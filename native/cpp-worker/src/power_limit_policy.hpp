#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace amd_mobile_power {

constexpr int kMinimumRestoreWatts = 1;
constexpr int kMaximumRestoreWatts = 200;
constexpr double kReadbackToleranceWatts = 0.75;

struct PowerLimitTarget {
    int stapm_watts = 0;
    int fast_watts = 0;
    int slow_watts = 0;
};

enum class PowerLimitKind {
    Stapm,
    Fast,
    Slow,
};

const char* PowerLimitKindName(PowerLimitKind kind);

struct PowerLimitReadback {
    PowerLimitKind kind = PowerLimitKind::Stapm;
    int requested_watts = 0;
    int driver_result = 0;
    std::optional<double> effective_watts;
};

struct PowerLimitApplicationResult {
    PowerLimitTarget target;
    PowerLimitTarget previous;
    std::vector<PowerLimitReadback> readbacks;
    std::vector<PowerLimitReadback> restore_readbacks;
    bool restore_attempted = false;
    bool restored_previous_limits = false;
    std::optional<std::string> error;

    bool IsSuccessful() const {
        return !error.has_value();
    }
};

class IPowerLimitBackend {
public:
    virtual ~IPowerLimitBackend() = default;

    virtual int SetStapmLimit(std::uint32_t milliwatts) = 0;
    virtual int SetFastLimit(std::uint32_t milliwatts) = 0;
    virtual int SetSlowLimit(std::uint32_t milliwatts) = 0;
    virtual int RefreshTable() = 0;
    virtual std::optional<double> GetStapmLimit() = 0;
    virtual std::optional<double> GetFastLimit() = 0;
    virtual std::optional<double> GetSlowLimit() = 0;
};

std::optional<std::string> ValidatePowerLimitTarget(
    const PowerLimitTarget& target,
    int minimum_watts,
    int maximum_watts,
    bool supports_fast,
    bool supports_slow);

PowerLimitApplicationResult ApplyPowerLimitTarget(
    IPowerLimitBackend& backend,
    const PowerLimitTarget& target,
    int minimum_watts,
    int maximum_watts,
    bool supports_fast,
    bool supports_slow);

}  // namespace amd_mobile_power
