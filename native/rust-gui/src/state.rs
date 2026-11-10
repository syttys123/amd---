use crate::worker::PowerPolicySettings;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
struct PersistedUiState {
    #[serde(default)]
    power_policy: Option<PowerPolicySettings>,
    #[serde(default = "default_presets")]
    presets: [i32; 3],
}

impl Default for PersistedUiState {
    fn default() -> Self {
        Self {
            power_policy: None,
            presets: default_presets(),
        }
    }
}

fn default_presets() -> [i32; 3] {
    [12, 25, 45]
}

fn sanitize_presets(presets: [i32; 3]) -> [i32; 3] {
    if presets.iter().all(|watts| (1..=255).contains(watts)) {
        presets
    } else {
        default_presets()
    }
}

fn state_path() -> Option<PathBuf> {
    let local_app_data = std::env::var_os("LOCALAPPDATA")?;
    Some(
        PathBuf::from(local_app_data)
            .join("AmdMobilePower")
            .join("rust-ui-state.json"),
    )
}

fn load_state() -> Option<PersistedUiState> {
    let path = state_path()?;
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str::<PersistedUiState>(&contents).ok()
}

pub fn load_power_policy() -> Option<PowerPolicySettings> {
    load_state()?.power_policy
}

pub fn load_presets() -> [i32; 3] {
    sanitize_presets(
        load_state()
            .map(|state| state.presets)
            .unwrap_or_else(default_presets),
    )
}

pub fn save_power_policy(settings: PowerPolicySettings) -> Result<(), String> {
    update_state(|state| state.power_policy = Some(settings))
}

pub fn save_presets(presets: [i32; 3]) -> Result<(), String> {
    let presets = sanitize_presets(presets);
    update_state(|state| state.presets = presets)
}

fn update_state(update: impl FnOnce(&mut PersistedUiState)) -> Result<(), String> {
    let path = state_path().ok_or_else(|| {
        "LOCALAPPDATA is unavailable; UI settings cannot be persisted.".to_owned()
    })?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("unable to create {}: {error}", parent.display()))?;
    }
    let mut state = load_state().unwrap_or_default();
    update(&mut state);
    let contents = serde_json::to_string_pretty(&state)
        .map_err(|error| format!("unable to serialize UI state: {error}"))?;
    std::fs::write(&path, contents)
        .map_err(|error| format!("unable to write {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::{default_presets, sanitize_presets, PersistedUiState};
    use crate::worker::{PowerLimitTarget, PowerPolicySettings};

    #[test]
    fn persisted_state_round_trips_policy_settings() {
        let settings = PowerPolicySettings {
            enabled: true,
            battery_target: PowerLimitTarget::uniform(12),
            ac_target: PowerLimitTarget::uniform(45),
        };
        let encoded = serde_json::to_string(&PersistedUiState {
            power_policy: Some(settings),
            presets: [10, 20, 40],
        })
        .unwrap();
        let decoded: PersistedUiState = serde_json::from_str(&encoded).unwrap();
        assert_eq!(decoded.power_policy, Some(settings));
        assert_eq!(decoded.presets, [10, 20, 40]);
    }

    #[test]
    fn legacy_policy_state_gets_default_presets() {
        let decoded: PersistedUiState = serde_json::from_str(
            r#"{"powerPolicy":{"enabled":true,"batteryTarget":{"stapmWatts":10,"fastWatts":10,"slowWatts":10},"acTarget":{"stapmWatts":45,"fastWatts":45,"slowWatts":45}}}"#,
        )
        .unwrap();

        assert!(decoded.power_policy.is_some());
        assert_eq!(decoded.presets, default_presets());
    }

    #[test]
    fn presets_do_not_require_a_saved_policy() {
        let decoded: PersistedUiState = serde_json::from_str(r#"{"presets":[11,22,44]}"#).unwrap();

        assert_eq!(decoded.power_policy, None);
        assert_eq!(decoded.presets, [11, 22, 44]);
    }

    #[test]
    fn corrupt_presets_fall_back_to_defaults() {
        assert_eq!(sanitize_presets([0, 25, 45]), default_presets());
        assert_eq!(sanitize_presets([12, 25, 256]), default_presets());
        assert_eq!(sanitize_presets([10, 20, 40]), [10, 20, 40]);
    }
}
