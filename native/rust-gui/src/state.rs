use crate::worker::PowerPolicySettings;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
struct PersistedUiState {
    power_policy: PowerPolicySettings,
}

fn state_path() -> Option<PathBuf> {
    let local_app_data = std::env::var_os("LOCALAPPDATA")?;
    Some(
        PathBuf::from(local_app_data)
            .join("AmdMobilePower")
            .join("rust-ui-state.json"),
    )
}

pub fn load_power_policy() -> Option<PowerPolicySettings> {
    let path = state_path()?;
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str::<PersistedUiState>(&contents)
        .ok()
        .map(|state| state.power_policy)
}

pub fn save_power_policy(settings: PowerPolicySettings) -> Result<(), String> {
    let path = state_path().ok_or_else(|| {
        "LOCALAPPDATA is unavailable; the policy cannot be persisted.".to_owned()
    })?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("unable to create {}: {error}", parent.display()))?;
    }
    let contents = serde_json::to_string_pretty(&PersistedUiState {
        power_policy: settings,
    })
    .map_err(|error| format!("unable to serialize policy state: {error}"))?;
    std::fs::write(&path, contents)
        .map_err(|error| format!("unable to write {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::PersistedUiState;
    use crate::worker::{PowerLimitTarget, PowerPolicySettings};

    #[test]
    fn persisted_state_round_trips_policy_settings() {
        let settings = PowerPolicySettings {
            enabled: true,
            battery_target: PowerLimitTarget::uniform(12),
            ac_target: PowerLimitTarget::uniform(45),
        };
        let encoded = serde_json::to_string(&PersistedUiState {
            power_policy: settings,
        })
        .unwrap();
        let decoded: PersistedUiState = serde_json::from_str(&encoded).unwrap();
        assert_eq!(decoded.power_policy, settings);
    }
}
