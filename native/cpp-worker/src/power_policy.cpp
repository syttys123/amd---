#include "power_policy.hpp"

namespace amd_mobile_power {

namespace {

constexpr auto kFailureBackoff = std::chrono::seconds(5);

}  // namespace

const char* PowerLineStateName(PowerLineState state) {
    switch (state) {
    case PowerLineState::Unknown:
        return "unknown";
    case PowerLineState::Ac:
        return "ac";
    case PowerLineState::Battery:
        return "battery";
    }
    return "unknown";
}

void PowerPolicyController::SetSettings(const PowerPolicySettings& settings) {
    settings_ = settings;
    state_ = PowerPolicyState{};
    state_.settings = settings;
    last_applied_power_line_.reset();
    last_applied_target_.reset();
    last_attempt_power_line_.reset();
    last_attempt_target_.reset();
    last_failure_at_.reset();
}

const std::optional<PowerPolicySettings>& PowerPolicyController::settings() const {
    return settings_;
}

const PowerPolicyState& PowerPolicyController::state() const {
    return state_;
}

void PowerPolicyController::Tick(
    IPowerPolicyBackend& backend,
    std::chrono::steady_clock::time_point now,
    const std::string& timestamp) {
    if (!settings_ || !settings_->enabled) {
        return;
    }

    PowerPolicyObservation observation;
    std::string observe_error;
    if (!backend.Observe(observation, observe_error)) {
        RecordFailure(
            state_.last_observed_power_line,
            observe_error.empty() ? "Power policy observation failed." : observe_error,
            now,
            timestamp);
        return;
    }
    state_.last_observed_power_line = observation.power_line;

    if (!observation.platform.is_supported || !observation.platform.profile) {
        RecordFailure(
            observation.power_line,
            observation.platform.unsupported_reason.value_or(
                "The platform has no supported power profile."),
            now,
            timestamp);
        return;
    }
    if (observation.power_line == PowerLineState::Unknown) {
        RecordFailure(
            observation.power_line,
            "Power-line state is unknown.",
            now,
            timestamp);
        return;
    }

    const PowerLimitTarget target =
        observation.power_line == PowerLineState::Ac
        ? settings_->ac_target
        : settings_->battery_target;
    if (!ShouldAttempt(observation.power_line, target, now)) {
        return;
    }

    const PowerLimitApplicationResult result =
        backend.ApplyTarget(target, observation.platform);
    RecordAttempt(
        observation.power_line,
        target,
        result.IsSuccessful(),
        result.error,
        now,
        timestamp);
}

bool PowerPolicyController::ShouldAttempt(
    PowerLineState power_line,
    const PowerLimitTarget& target,
    std::chrono::steady_clock::time_point now) {
    if (last_applied_power_line_ == power_line &&
        last_applied_target_ == target) {
        return false;
    }

    if (last_attempt_power_line_ == power_line &&
        last_attempt_target_ == target &&
        last_failure_at_ &&
        now - *last_failure_at_ < kFailureBackoff) {
        return false;
    }

    last_attempt_power_line_ = power_line;
    last_attempt_target_ = target;
    return true;
}

void PowerPolicyController::RecordAttempt(
    PowerLineState power_line,
    const PowerLimitTarget& target,
    bool succeeded,
    const std::optional<std::string>& error,
    std::chrono::steady_clock::time_point now,
    const std::string& timestamp) {
    if (succeeded) {
        last_applied_power_line_ = power_line;
        last_applied_target_ = target;
        last_failure_at_.reset();
        state_.last_applied_target = target;
        state_.last_error.reset();
    } else {
        last_failure_at_ = now;
        state_.last_error = error.value_or("Power policy application failed.");
    }

    state_.settings = settings_;
    state_.last_observed_power_line = power_line;
    state_.last_attempt_at = timestamp;
    state_.last_attempt_succeeded = succeeded;
}

void PowerPolicyController::RecordFailure(
    std::optional<PowerLineState> power_line,
    const std::string& error,
    std::chrono::steady_clock::time_point now,
    const std::string& timestamp) {
    last_failure_at_ = now;
    state_.settings = settings_;
    if (power_line) {
        state_.last_observed_power_line = *power_line;
    }
    state_.last_attempt_at = timestamp;
    state_.last_attempt_succeeded = false;
    state_.last_error = error;
}

}  // namespace amd_mobile_power
