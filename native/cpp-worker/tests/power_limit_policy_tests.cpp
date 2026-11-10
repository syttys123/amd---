#include "../src/power_limit_policy.hpp"
#include "../src/profile_catalog.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

namespace {

using amd_mobile_power::ApplyPowerLimitTarget;
using amd_mobile_power::IPowerLimitBackend;
using amd_mobile_power::PowerLimitApplicationResult;
using amd_mobile_power::PowerLimitTarget;

struct FakeBackend final : IPowerLimitBackend {
    double stapm = 45.0;
    double fast = 45.0;
    double slow = 45.0;
    int stapm_result = 0;
    int slow_result = 0;
    int refresh_result = 0;
    bool clamp_stapm_readback = false;
    std::vector<int> fast_results;
    std::vector<double> fast_readback_offsets;
    std::size_t fast_attempt = 0;
    std::vector<PowerLimitTarget> writes;

    int SetStapmLimit(std::uint32_t milliwatts) override {
        writes.push_back({
            static_cast<int>(milliwatts / 1000),
            fast_watts,
            slow_watts});
        if (stapm_result == 0) {
            stapm = clamp_stapm_readback
                ? std::min(stapm, 25.0)
                : static_cast<double>(milliwatts) / 1000.0;
        }
        return stapm_result;
    }

    int SetFastLimit(std::uint32_t milliwatts) override {
        fast_watts = static_cast<int>(milliwatts / 1000);
        const int result = fast_results.empty()
            ? 0
            : fast_results[
                std::min(fast_attempt, fast_results.size() - 1)];
        const double offset = fast_readback_offsets.empty()
            ? 0.0
            : fast_readback_offsets[
                std::min(fast_attempt, fast_readback_offsets.size() - 1)];
        ++fast_attempt;
        if (result == 0) {
            fast = static_cast<double>(milliwatts) / 1000.0 + offset;
        }
        return result;
    }

    int SetSlowLimit(std::uint32_t milliwatts) override {
        slow_watts = static_cast<int>(milliwatts / 1000);
        if (slow_result == 0) {
            slow = static_cast<double>(milliwatts) / 1000.0;
        }
        return slow_result;
    }

    int RefreshTable() override {
        return refresh_result;
    }

    std::optional<double> GetStapmLimit() override {
        return stapm;
    }

    std::optional<double> GetFastLimit() override {
        return fast;
    }

    std::optional<double> GetSlowLimit() override {
        return slow;
    }

    int fast_watts = 45;
    int slow_watts = 45;
};

bool Expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAILED: " << message << "\n";
        return false;
    }
    return true;
}

bool ApplySucceedsWithReadback() {
    FakeBackend backend;
    backend.clamp_stapm_readback = true;
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{20, 30, 40},
        5,
        60,
        true,
        true);
    return Expect(result.IsSuccessful(), "clamped STAPM should remain successful") &&
        Expect(result.readbacks.size() == 3, "apply should report three readbacks") &&
        Expect(
            std::abs(*result.readbacks[1].effective_watts - 30.0) < 0.01,
            "Fast readback should match") &&
        Expect(
            std::abs(*result.readbacks[2].effective_watts - 40.0) < 0.01,
            "Slow readback should match");
}

bool RejectedStapmDoesNotUndoFastAndSlow() {
    FakeBackend backend;
    backend.stapm_result = -1;
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{25, 20, 20},
        5,
        60,
        true,
        true);
    return Expect(result.IsSuccessful(), "rejected STAPM should not fail Fast/Slow") &&
        Expect(!result.restore_attempted, "rejected STAPM must not trigger restore") &&
        Expect(
            std::abs(*result.readbacks[1].effective_watts - 20.0) < 0.01,
            "Fast target should remain applied");
}

bool PartialWriteFailureRestoresPreviousTarget() {
    FakeBackend backend;
    backend.fast_results = {-2, 0};
    backend.fast_readback_offsets = {0, 0};
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{20, 30, 40},
        5,
        60,
        true,
        true);
    return Expect(!result.IsSuccessful(), "Fast write failure should fail the apply") &&
        Expect(result.restore_attempted, "failure should attempt restore") &&
        Expect(result.restored_previous_limits, "restore should read back exactly") &&
        Expect(
            std::abs(*backend.GetFastLimit() - 45.0) < 0.01,
            "restore should return Fast to prior value") &&
        Expect(
            backend.fast_watts == 45,
            "Fast should be restored to the previous target");
}

