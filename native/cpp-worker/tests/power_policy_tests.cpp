#include "../src/power_policy.hpp"

#include <chrono>
#include <iostream>
#include <optional>
#include <string>

namespace {

using amd_mobile_power::IPowerPolicyBackend;
using amd_mobile_power::PlatformCapability;
using amd_mobile_power::PowerLimitApplicationResult;
using amd_mobile_power::PowerLimitTarget;
using amd_mobile_power::PowerLineState;
using amd_mobile_power::PowerPolicyController;
using amd_mobile_power::PowerPolicyObservation;
using amd_mobile_power::PowerPolicySettings;

struct FakePolicyBackend final : IPowerPolicyBackend {
    PlatformCapability capability;
    PowerLineState power_line = PowerLineState::Battery;
    bool observe_failure = false;
    bool apply_failure = false;
    int observe_count = 0;
    int apply_count = 0;
    std::optional<PowerLimitTarget> last_target;

    bool Observe(
        PowerPolicyObservation& observation,
        std::string& error) override {
        ++observe_count;
        if (observe_failure) {
            error = "observation failed";
            return false;
        }
        observation.platform = capability;
        observation.power_line = power_line;
        return true;
    }

    PowerLimitApplicationResult ApplyTarget(
        const PowerLimitTarget& target,
        const PlatformCapability&) override {
        ++apply_count;
        last_target = target;
        PowerLimitApplicationResult result;
        result.target = target;
        if (apply_failure) {
            result.error = "apply failed";
        }
        return result;
    }
};

bool Expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAILED: " << message << "\n";
        return false;
    }
    return true;
}

PlatformCapability SupportedCapability() {
    PlatformCapability capability;
    capability.is_supported = true;
    capability.profile = amd_mobile_power::ProfileInfo{
        "test-profile",
        "Test profile",
        5,
        60,
        25,
        true};
    capability.limits.supports_stapm = true;
    capability.limits.supports_fast = true;
    capability.limits.supports_slow = true;
    return capability;
}

bool AppliesBatteryThenAcWhenPowerLineChanges() {
    FakePolicyBackend backend;
    backend.capability = SupportedCapability();
    PowerPolicyController controller;
    controller.SetSettings(PowerPolicySettings{
        true,
        PowerLimitTarget::uniform(12),
        PowerLimitTarget::uniform(45)});

    const auto start = std::chrono::steady_clock::now();
    controller.Tick(backend, start, "2026-11-10T00:00:00Z");
    const bool battery_applied =
        backend.apply_count == 1 &&
        backend.last_target == std::optional<PowerLimitTarget>(
            PowerLimitTarget::uniform(12)) &&
        controller.state().last_observed_power_line ==
            std::optional<PowerLineState>(PowerLineState::Battery) &&
        controller.state().last_attempt_succeeded == std::optional<bool>(true);

    controller.Tick(
        backend,
        start + std::chrono::seconds(1),
        "2026-11-10T00:00:01Z");
    const bool unchanged_is_not_reapplied = backend.apply_count == 1;

    backend.power_line = PowerLineState::Ac;
    controller.Tick(
        backend,
        start + std::chrono::seconds(2),
        "2026-11-10T00:00:02Z");
    const bool ac_applied =
        backend.apply_count == 2 &&
        backend.last_target == std::optional<PowerLimitTarget>(
            PowerLimitTarget::uniform(45)) &&
        controller.state().last_applied_target ==
            std::optional<PowerLimitTarget>(PowerLimitTarget::uniform(45));

    return Expect(battery_applied, "battery target should be applied first") &&
        Expect(
            unchanged_is_not_reapplied,
            "the same power line should not be written repeatedly") &&
        Expect(ac_applied, "AC target should be applied after a power-line change");
}

