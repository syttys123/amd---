use serde::Deserialize;
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Write};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HealthResponse {
    protocol_version: u32,
    request_id: String,
    success: bool,
    payload: Option<serde_json::Value>,
    error: Option<WorkerError>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HealthPayload {
    status: String,
    worker_version: String,
    process_id: u32,
    uptime_seconds: f64,
    hardware_initialized: bool,
}

#[derive(Debug, Deserialize)]
struct WorkerError {
    code: String,
    message: String,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut arguments = std::env::args().skip(1);
    let mut pipe_name = r"\\.\pipe\AmdMobilePower.Worker.v1".to_owned();
    let mut command = "getHealth".to_owned();
    let mut payload = serde_json::Value::Null;
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--pipe-name" => {
                pipe_name = arguments.next().ok_or("--pipe-name requires a value")?;
            }
            "--command" => {
                command = arguments.next().ok_or("--command requires a value")?;
            }
            "--payload-json" => {
                let value = arguments.next().ok_or("--payload-json requires a value")?;
                payload = serde_json::from_str(&value)
                    .map_err(|error| format!("invalid --payload-json: {error}"))?;
            }
            "--help" | "-h" => {
                println!(
                    "usage: amd-mobile-power-probe [--pipe-name NAME] [--command COMMAND] \
                     [--payload-json JSON]"
                );
                return Ok(());
            }
            value => return Err(format!("unknown argument: {value}").into()),
        }
    }

    let request_id = format!(
        "rust-probe-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_millis())
            .unwrap_or(0)
    );
    let request = serde_json::json!({
        "protocolVersion": 1,
        "requestId": request_id,
        "command": command,
        "payload": payload
    });

    let stream = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pipe_name)
        .map_err(|error| format!("unable to open {pipe_name}: {error}"))?;
    let mut writer = stream.try_clone()?;
    let mut reader = BufReader::new(stream);
    writer.write_all(request.to_string().as_bytes())?;
    writer.write_all(b"\n")?;
    writer.flush()?;

    let mut response_line = String::new();
    let bytes_read = reader.read_line(&mut response_line)?;
    if bytes_read == 0 {
        return Err("worker closed the pipe without a response".into());
    }

    let response: HealthResponse = serde_json::from_str(&response_line)?;
    if response.protocol_version != 1 {
        return Err(format!("unexpected protocol version: {}", response.protocol_version).into());
    }
    if response.request_id != request_id {
        return Err("worker response requestId did not match".into());
    }
    if !response.success {
        let error = response
            .error
            .ok_or("worker returned failure without error")?;
        return Err(format!("{}: {}", error.code, error.message).into());
    }

    if let Some(payload_value) = response.payload {
        if command != "getHealth" {
            println!("{}", serde_json::to_string(&payload_value)?);
            return Ok(());
        }
        let payload: HealthPayload = serde_json::from_value(payload_value)?;
        println!(
            "status={} worker={} pid={} uptime={:.1}s hardware={}",
            payload.status,
            payload.worker_version,
            payload.process_id,
            payload.uptime_seconds,
            payload.hardware_initialized
        );
    } else {
        println!("success");
    }
    Ok(())
}
