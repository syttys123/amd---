#include "power_limit_policy.hpp"

#include <cmath>
#include <iomanip>
#include <sstream>

namespace amd_mobile_power {

namespace {

struct WriteAttempt {
    std::vector<PowerLimitReadback> readbacks;
    std::optional<std::string> error;

    bool IsSuccessful() const {
        return !error.has_value();
    }
};

bool IsValidTarget(int watts) {
    return watts >= kMinimumTargetWatts && watts <= kMaximumTargetWatts;
}

bool IsRestorable(int watts) {
    return watts >= kMinimumRestoreWatts && watts <= kMaximumRestoreWatts;
}

int RoundReadback(double watts) {
    return static_cast<int>(std::lround(watts));
}

std::optional<double> FiniteValue(std::optional<double> value) {
    return value.has_value() && std::isfinite(*value) ? value : std::nullopt;
}

std::string FormatWatts(double watts) {
    std::ostringstream output;
    output << std::fixed << std::setprecision(2) << watts;
    return output.str();
}

std::optional<PowerLimitTarget> ReadPreviousTarget(
    IPowerLimitBackend& backend,
    std::string& error) {
    const auto stapm = FiniteValue(backend.GetStapmLimit());
    const auto fast = FiniteValue(backend.GetFastLimit());
    const auto slow = FiniteValue(backend.GetSlowLimit());
    if (!stapm || !fast || !slow) {
        error = "STAPM, Fast, or Slow limits are missing.";
        return std::nullopt;
    }

    const PowerLimitTarget target{
        RoundReadback(*stapm),
        RoundReadback(*fast),
        RoundReadback(*slow)};
    if (!IsRestorable(target.stapm_watts) ||
        !IsRestorable(target.fast_watts) ||
        !IsRestorable(target.slow_watts)) {
        std::ostringstream message;
        message
            << "Read-back values must be between " << kMinimumRestoreWatts
            << "W and " << kMaximumRestoreWatts << "W; received "
            << FormatWatts(*stapm) << "/" << FormatWatts(*fast) << "/"
            << FormatWatts(*slow) << "W.";
        error = message.str();
        return std::nullopt;
    }
    return target;
}

PowerLimitReadback CreateReadback(
    PowerLimitKind kind,
    int requested_watts,
    int driver_result,
    std::optional<double> effective_watts) {
    return PowerLimitReadback{
        kind,
        requested_watts,
        driver_result,
        FiniteValue(effective_watts)};
}

WriteAttempt WriteTarget(
    IPowerLimitBackend& backend,
    const PowerLimitTarget& target,
    bool require_exact_readback) {
    WriteAttempt attempt;
    const int stapm_result = backend.SetStapmLimit(
        static_cast<std::uint32_t>(target.stapm_watts * 1000));
    const int fast_result = backend.SetFastLimit(
        static_cast<std::uint32_t>(target.fast_watts * 1000));
    const int slow_result = backend.SetSlowLimit(
        static_cast<std::uint32_t>(target.slow_watts * 1000));
    const int refresh_result = backend.RefreshTable();

    attempt.readbacks = {
        CreateReadback(
            PowerLimitKind::Stapm,
            target.stapm_watts,
            stapm_result,
            refresh_result == 0 ? backend.GetStapmLimit() : std::nullopt),
        CreateReadback(
            PowerLimitKind::Fast,
            target.fast_watts,
            fast_result,
            refresh_result == 0 ? backend.GetFastLimit() : std::nullopt),
        CreateReadback(
            PowerLimitKind::Slow,
            target.slow_watts,
            slow_result,
            refresh_result == 0 ? backend.GetSlowLimit() : std::nullopt)};

    std::vector<std::string> errors;
    for (const auto& readback : attempt.readbacks) {
        if (readback.kind == PowerLimitKind::Stapm) {
            // Firmware may manage STAPM dynamically or reject it independently
            // of the PPT Fast/Slow caps that enforce the requested ceiling.
            continue;
        }

        if (readback.driver_result != 0) {
            errors.push_back(
                std::string(PowerLimitKindName(readback.kind)) +
                " write returned " +
                std::to_string(readback.driver_result) + ".");
            continue;
        }
        if (!readback.effective_watts) {
            errors.push_back(
                std::string(PowerLimitKindName(readback.kind)) +
                " read-back is unavailable.");
            continue;
        }
        if (*readback.effective_watts <= 0) {
            errors.push_back(
                std::string(PowerLimitKindName(readback.kind)) +
                " read back an invalid value of " +
                FormatWatts(*readback.effective_watts) + "W.");
            continue;
        }

        const double difference =
            *readback.effective_watts - readback.requested_watts;
        const bool increased = difference > kReadbackToleranceWatts;
        const bool invalid = require_exact_readback
            ? std::abs(difference) > kReadbackToleranceWatts
            : increased;
        if (invalid) {
            errors.push_back(
                std::string(PowerLimitKindName(readback.kind)) +
                " requested " + std::to_string(readback.requested_watts) +
                "W but read back " +
                FormatWatts(*readback.effective_watts) + "W.");
        }
    }

    if (refresh_result != 0) {
        errors.push_back(
            "RyzenAdj refresh_table failed with code " +
            std::to_string(refresh_result) + ".");
    }

    if (!errors.empty()) {
        std::ostringstream message;
        for (std::size_t index = 0; index < errors.size(); ++index) {
            if (index != 0) {
                message << ' ';
            }
            message << errors[index];
        }
        attempt.error = message.str();
    }
    return attempt;
}

}  // namespace

const char* PowerLimitKindName(PowerLimitKind kind) {
    switch (kind) {
    case PowerLimitKind::Stapm:
        return "STAPM";
    case PowerLimitKind::Fast:
        return "Fast";
    case PowerLimitKind::Slow:
        return "Slow";
    }
    return "Unknown";
}

std::optional<std::string> ValidatePowerLimitTarget(
    const PowerLimitTarget& target,
    bool supports_fast,
    bool supports_slow) {
    const auto validate = [](const char* name, int watts) -> std::optional<std::string> {
        if (IsValidTarget(watts)) {
            return std::nullopt;
        }
        return std::string(name) + ": Power must be between " +
            std::to_string(kMinimumTargetWatts) + "W and " +
            std::to_string(kMaximumTargetWatts) + "W.";
    };

    if (const auto error = validate("STAPM", target.stapm_watts)) {
        return error;
    }
    if (const auto error = validate("Fast", target.fast_watts)) {
        return error;
    }
    if (const auto error = validate("Slow", target.slow_watts)) {
        return error;
    }
    if (!supports_fast || !supports_slow) {
        std::string names;
        if (!supports_fast) {
            names = "Fast";
        }
        if (!supports_slow) {
            if (!names.empty()) {
                names += ", ";
            }
            names += "Slow";
        }
        return "The platform does not support these required power limits: " +
            names + ".";
    }
    return std::nullopt;
}

PowerLimitApplicationResult ApplyPowerLimitTarget(
    IPowerLimitBackend& backend,
    const PowerLimitTarget& target,
    bool supports_fast,
    bool supports_slow) {
    PowerLimitApplicationResult result;
    result.target = target;
    if (const auto validation =
            ValidatePowerLimitTarget(target, supports_fast, supports_slow)) {
        result.error = validation;
        return result;
    }

    const int refresh_result = backend.RefreshTable();
    if (refresh_result != 0) {
        result.error =
            "RyzenAdj refresh_table failed with code " +
            std::to_string(refresh_result) + ".";
        return result;
    }

    std::string previous_error;
    const auto previous = ReadPreviousTarget(backend, previous_error);
    if (!previous) {
        result.error =
            "Previous power limits cannot be verified safely: " +
            previous_error;
        return result;
    }
    result.previous = *previous;

    const WriteAttempt applied = WriteTarget(
        backend,
        target,
        false);
    result.readbacks = applied.readbacks;
    if (applied.IsSuccessful()) {
        return result;
    }

    result.restore_attempted = true;
    const WriteAttempt restored = WriteTarget(
        backend,
        result.previous,
        true);
    result.restore_readbacks = restored.readbacks;
    result.restored_previous_limits = restored.IsSuccessful();
    result.error = *applied.error;
    if (!restored.IsSuccessful()) {
        result.error = result.error.value() +
            " Restore failed: " + restored.error.value();
    }
    return result;
}

}  // namespace amd_mobile_power