bool UnexpectedReadbackIncreaseRestoresPreviousTarget() {
    FakeBackend backend;
    backend.fast_results = {0, 0};
    backend.fast_readback_offsets = {2, 0};
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{20, 30, 40},
        5,
        60,
        true,
        true);
    return Expect(!result.IsSuccessful(), "readback above target should fail") &&
        Expect(result.restore_attempted, "readback failure should attempt restore") &&
        Expect(result.restored_previous_limits, "restore should succeed");
}

bool RestoreFailureIsReported() {
    FakeBackend backend;
    backend.fast_results = {-2, 0};
    backend.fast_readback_offsets = {2, 2};
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{20, 30, 40},
        5,
        60,
        true,
        true);
    return Expect(!result.IsSuccessful(), "failed restore should remain unsuccessful") &&
        Expect(result.restore_attempted, "failed restore should be attempted") &&
        Expect(
            !result.restored_previous_limits,
            "failed restore should be reported") &&
        Expect(
            result.error.has_value() &&
                result.error->find("Restore failed") != std::string::npos,
            "error should explain restore failure");
}

bool InvalidTargetIsRejectedBeforeWrite() {
    FakeBackend backend;
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{4, 30, 40},
        5,
        60,
        true,
        true);
    return Expect(!result.IsSuccessful(), "out-of-range target should be rejected") &&
        Expect(backend.writes.empty(), "invalid target must not write");
}

bool UnsupportedFastIsRejectedBeforeWrite() {
    FakeBackend backend;
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{20, 30, 40},
        5,
        60,
        false,
        true);
    return Expect(!result.IsSuccessful(), "unsupported Fast should be rejected") &&
        Expect(backend.writes.empty(), "unsupported target must not write");
}

bool InvalidPreviousReadbackIsRejectedBeforeWrite() {
    FakeBackend backend;
    backend.fast = 0.0;
    const PowerLimitApplicationResult result = ApplyPowerLimitTarget(
        backend,
        PowerLimitTarget{20, 30, 40},
        5,
        60,
        true,
        true);
    return Expect(!result.IsSuccessful(), "invalid previous readback should fail") &&
        Expect(backend.writes.empty(), "previous invalid state must not write");
}

bool ProfileCatalogSelectsVerifiedAndConservativeFamilies() {
    const auto* development = amd_mobile_power::FindPlatformProfile(
        10,
        "AMD Ryzen 7 8845HS",
        "4c0009");
    const auto* generic_hawk = amd_mobile_power::FindPlatformProfile(
        10,
        "AMD Ryzen 5 8640HS",
        "4c0009");
    const auto* phoenix = amd_mobile_power::FindPlatformProfile(
        9,
        "AMD Ryzen 7 7840U",
        "unknown");
    const auto* renoir = amd_mobile_power::FindPlatformProfile(
        3,
        "AMD Ryzen 5 5500U",
        "unknown");
    const auto* unknown = amd_mobile_power::FindPlatformProfile(
        99,
        "AMD Unknown",
        "unknown");

    return Expect(
               development != nullptr &&
                   development->id == "hawk-point-8845hs" &&
                   development->maximum_watts == 60 &&
                   development->verified,
               "8845HS should select the verified development profile") &&
        Expect(
            generic_hawk != nullptr &&
                generic_hawk->id == "ryzenadj-hawk-point" &&
                generic_hawk->maximum_watts == 45 &&
                !generic_hawk->verified,
            "generic Hawk Point should remain conservative") &&
        Expect(
            phoenix != nullptr &&
                phoenix->id == "ryzenadj-phoenix",
            "Phoenix family should map to a profile") &&
        Expect(
            renoir != nullptr &&
                renoir->id == "ryzenadj-renoir-cezanne",
            "Renoir/Cezanne family should map to a profile") &&
        Expect(
            unknown == nullptr,
            "unknown family must remain unsupported");
}

}  // namespace

int main() {
    const bool passed =
        ApplySucceedsWithReadback() &&
        RejectedStapmDoesNotUndoFastAndSlow() &&
        PartialWriteFailureRestoresPreviousTarget() &&
        UnexpectedReadbackIncreaseRestoresPreviousTarget() &&
        RestoreFailureIsReported() &&
        InvalidTargetIsRejectedBeforeWrite() &&
        UnsupportedFastIsRejectedBeforeWrite() &&
        InvalidPreviousReadbackIsRejectedBeforeWrite() &&
        ProfileCatalogSelectsVerifiedAndConservativeFamilies();
    if (!passed) {
        return 1;
    }
    std::cout << "power_limit_policy_tests: PASS\n";
    return 0;
}
