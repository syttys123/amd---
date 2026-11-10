use serde::Deserialize;
use serde_json::Value;
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const DEFAULT_PIPE_NAME: &str = r"\\.\pipe\AmdMobilePower.RustGui.Worker.v1";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthPayload {
    pub status: String,
    pub worker_version: String,
    pub process_id: u32,
    pub uptime_seconds: f64,
    pub hardware_initialized: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotPayload {
    pub platform: PlatformPayload,
    pub telemetry: TelemetryPayload,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformPayload {
    pub cpu: CpuPayload,
    pub limits: LimitsPayload,
    pub is_supported: bool,
    pub unsupported_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CpuPayload {
    pub processor_name: String,
    pub vendor: String,
    pub ryzen_adj_family: Option<i32>,
    pub ryzen_adj_family_name: Option<String>,
    pub smu_bios_version: Option<String>,
    pub pm_table_version: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitsPayload {
    pub supports_stapm: bool,
    pub supports_fast: bool,
    pub supports_slow: bool,
    pub supports_any: bool,
}

#[derive(Debug, Deserialize)]
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
        let payload = self.request("getHealth")?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn snapshot(&self) -> Result<SnapshotPayload, String> {
        let payload = self.request("getSnapshot")?;
        serde_json::from_value(payload).map_err(|error| error.to_string())
    }

    pub fn shutdown(&self) -> Result<(), String> {
        self.request("shutdown").map(|_| ())
    }

    fn request(&self, command: &str) -> Result<Value, String> {
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
            "payload": null
        });

        let stream = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&self.pipe_name)
            .map_err(|error| format!("unable to open {}: {error}", self.pipe_name))?;
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
    use super::{normalize_pipe_name, WorkerClient};

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
}
