#pragma once

#include "power_limit_policy.hpp"
#include "ryzen_hardware.hpp"

#include <chrono>
#include <optional>
#include <string>

namespace amd_mobile_power {

enum class PowerLineState {
    Unknown,
    Ac,
    Battery,
};

const char* PowerLineStateName(PowerLineState state);

struct PowerPolicySettings {
    bool enabled = false;
    PowerLimitTarget battery_target;
    PowerLimitTarget ac_target;
    bool battery_enabled = true;
    bool ac_enabled = true;
};

struct PowerPolicyState {
    std::optional<PowerPolicySettings> settings;
    std::optional<PowerLineState> last_observed_power_line;
    std::optional<PowerLimitTarget> last_applied_target;
    std::optional<std::string> last_attempt_at;
    std::optional<bool> last_attempt_succeeded;
    std::optional<std::string> last_error;
};

struct PowerPolicyObservation {
    PlatformCapability platform;
    PowerLineState power_line = PowerLineState::Unknown;
};

class IPowerPolicyBackend {
public:
    virtual ~IPowerPolicyBackend() = default;

    virtual bool Observe(
        PowerPolicyObservation& observation,
        std::string& error) = 0;
    virtual PowerLimitApplicationResult ApplyTarget(
        const PowerLimitTarget& target,
        const PlatformCapability& capability) = 0;
};

class PowerPolicyController {
public:
    void SetSettings(const PowerPolicySettings& settings);
    const std::optional<PowerPolicySettings>& settings() const;
    const PowerPolicyState& state() const;

    void Tick(
        IPowerPolicyBackend& backend,
        std::chrono::steady_clock::time_point now,
        const std::string& timestamp);

private:
    bool ShouldAttempt(
        PowerLineState power_line,
        const PowerLimitTarget& target,
        std::chrono::steady_clock::time_point now);
    void RecordAttempt(
        PowerLineState power_line,
        const PowerLimitTarget& target,
        bool succeeded,
        const std::optional<std::string>& error,
        std::chrono::steady_clock::time_point now,
        const std::string& timestamp);
    void RecordFailure(
        std::optional<PowerLineState> power_line,
        const std::string& error,
        std::chrono::steady_clock::time_point now,
        const std::string& timestamp);

    std::optional<PowerPolicySettings> settings_;
    PowerPolicyState state_;
    std::optional<PowerLineState> last_applied_power_line_;
    std::optional<PowerLimitTarget> last_applied_target_;
    std::optional<PowerLineState> last_attempt_power_line_;
    std::optional<PowerLimitTarget> last_attempt_target_;
    std::optional<std::chrono::steady_clock::time_point> last_failure_at_;
};

}  // namespace amd_mobile_power
