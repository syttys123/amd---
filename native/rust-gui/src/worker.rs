use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const DEFAULT_PIPE_NAME: &str = r"\\.\pipe\AmdMobilePower.RustGui.Worker.v1";

fn retry_busy_connection<T>(
    timeout: Duration,
    mut connect: impl FnMut() -> std::io::Result<T>,
) -> std::io::Result<T> {
    let deadline = Instant::now() + timeout;
    loop {
        match connect() {
            Ok(stream) => return Ok(stream),
            Err(error) if error.raw_os_error() == Some(231) && Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(20).min(deadline.saturating_duration_since(Instant::now())));
            }
            Err(error) => return Err(error),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PowerLimitTarget {
    pub stapm_watts: i32,
    pub fast_watts: i32,
    pub slow_watts: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PowerLineState {
    Unknown,
    Ac,
    Battery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PowerPolicySettings {
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub battery_enabled: bool,
    #[serde(default = "default_true")]
    pub ac_enabled: bool,
    pub battery_target: PowerLimitTarget,
    pub ac_target: PowerLimitTarget,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PowerPolicyState {
    pub settings: Option<PowerPolicySettings>,
    pub last_observed_power_line: Option<PowerLineState>,
    pub last_applied_target: Option<PowerLimitTarget>,
    pub last_attempt_at: Option<String>,
    pub last_attempt_succeeded: Option<bool>,
    pub last_error: Option<String>,
}

impl PowerLimitTarget {
    pub fn uniform(watts: i32) -> Self {
        Self {
            stapm_watts: watts,
            fast_watts: watts,
            slow_watts: watts,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyTargetResult {
    pub is_successful: bool,
    pub error: Option<String>,
    pub has_firmware_clamp: bool,
    pub has_stapm_warning: bool,
    pub restore_attempted: bool,
    pub restored_previous_limits: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthPayload {
    pub status: String,
    pub worker_version: String,
    pub process_id: u32,
    pub uptime_seconds: f64,
    pub hardware_initialized: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotPayload {
    pub platform: PlatformPayload,
    pub telemetry: TelemetryPayload,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformPayload {
    pub cpu: CpuPayload,
    pub limits: LimitsPayload,
    pub matched_profile: Option<ProfilePayload>,
    pub is_supported: bool,
    pub unsupported_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfilePayload {
    pub id: String,
    pub display_name: String,
    pub minimum_watts: i32,
    pub maximum_watts: i32,
    pub default_watts: i32,
    pub is_verified: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CpuPayload {
    pub processor_name: String,
    pub vendor: String,
    pub ryzen_adj_family: Option<i32>,
    pub ryzen_adj_family_name: Option<String>,
    pub smu_bios_version: Option<String>,
    pub pm_table_version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitsPayload {
    pub supports_stapm: bool,
    pub supports_fast: bool,
    pub supports_slow: bool,
    pub supports_any: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TelemetryPayload {
    pub target_watts: Option<f64>,
    pub stapm_value_watts: Option<f64>,
    pub fast_value_watts: Option<f64>,
    pub slow_value_watts: Option<f64>,
    pub stapm_limit_watts: Option<f64>,
    pub fast_limit_watts: Option<f64>,
    pub slow_limit_watts: Option<f64>,
    pub tctl_value_celsius: Option<f64>,
    pub tctl_limit_celsius: Option<f64>,
    pub power_line: String,
    pub updated_at: Option<String>,
    pub has_firmware_clamp: bool,
}

#[derive(Debug, Deserialize)]
struct WorkerError {
    code: String,
    message: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Response {
    protocol_version: u32,
    request_id: String,
    success: bool,
    payload: Option<Value>,
    error: Option<WorkerError>,
}

#[derive(Debug, Clone)]
pub struct WorkerClient {
    pipe_name: String,
}

impl WorkerClient {
    pub fn new(pipe_name: impl Into<String>) -> Self {
        Self {
            pipe_name: normalize_pipe_name(pipe_name.into()),
        }
    }

    pub fn health(&self) -> Result<HealthPayload, String> {
        let payload = self.request("getHealth", Value::Null)?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn snapshot(&self) -> Result<SnapshotPayload, String> {
        let payload = self.request("getSnapshot", Value::Null)?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn apply_target(&self, target: PowerLimitTarget) -> Result<ApplyTargetResult, String> {
        let payload = serde_json::to_value(serde_json::json!({
            "target": target
        }))
        .map_err(|error| format!("unable to build applyTarget payload: {error}"))?;
        let payload = self.request("applyTarget", payload)?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn get_power_policy(&self) -> Result<PowerPolicyState, String> {
        let payload = self.request("getPowerPolicy", Value::Null)?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn set_power_policy(
        &self,
        settings: PowerPolicySettings,
    ) -> Result<PowerPolicyState, String> {
        let payload = serde_json::to_value(serde_json::json!({
            "settings": settings
        }))
        .map_err(|error| format!("unable to build setPowerPolicy payload: {error}"))?;
        let payload = self.request("setPowerPolicy", payload)?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn shutdown(&self) -> Result<(), String> {
        self.request("shutdown", Value::Null).map(|_| ())
    }

    fn request(&self, command: &str, payload: Value) -> Result<Value, String> {
        let request_id = format!(
            "rust-gui-{}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_millis())
                .unwrap_or(0),
            NEXT_REQUEST_ID.fetch_add(1, Ordering::Relaxed)
        );
        let request = serde_json::json!({
            "protocolVersion": 1,
            "requestId": request_id,
            "command": command,
            "payload": payload
        });

        let stream = retry_busy_connection(Duration::from_secs(2), || {
            OpenOptions::new().read(true).write(true).open(&self.pipe_name)
        }).map_err(|error| format!("unable to open {}: {error}", self.pipe_name))?;
        let mut writer = stream
            .try_clone()
            .map_err(|error| format!("unable to clone worker stream: {error}"))?;
        let mut reader = BufReader::new(stream);
        writer
            .write_all(request.to_string().as_bytes())
            .map_err(|error| format!("unable to write worker request: {error}"))?;
        writer
            .write_all(b"\n")
            .map_err(|error| format!("unable to terminate worker request: {error}"))?;
        writer
            .flush()
            .map_err(|error| format!("unable to flush worker request: {error}"))?;

        let mut response_line = String::new();
        let bytes_read = reader
            .read_line(&mut response_line)
            .map_err(|error| format!("unable to read worker response: {error}"))?;
        if bytes_read == 0 {
            return Err("worker closed the pipe without a response".to_owned());
        }

        let response: Response = serde_json::from_str(&response_line)
            .map_err(|error| format!("unable to parse worker response: {error}"))?;
        if response.protocol_version != 1 {
            return Err(format!(
                "unexpected worker protocol version: {}",
                response.protocol_version
            ));
        }
        if response.request_id != request_id {
            return Err("worker response requestId did not match".to_owned());
        }
        if !response.success {
            return Err(match response.error {
                Some(error) => format!("{}: {}", error.code, error.message),
                None => "worker returned failure without an error".to_owned(),
            });
        }
        response
            .payload
            .ok_or_else(|| "worker returned success without a payload".to_owned())
    }
}

static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

fn normalize_pipe_name(value: String) -> String {
    const PREFIX: &str = r"\\.\pipe\";
    if value.starts_with(PREFIX) {
        value
    } else {
        format!("{PREFIX}{value}")
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn real_busy_pipe_connects_after_owner_disconnects() {
        use std::os::windows::io::FromRawHandle;
        use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
        use windows_sys::Win32::Storage::FileSystem::PIPE_ACCESS_DUPLEX;
        use windows_sys::Win32::System::Pipes::{ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe};
        let name = format!(r"\\.\pipe\AmdMobilePower.RetryTest.{}", std::process::id());
        let wide: Vec<u16> = name.encode_utf16().chain(Some(0)).collect();
        let handle = unsafe {
            CreateNamedPipeW(wide.as_ptr(), PIPE_ACCESS_DUPLEX, 1, 1, 1024, 1024, 0, std::ptr::null())
        };
        assert_ne!(handle, INVALID_HANDLE_VALUE);
        let server = unsafe { std::fs::File::from_raw_handle(handle) };
        let occupied = std::fs::OpenOptions::new().read(true).write(true).open(&name).unwrap();
        assert_eq!(std::fs::OpenOptions::new().read(true).write(true).open(&name).unwrap_err().raw_os_error(), Some(231));
        let (started, ready) = std::sync::mpsc::channel();
        let retry = std::thread::spawn(move || {
            let mut attempts = 0;
            let result = super::retry_busy_connection(std::time::Duration::from_secs(2), || {
                attempts += 1;
                let result = std::fs::OpenOptions::new().read(true).write(true).open(&name);
                if attempts == 1 { started.send(()).unwrap(); }
                result
            });
            (result, attempts)
        });
        ready.recv_timeout(std::time::Duration::from_secs(1)).unwrap();
        unsafe { assert_ne!(DisconnectNamedPipe(handle), 0); }
        unsafe { ConnectNamedPipe(handle, std::ptr::null_mut()); }
        let (connected, attempts) = retry.join().unwrap();
        assert!(connected.is_ok());
        assert!(attempts >= 2);
        drop(connected);
        drop(occupied);
        drop(server);
    }

    #[test]
    fn busy_connection_retries_until_available() {
        let mut attempts = 0;
        let result = super::retry_busy_connection(std::time::Duration::from_secs(1), || {
            attempts += 1;
            if attempts < 3 { Err(std::io::Error::from_raw_os_error(231)) } else { Ok(42) }
        });
        assert_eq!(result.unwrap(), 42);
        assert_eq!(attempts, 3);
    }

    #[test]
    fn connection_errors_other_than_busy_are_not_retried() {
        for code in [2, 5, 109] {
            let mut attempts = 0;
            let result: std::io::Result<()> = super::retry_busy_connection(std::time::Duration::from_secs(1), || {
                attempts += 1;
                Err(std::io::Error::from_raw_os_error(code))
            });
            assert_eq!(result.unwrap_err().raw_os_error(), Some(code));
            assert_eq!(attempts, 1);
        }
    }

    #[test]
    fn persistent_busy_connection_has_a_deadline() {
        let start = std::time::Instant::now();
        let mut attempts = 0;
        let result: std::io::Result<()> = super::retry_busy_connection(std::time::Duration::from_millis(40), || {
            attempts += 1;
            Err(std::io::Error::from_raw_os_error(231))
        });
        assert_eq!(result.unwrap_err().raw_os_error(), Some(231));
        assert!(attempts >= 2);
        assert!(start.elapsed() >= std::time::Duration::from_millis(40));
        assert!(start.elapsed() < std::time::Duration::from_secs(2));
    }

    use super::{normalize_pipe_name, PowerLimitTarget, PowerPolicySettings, WorkerClient};

    #[test]
    fn pipe_name_is_normalized_for_the_windows_namespace() {
        assert_eq!(
            WorkerClient::new("AmdMobilePower.Test").pipe_name,
            r"\\.\pipe\AmdMobilePower.Test"
        );
        assert_eq!(
            WorkerClient::new(r"\\.\pipe\AmdMobilePower.Test").pipe_name,
            r"\\.\pipe\AmdMobilePower.Test"
        );
        assert_eq!(
            normalize_pipe_name("AmdMobilePower.Test".to_owned()),
            r"\\.\pipe\AmdMobilePower.Test"
        );
    }

    #[test]
    fn target_payload_uses_the_v1_camel_case_contract() {
        let value = serde_json::to_value(super::PowerLimitTarget::uniform(12)).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "stapmWatts": 12,
                "fastWatts": 12,
                "slowWatts": 12
            })
        );
    }

    #[test]
    fn power_policy_payload_uses_the_v1_camel_case_contract() {
        let value = serde_json::to_value(PowerPolicySettings {
            enabled: true,
            battery_enabled: true,
            ac_enabled: false,
            battery_target: PowerLimitTarget::uniform(12),
            ac_target: PowerLimitTarget::uniform(45),
        })
        .unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "enabled": true,
                "batteryEnabled": true,
                "acEnabled": false,
                "batteryTarget": {
                    "stapmWatts": 12,
                    "fastWatts": 12,
                    "slowWatts": 12
                },
                "acTarget": {
                    "stapmWatts": 45,
                    "fastWatts": 45,
                    "slowWatts": 45
                }
            })
        );
    }

    #[test]
    fn legacy_power_policy_defaults_both_power_lines_to_enabled() {
        let settings: PowerPolicySettings = serde_json::from_value(serde_json::json!({
            "enabled": true,
            "batteryTarget": {
                "stapmWatts": 10,
                "fastWatts": 10,
                "slowWatts": 10
            },
            "acTarget": {
                "stapmWatts": 45,
                "fastWatts": 45,
                "slowWatts": 45
            }
        }))
        .unwrap();

        assert!(settings.battery_enabled);
        assert!(settings.ac_enabled);
    }
}
