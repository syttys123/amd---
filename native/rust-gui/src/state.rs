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
    #[serde(default)]
    mode: UiMode,
    #[serde(default)]
    top_most: bool,
    #[serde(default)]
    max_target_watts: Option<i32>,
}

impl Default for PersistedUiState {
    fn default() -> Self {
        Self {
            power_policy: None,
            presets: default_presets(),
            mode: UiMode::default(),
            top_most: false,
            max_target_watts: None,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum UiMode {
    #[default]
    Simple,
    Advanced,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowPreferences {
    pub mode: UiMode,
    pub top_most: bool,
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

pub fn load_window_preferences() -> WindowPreferences {
    load_state()
        .map(|state| WindowPreferences {
            mode: state.mode,
            top_most: state.top_most,
        })
        .unwrap_or(WindowPreferences {
            mode: UiMode::Simple,
            top_most: false,
        })
}

/// Optional per-installation hard ceiling for the target power. The GUI and the
/// worker target are clamped to it, so a user who pins the ceiling to 12 W
/// cannot raise the package limit any higher from the UI.
pub fn load_max_target_watts() -> Option<i32> {
    load_state()?.max_target_watts.filter(|watts| *watts > 0)
}

pub fn save_max_target_watts(watts: i32) -> Result<(), String> {
    update_state(|state| state.max_target_watts = Some(watts.max(1)))
}

pub fn save_power_policy(settings: PowerPolicySettings) -> Result<(), String> {
    update_state(|state| state.power_policy = Some(settings))
}

pub fn save_presets(presets: [i32; 3]) -> Result<(), String> {
    let presets = sanitize_presets(presets);
    update_state(|state| state.presets = presets)
}

pub fn save_window_preferences(preferences: WindowPreferences) -> Result<(), String> {
    update_state(|state| {
        state.mode = preferences.mode;
        state.top_most = preferences.top_most;
    })
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
    use super::{default_presets, sanitize_presets, PersistedUiState, UiMode, WindowPreferences};
    use crate::worker::{PowerLimitTarget, PowerPolicySettings};

    #[test]
    fn persisted_state_round_trips_policy_settings() {
        let settings = PowerPolicySettings {
            enabled: true,
            battery_enabled: true,
            ac_enabled: false,
            battery_target: PowerLimitTarget::uniform(12),
            ac_target: PowerLimitTarget::uniform(45),
        };
        let encoded = serde_json::to_string(&PersistedUiState {
            power_policy: Some(settings),
            presets: [10, 20, 40],
            mode: UiMode::Simple,
            top_most: true,
            max_target_watts: None,
        })
        .unwrap();
        let decoded: PersistedUiState = serde_json::from_str(&encoded).unwrap();
        assert_eq!(decoded.power_policy, Some(settings));
        assert_eq!(decoded.presets, [10, 20, 40]);
        assert_eq!(decoded.mode, UiMode::Simple);
        assert!(decoded.top_most);
        assert!(decoded.power_policy.unwrap().battery_enabled);
        assert!(!decoded.power_policy.unwrap().ac_enabled);
    }

    #[test]
    fn legacy_policy_state_gets_default_presets() {
        let decoded: PersistedUiState = serde_json::from_str(
            r#"{"powerPolicy":{"enabled":true,"batteryTarget":{"stapmWatts":10,"fastWatts":10,"slowWatts":10},"acTarget":{"stapmWatts":45,"fastWatts":45,"slowWatts":45}}}"#,
        )
        .unwrap();

        assert!(decoded.power_policy.is_some());
        assert_eq!(decoded.presets, default_presets());
        assert_eq!(decoded.mode, UiMode::Simple);
        assert!(!decoded.top_most);
    }

    #[test]
    fn presets_do_not_require_a_saved_policy() {
        let decoded: PersistedUiState = serde_json::from_str(r#"{"presets":[11,22,44]}"#).unwrap();

        assert_eq!(decoded.power_policy, None);
        assert_eq!(decoded.presets, [11, 22, 44]);
        assert_eq!(decoded.mode, UiMode::Simple);
        assert!(!decoded.top_most);
    }

    #[test]
    fn corrupt_presets_fall_back_to_defaults() {
        assert_eq!(sanitize_presets([0, 25, 45]), default_presets());
        assert_eq!(sanitize_presets([12, 25, 256]), default_presets());
        assert_eq!(sanitize_presets([10, 20, 40]), [10, 20, 40]);
    }

    #[test]
    fn window_preferences_are_independent_from_policy_and_presets() {
        let preferences = WindowPreferences {
            mode: UiMode::Simple,
            top_most: true,
        };
        let encoded = serde_json::to_string(&PersistedUiState {
            power_policy: None,
            presets: [12, 25, 45],
            mode: preferences.mode,
            top_most: preferences.top_most,
            max_target_watts: None,
        })
        .unwrap();
        let decoded: PersistedUiState = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded.mode, UiMode::Simple);
        assert!(decoded.top_most);
        assert_eq!(decoded.presets, [12, 25, 45]);
        assert_eq!(decoded.power_policy, None);
    }
}