bool RetriesFailedPolicyAfterBackoff() {
    FakePolicyBackend backend;
    backend.capability = SupportedCapability();
    backend.apply_failure = true;
    PowerPolicyController controller;
    controller.SetSettings(PowerPolicySettings{
        true,
        PowerLimitTarget::uniform(12),
        PowerLimitTarget::uniform(45)});

    const auto start = std::chrono::steady_clock::now();
    controller.Tick(backend, start, "2026-11-10T00:00:00Z");
    const bool first_failure_is_reported =
        backend.apply_count == 1 &&
        controller.state().last_attempt_succeeded == std::optional<bool>(false) &&
        controller.state().last_error == std::optional<std::string>("apply failed");

    controller.Tick(
        backend,
        start + std::chrono::seconds(1),
        "2026-11-10T00:00:01Z");
    const bool backoff_skips_retry = backend.apply_count == 1;

    controller.Tick(
        backend,
        start + std::chrono::seconds(6),
        "2026-11-10T00:00:06Z");
    const bool retry_after_backoff = backend.apply_count == 2;

    return Expect(first_failure_is_reported, "first policy failure should be reported") &&
        Expect(backoff_skips_retry, "a failed policy target should back off") &&
        Expect(retry_after_backoff, "a failed policy target should retry after five seconds");
}

bool DisabledPolicyDoesNotTouchHardware() {
    FakePolicyBackend backend;
    backend.capability = SupportedCapability();
    PowerPolicyController controller;
    controller.SetSettings(PowerPolicySettings{
        false,
        PowerLimitTarget::uniform(12),
        PowerLimitTarget::uniform(45)});

    controller.Tick(
        backend,
        std::chrono::steady_clock::now(),
        "2026-11-10T00:00:00Z");
    return Expect(backend.observe_count == 0, "disabled policy should not observe hardware") &&
        Expect(backend.apply_count == 0, "disabled policy should not apply a target");
}

bool UnknownPowerLineIsRejected() {
    FakePolicyBackend backend;
    backend.capability = SupportedCapability();
    backend.power_line = PowerLineState::Unknown;
    PowerPolicyController controller;
    controller.SetSettings(PowerPolicySettings{
        true,
        PowerLimitTarget::uniform(12),
        PowerLimitTarget::uniform(45)});

    controller.Tick(
        backend,
        std::chrono::steady_clock::now(),
        "2026-11-10T00:00:00Z");
    return Expect(backend.apply_count == 0, "unknown power line should not apply a target") &&
        Expect(
            controller.state().last_attempt_succeeded == std::optional<bool>(false),
            "unknown power line should be surfaced as a policy failure");
}

bool BatteryOnlyPolicySkipsAcAndAppliesOnBattery() {
    FakePolicyBackend backend;
    backend.capability = SupportedCapability();
    backend.power_line = PowerLineState::Ac;
    PowerPolicyController controller;
    PowerPolicySettings settings;
    settings.enabled = true;
    settings.battery_target = PowerLimitTarget::uniform(10);
    settings.ac_target = PowerLimitTarget::uniform(45);
    settings.battery_enabled = true;
    settings.ac_enabled = false;
    controller.SetSettings(settings);

    const auto start = std::chrono::steady_clock::now();
    controller.Tick(backend, start, "2026-11-11T00:00:00Z");
    const bool ac_skipped =
        backend.apply_count == 0 &&
        controller.state().last_observed_power_line ==
            std::optional<PowerLineState>(PowerLineState::Ac) &&
        !controller.state().last_attempt_succeeded.has_value();

    backend.power_line = PowerLineState::Battery;
    controller.Tick(
        backend,
        start + std::chrono::seconds(1),
        "2026-11-11T00:00:01Z");
    const bool battery_applied =
        backend.apply_count == 1 &&
        backend.last_target == std::optional<PowerLimitTarget>(
            PowerLimitTarget::uniform(10)) &&
        controller.state().last_attempt_succeeded == std::optional<bool>(true);

    return Expect(ac_skipped, "battery-only policy should not touch AC") &&
        Expect(
            battery_applied,
            "battery-only policy should still apply on battery");
}

}  // namespace

int main() {
    const bool passed =
        AppliesBatteryThenAcWhenPowerLineChanges() &&
        RetriesFailedPolicyAfterBackoff() &&
        DisabledPolicyDoesNotTouchHardware() &&
        UnknownPowerLineIsRejected() &&
        BatteryOnlyPolicySkipsAcAndAppliesOnBattery();
    if (!passed) {
        return 1;
    }
    std::cout << "power_policy_tests: PASS\n";
    return 0;
}
