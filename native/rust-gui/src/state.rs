use crate::worker::PowerPolicySettings;
use serde::{Deserialize, Serialize};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};

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
    #[serde(default)]
    write_unlocked: bool,
}

impl Default for PersistedUiState {
    fn default() -> Self {
        Self {
            power_policy: None,
            presets: default_presets(),
            mode: UiMode::default(),
            top_most: false,
            max_target_watts: None,
            write_unlocked: false,
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

fn decode_state(contents: &str) -> Result<PersistedUiState, serde_json::Error> {
    // Notepad and PowerShell 5.1 write UTF-8 with a BOM; serde_json rejects it.
    serde_json::from_str::<PersistedUiState>(contents.trim_start_matches('\u{feff}'))
}

fn load_state() -> Option<PersistedUiState> {
    let path = state_path()?;
    load_state_from(&path)
}

fn load_state_from(path: &Path) -> Option<PersistedUiState> {
    let contents = std::fs::read_to_string(path).ok()?;
    match decode_state(&contents) {
        Ok(state) => Some(state),
        Err(_) => {
            // Keep the bad file for support and diagnostics. The next save
            // replaces it with a valid atomic snapshot.
            backup_corrupt_state(path);
            None
        }
    }
}

fn backup_corrupt_state(path: &Path) {
    let backup = path.with_file_name(format!(
        "{}.corrupt.bak",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("rust-ui-state.json")
    ));
    let _ = std::fs::copy(path, backup);
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

/// Whether the owner previously accepted the unlock notice. Write access is
/// still granted explicitly per session *and* stored here so a restart keeps
/// the chosen state instead of silently reverting to read-only.
pub fn load_write_unlocked() -> bool {
    load_state()
        .map(|state| state.write_unlocked)
        .unwrap_or(false)
}

pub fn save_write_unlocked(unlocked: bool) -> Result<(), String> {
    update_state(|state| state.write_unlocked = unlocked)
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
    write_state_atomic(&path, contents.as_bytes())
}

fn write_state_atomic(path: &Path, contents: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("state path has no parent: {}", path.display()))?;
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("rust-ui-state.json");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let temp_path = parent.join(format!(".{file_name}.tmp-{}-{stamp}", std::process::id()));

    let write_result = (|| -> Result<(), String> {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp_path)
            .map_err(|error| format!("unable to create {}: {error}", temp_path.display()))?;
        file.write_all(contents)
            .map_err(|error| format!("unable to write {}: {error}", temp_path.display()))?;
        file.sync_all()
            .map_err(|error| format!("unable to flush {}: {error}", temp_path.display()))?;
        Ok(())
    })();
    if let Err(error) = write_result {
        let _ = std::fs::remove_file(&temp_path);
        return Err(error);
    }

    if let Err(error) = replace_file(&temp_path, path) {
        let _ = std::fs::remove_file(&temp_path);
        return Err(format!("unable to replace {}: {error}", path.display()));
    }
    Ok(())
}

#[cfg(windows)]
fn replace_file(source: &Path, destination: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
    };

    let source_wide: Vec<u16> = source
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let destination_wide: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let result = unsafe {
        MoveFileExW(
            source_wide.as_ptr(),
            destination_wide.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if result == 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace_file(source: &Path, destination: &Path) -> std::io::Result<()> {
    std::fs::rename(source, destination)
}

#[cfg(test)]
mod tests {
    use super::{
        default_presets, load_state_from, sanitize_presets, write_state_atomic, PersistedUiState,
        UiMode, WindowPreferences,
    };
    use crate::worker::{PowerLimitTarget, PowerPolicySettings};
    use std::path::PathBuf;

    #[test]
    fn state_with_utf8_bom_is_accepted() {
        let decoded = super::decode_state("\u{feff}{\"presets\":[10,25,45]}")
            .expect("BOM-prefixed state must parse");

        assert_eq!(decoded.presets, [10, 25, 45]);
    }

    #[test]
    fn malformed_state_is_rejected() {
        assert!(super::decode_state("{\"presets\":[10,25").is_err());
    }

    #[test]
    fn atomic_state_write_replaces_an_existing_file() {
        let directory = test_directory("atomic-state");
        let path = directory.join("rust-ui-state.json");
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::write(&path, b"old").unwrap();

        write_state_atomic(&path, br#"{"presets":[10,25,45]}"#).unwrap();

        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            r#"{"presets":[10,25,45]}"#
        );
        let _ = std::fs::remove_dir_all(&directory);
    }

    #[test]
    fn corrupt_state_is_preserved_for_recovery() {
        let directory = test_directory("corrupt-state");
        let path = directory.join("rust-ui-state.json");
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::write(&path, b"{not-json").unwrap();

        assert!(load_state_from(&path).is_none());
        let backup = directory.join("rust-ui-state.json.corrupt.bak");
        assert_eq!(std::fs::read(&backup).unwrap(), b"{not-json");
        let _ = std::fs::remove_dir_all(&directory);
    }

    fn test_directory(label: &str) -> PathBuf {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!(
            "amd-mobile-power-{label}-{}-{stamp}",
            std::process::id()
        ))
    }

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
            write_unlocked: false,
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
            write_unlocked: false,
        })
        .unwrap();
        let decoded: PersistedUiState = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded.mode, UiMode::Simple);
        assert!(decoded.top_most);
        assert_eq!(decoded.presets, [12, 25, 45]);
        assert_eq!(decoded.power_policy, None);
    }
}
