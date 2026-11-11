//! AMD Mobile Power command-line probe.
//!
//! Two modes are supported:
//!
//! * a raw single-request client (`--pipe-name` / `--command`) used by the
//!   existing verifier scripts against an already running worker;
//! * a headless compatibility diagnosis (`--diagnose`) that starts a private,
//!   read-only worker, collects health/capabilities/telemetry/profiles, and
//!   prints one redacted JSON document. The diagnosis mode needs neither
//!   PowerShell nor the GUI, which is what lets a user on an unknown AMD laptop
//!   produce a report that can be imported back into the repository.

use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Write};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStderr, Command, ExitCode, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const PROTOCOL_VERSION: u32 = 1;
const PROBE_VERSION: &str = env!("CARGO_PKG_VERSION");
const DEFAULT_WORKER_EXE: &str = "amdmobilepower_native_worker.exe";
const BUILD_INFO_FILE: &str = "BUILD-INFO.txt";
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const REPORT_TYPE: &str = "amd-mobile-power-native-compatibility";
const HARDWARE_OWNER_MUTEX: &str = r"Local\AmdMobilePower.HardwareOwner.v1";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkerResponse {
    protocol_version: u32,
    request_id: String,
    success: bool,
    payload: Option<Value>,
    error: Option<WorkerError>,
}

#[derive(Debug, Deserialize)]
struct WorkerError {
    code: String,
    message: String,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(message) => {
            eprintln!("error: {message}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<u8, String> {
    let mut options = Options::default();
    let mut arguments = std::env::args().skip(1).peekable();
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--pipe-name" => options.pipe_name = take_value(&mut arguments, "--pipe-name")?,
            "--command" => options.command = take_value(&mut arguments, "--command")?,
            "--payload-json" => {
                let value = take_value(&mut arguments, "--payload-json")?;
                options.payload = serde_json::from_str(&value)
                    .map_err(|error| format!("invalid --payload-json: {error}"))?;
            }
            "--diagnose" => options.diagnose = true,
            "--worker" => {
                options.worker = Some(PathBuf::from(take_value(&mut arguments, "--worker")?))
            }
            "--out" => options.out = Some(PathBuf::from(take_value(&mut arguments, "--out")?)),
            "--markdown" => {
                options.markdown = Some(PathBuf::from(take_value(&mut arguments, "--markdown")?));
            }
            "--timeout-ms" => {
                let raw = take_value(&mut arguments, "--timeout-ms")?;
                let parsed: u64 = raw
                    .parse()
                    .map_err(|error| format!("invalid --timeout-ms: {error}"))?;
                options.timeout = Duration::from_millis(parsed.clamp(500, 60_000));
            }
            "--self-test" => options.self_test = true,
            "--version" => {
                println!("amd-mobile-power-probe {PROBE_VERSION}");
                return Ok(0);
            }
            "--help" | "-h" => {
                print_usage();
                return Ok(0);
            }
            value => return Err(format!("unknown argument: {value}")),
        }
    }

    if options.self_test {
        return run_self_test();
    }
    if options.diagnose {
        return run_diagnose(options);
    }
    run_single_request(&options)
}

fn print_usage() {
    println!(
        "usage: amd-mobile-power-probe [MODE]\n\n\
         Modes:\n  \
         --diagnose                 start a private read-only worker and emit a\n\
         \x20                          compatibility report (no GUI, no PowerShell)\n  \
         --self-test                validate the probe build without hardware access\n  \
         --command COMMAND          send one request to an already running worker\n\n\
         Options:\n  \
         --pipe-name NAME           worker pipe for --command (defaults to the\n\
         \x20                          development pipe name)\n  \
         --payload-json JSON        request payload for --command\n  \
         --worker PATH              worker executable used by --diagnose\n  \
         --out FILE                 write the diagnosis JSON report to FILE\n  \
         --markdown FILE            also write a Markdown summary to FILE\n  \
         --timeout-ms N             worker start timeout for --diagnose (default 8000)\n  \
         --version, --help\n\n\
         The diagnosis mode never enables hardware write controls."
    );
}

fn take_value<I>(arguments: &mut std::iter::Peekable<I>, flag: &str) -> Result<String, String>
where
    I: Iterator<Item = String>,
{
    arguments
        .next()
        .ok_or_else(|| format!("{flag} requires a value"))
}

#[derive(Debug)]
struct Options {
    pipe_name: String,
    command: String,
    payload: Value,
    diagnose: bool,
    self_test: bool,
    worker: Option<PathBuf>,
    out: Option<PathBuf>,
    markdown: Option<PathBuf>,
    timeout: Duration,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            // Historical default pipe: verifier scripts drive a worker that was
            // started by hand with this name.
            pipe_name: r"\\.\pipe\AmdMobilePower.Worker.v1".to_owned(),
            command: "getHealth".to_owned(),
            payload: Value::Null,
            diagnose: false,
            self_test: false,
            worker: None,
            out: None,
            markdown: None,
            timeout: Duration::from_millis(8000),
        }
    }
}

fn request_id() -> String {
    format!("probe-{}-{}", std::process::id(), unix_millis())
}

fn unix_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

/// Send one request over a named pipe and return the response payload.
fn request(pipe_name: &str, command: &str, payload: &Value) -> Result<Value, String> {
    let id = request_id();
    let request = json!({
        "protocolVersion": PROTOCOL_VERSION,
        "requestId": id,
        "command": command,
        "payload": payload,
    });

    let stream = open_pipe(pipe_name)?;
    let mut writer = stream
        .try_clone()
        .map_err(|error| format!("unable to clone the worker pipe: {error}"))?;
    let mut reader = BufReader::new(stream);
    writer
        .write_all(request.to_string().as_bytes())
        .and_then(|_| writer.write_all(b"\n"))
        .and_then(|_| writer.flush())
        .map_err(|error| format!("unable to send {command}: {error}"))?;

    let mut line = String::new();
    let read = reader
        .read_line(&mut line)
        .map_err(|error| format!("unable to read the {command} response: {error}"))?;
    if read == 0 {
        return Err(format!("worker closed the pipe before answering {command}"));
    }

    let response: WorkerResponse = serde_json::from_str(&line)
        .map_err(|error| format!("invalid {command} response: {error}"))?;
    if response.protocol_version != PROTOCOL_VERSION {
        return Err(format!(
            "unexpected protocol version {} for {command}",
            response.protocol_version
        ));
    }
    if response.request_id != id {
        return Err(format!("requestId mismatch for {command}"));
    }
    if !response.success {
        let error = response
            .error
            .ok_or_else(|| format!("worker failed {command} without an error object"))?;
        return Err(format!("{}: {}", error.code, error.message));
    }
    Ok(response.payload.unwrap_or(Value::Null))
}

/// The worker exposes a single pipe instance, so a client can legitimately see
/// ERROR_PIPE_BUSY while the GUI is polling. Retry that case briefly; every
/// other error (for example ERROR_FILE_NOT_FOUND) is returned immediately.
fn open_pipe(pipe_name: &str) -> Result<std::fs::File, String> {
    const ERROR_PIPE_BUSY: i32 = 231;
    let mut last_error = String::new();
    for _ in 0..40 {
        match OpenOptions::new().read(true).write(true).open(pipe_name) {
            Ok(stream) => return Ok(stream),
            Err(error) => {
                last_error = error.to_string();
                if error.raw_os_error() != Some(ERROR_PIPE_BUSY) {
                    break;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
        }
    }
    Err(format!("unable to open the worker pipe: {last_error}"))
}

fn run_single_request(options: &Options) -> Result<u8, String> {
    let payload = request(&options.pipe_name, &options.command, &options.payload)?;
    if options.command == "getHealth" {
        if let Some(health) = payload.as_object() {
            println!(
                "status={} worker={} pid={} uptime={:.1}s hardware={}",
                health
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown"),
                health
                    .get("workerVersion")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown"),
                health.get("processId").and_then(Value::as_u64).unwrap_or(0),
                health
                    .get("uptimeSeconds")
                    .and_then(Value::as_f64)
                    .unwrap_or(0.0),
                health
                    .get("hardwareInitialized")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
            );
        } else {
            println!(
                "{}",
                serde_json::to_string(&payload).map_err(|error| error.to_string())?
            );
        }
    } else {
        println!(
            "{}",
            serde_json::to_string(&payload).map_err(|error| error.to_string())?
        );
    }
    Ok(0)
}

fn run_self_test() -> Result<u8, String> {
    // Keep the self test hardware-free so it can run in CI and inside a freshly
    // expanded package before any driver is installed.
    let timestamp = iso8601_now();
    if timestamp.len() != 20 || !timestamp.ends_with('Z') {
        return Err("ISO-8601 clock formatting failed".to_owned());
    }
    let sample = json!({
        "schemaVersion": 1,
        "reportType": REPORT_TYPE,
        "selfTest": "PASS",
        "probeVersion": PROBE_VERSION,
        "readOnlyByDefault": true,
        "generatedAt": timestamp,
    });
    println!(
        "{}",
        serde_json::to_string(&sample).map_err(|error| error.to_string())?
    );
    Ok(0)
}

fn run_diagnose(options: Options) -> Result<u8, String> {
    let probe_dir = std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."));
    let worker_path = options
        .worker
        .clone()
        .unwrap_or_else(|| probe_dir.join(DEFAULT_WORKER_EXE));
    // The worker resolves RyzenAdj DLLs relative to its own executable, so the
    // package directory (not the probe directory) is the working directory.
    let package_dir = worker_path
        .parent()
        .filter(|parent| parent.is_dir())
        .map(Path::to_path_buf)
        .unwrap_or_else(|| probe_dir.clone());
    let build_info = if package_dir.join(BUILD_INFO_FILE).is_file() {
        read_build_info(&package_dir)
    } else {
        read_build_info(&probe_dir)
    };

    let mut collection = Collection::default();
    let pipe_name = format!(
        r"\\.\pipe\AmdMobilePower.Diagnose.{}.{}",
        std::process::id(),
        unix_millis()
    );

    if !worker_path.is_file() {
        collection.error = Some(format!(
            "worker executable {} was not found next to the probe",
            DEFAULT_WORKER_EXE
        ));
    } else {
        let attempt = collect_with_worker(&worker_path, &package_dir, &pipe_name, options.timeout);
        match attempt {
            Ok(collected) => collection = collected,
            Err(error) => collection.error = Some(error),
        }
    }

    let report = build_report(&build_info, &collection);
    let status = report
        .get("collectionStatus")
        .and_then(Value::as_str)
        .unwrap_or("FAILED")
        .to_owned();

    let json_text = serde_json::to_string_pretty(&report)
        .map_err(|error| format!("unable to serialize the report: {error}"))?;
    match &options.out {
        Some(path) => {
            if let Some(parent) = path.parent() {
                if !parent.as_os_str().is_empty() {
                    std::fs::create_dir_all(parent).map_err(|error| {
                        format!("unable to create {}: {error}", parent.display())
                    })?;
                }
            }
            std::fs::write(path, format!("{json_text}\n"))
                .map_err(|error| format!("unable to write {}: {error}", path.display()))?;
            println!("{}", path.display());
        }
        None => println!("{json_text}"),
    }

    if let Some(path) = &options.markdown {
        let markdown = render_markdown(&report);
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)
                    .map_err(|error| format!("unable to create {}: {error}", parent.display()))?;
            }
        }
        std::fs::write(path, markdown)
            .map_err(|error| format!("unable to write {}: {error}", path.display()))?;
    }

    if let Some(error) = report.get("error").and_then(Value::as_str) {
        if !error.is_empty() {
            eprintln!("collection error: {error}");
        }
    }
    Ok(if status == "PASS" { 0 } else { 2 })
}

#[derive(Default)]
struct Collection {
    health: Option<Value>,
    capabilities: Option<Value>,
    snapshot: Option<Value>,
    profiles: Option<Value>,
    policy: Option<Value>,
    error: Option<String>,
    owner_conflict: bool,
}

fn collect_with_worker(
    worker_path: &Path,
    working_directory: &Path,
    pipe_name: &str,
    timeout: Duration,
) -> Result<Collection, String> {
    let mut collection = Collection::default();

    // First attempt: full read-only hardware access. If the process cannot load
    // the driver (typically because the shell is not elevated) fall back to a
    // worker without hardware so the report still carries host and version data.
    let mut session = None;
    if hardware_owner_is_active() {
        // The worker holds an exclusive hardware-owner mutex. Starting a second
        // owner would only surface a confusing driver error, so name the real
        // cause and continue with the read-only fallback worker.
        collection.owner_conflict = true;
        collection.error = Some(
            "another AMD Mobile Power instance currently owns hardware access; exit it from the tray and run the probe again for live limits"
                .to_owned(),
        );
    } else {
        match WorkerSession::start(worker_path, working_directory, pipe_name, true, timeout) {
            Ok(started) => session = Some(started),
            Err(error) => collection.error = Some(error),
        }
    }

    if session.is_none() {
        if let Ok(fallback) =
            WorkerSession::start(worker_path, working_directory, pipe_name, false, timeout)
        {
            session = Some(fallback);
        }
    }

    let mut session = match session {
        Some(session) => session,
        None => return Ok(collection),
    };

    collection.health = session.request("getHealth").ok();
    collection.capabilities = session.request("getCapabilities").ok();
    collection.snapshot = session.request("getSnapshot").ok();
    collection.profiles = session.request("getProfiles").ok();
    collection.policy = session.request("getPowerPolicy").ok();

    let hardware_initialized = collection
        .health
        .as_ref()
        .and_then(|health| health.get("hardwareInitialized"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if !hardware_initialized && collection.error.is_none() {
        collection.error = Some(
            "the worker started without hardware access; exit any running AMD Mobile Power instance and run the probe again"
                .to_owned(),
        );
    }

    session.shutdown();
    Ok(collection)
}

struct WorkerSession {
    child: Child,
    pipe_name: String,
    // Kept alive so the worker's stderr pipe stays open; the handle is only
    // consumed on the startup-failure path.
    _stderr: Option<ChildStderr>,
}

impl WorkerSession {
    fn start(
        worker_path: &Path,
        working_directory: &Path,
        pipe_name: &str,
        enable_hardware: bool,
        timeout: Duration,
    ) -> Result<Self, String> {
        let mut command = Command::new(worker_path);
        command
            .arg("--pipe-name")
            .arg(pipe_name)
            .current_dir(working_directory)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .creation_flags(CREATE_NO_WINDOW);
        if enable_hardware {
            command.arg("--enable-hardware");
        }
        let mut child = command
            .spawn()
            .map_err(|error| format!("unable to start {DEFAULT_WORKER_EXE}: {error}"))?;
        let mut child_stderr = child.stderr.take();

        let deadline = Instant::now() + timeout;
        loop {
            match request(pipe_name, "getHealth", &Value::Null) {
                Ok(_) => {
                    return Ok(Self {
                        child,
                        pipe_name: pipe_name.to_owned(),
                        _stderr: child_stderr,
                    })
                }
                Err(error) => {
                    if let Ok(Some(status)) = child.try_wait() {
                        let detail = take_child_stderr(&mut child_stderr);
                        let reason = if detail.is_empty() { error } else { detail };
                        return Err(format!(
                            "{DEFAULT_WORKER_EXE} exited early ({status}): {reason}"
                        ));
                    }
                    if Instant::now() >= deadline {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(format!(
                            "timed out waiting for the worker pipe after {} ms",
                            timeout.as_millis()
                        ));
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
            }
        }
    }

    fn request(&mut self, command: &str) -> Result<Value, String> {
        request(&self.pipe_name, command, &Value::Null)
    }

    fn shutdown(&mut self) {
        let _ = request(&self.pipe_name, "shutdown", &Value::Null);
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            match self.child.try_wait() {
                Ok(Some(_)) => return,
                Ok(None) => {}
                Err(_) => break,
            }
            if Instant::now() >= deadline {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

impl Drop for WorkerSession {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn build_report(build: &BTreeMap<String, String>, collection: &Collection) -> Value {
    let health = collection.health.as_ref();
    let platform = collection
        .capabilities
        .as_ref()
        .and_then(|value| value.get("platform"));
    let telemetry = collection
        .snapshot
        .as_ref()
        .and_then(|value| value.get("telemetry"));

    let hardware_initialized = health
        .and_then(|health| health.get("hardwareInitialized"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let platform_supported = platform
        .and_then(|platform| platform.get("isSupported"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let collection_status = if health.is_some() && hardware_initialized && platform_supported {
        "PASS"
    } else {
        "FAILED"
    };

    let mut checks = Vec::new();
    checks.push(check(
        "worker.health",
        if health.is_some() { "PASS" } else { "FAIL" },
        if health.is_some() {
            "worker answered getHealth".to_owned()
        } else {
            "worker did not answer getHealth".to_owned()
        },
    ));
    checks.push(check(
        "worker.hardware",
        if hardware_initialized { "PASS" } else { "WARN" },
        if hardware_initialized {
            "RyzenAdj hardware context initialized".to_owned()
        } else if collection.owner_conflict {
            "another AMD Mobile Power instance owns the hardware mutex".to_owned()
        } else {
            "hardware context unavailable; close other power tools and retry".to_owned()
        },
    ));
    checks.push(check(
        "worker.readOnly",
        "PASS",
        "worker started without --enable-write-controls".to_owned(),
    ));
    checks.push(check(
        "worker.exclusive",
        if collection.owner_conflict {
            "WARN"
        } else if hardware_initialized {
            "PASS"
        } else {
            "WARN"
        },
        if collection.owner_conflict {
            "another AMD Mobile Power instance owns hardware access; exit it from the tray and rerun"
                .to_owned()
        } else if hardware_initialized {
            "exclusive hardware access acquired".to_owned()
        } else {
            "hardware access not acquired".to_owned()
        },
    ));
    checks.push(check(
        "platform.supported",
        if platform_supported { "PASS" } else { "WARN" },
        platform
            .and_then(|platform| platform.get("unsupportedReason"))
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| {
                if platform_supported {
                    "platform reports power-limit support".to_owned()
                } else {
                    "platform capabilities were not collected".to_owned()
                }
            }),
    ));

    let limits = platform.and_then(|platform| platform.get("limits"));
    let supports = |name: &str| {
        limits
            .and_then(|limits| limits.get(name))
            .and_then(Value::as_bool)
            .unwrap_or(false)
    };
    checks.push(check(
        "limits.available",
        if supports("supportsStapm") || supports("supportsFast") || supports("supportsSlow") {
            "PASS"
        } else {
            "WARN"
        },
        format!(
            "stapm={} fast={} slow={}",
            supports("supportsStapm"),
            supports("supportsFast"),
            supports("supportsSlow")
        ),
    ));

    if let Some(telemetry) = telemetry {
        let readable = ["stapmLimitWatts", "fastLimitWatts", "slowLimitWatts"]
            .iter()
            .any(|name| telemetry.get(name).map(Value::is_number).unwrap_or(false));
        checks.push(check(
            "telemetry.readable",
            if readable { "PASS" } else { "WARN" },
            format!(
                "powerLine={} stapm={} fast={} slow={}",
                telemetry
                    .get("powerLine")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown"),
                number_text(telemetry.get("stapmLimitWatts")),
                number_text(telemetry.get("fastLimitWatts")),
                number_text(telemetry.get("slowLimitWatts")),
            ),
        ));
    } else {
        checks.push(check(
            "telemetry.readable",
            "WARN",
            "telemetry snapshot unavailable".to_owned(),
        ));
    }

    json!({
        "schemaVersion": 1,
        "reportType": REPORT_TYPE,
        "collectionStatus": collection_status,
        "collectedAt": iso8601_now(),
        "collector": {
            "name": "amd-mobile-power-probe",
            "version": PROBE_VERSION,
            "mode": "headless-diagnose",
            "requiresPowerShell": false,
            "requiresGui": false,
        },
        "privacy": {
            "localPathsIncluded": false,
            "pipeNameIncluded": false,
            "processIdIncluded": false,
            "accountNamesIncluded": false,
            "serialNumbersIncluded": false,
            "recentLogsIncluded": false,
            "networkUploadPerformed": false,
        },
        "host": host_information(),
        "package": {
            "name": build.get("Name").cloned().unwrap_or_default(),
            "version": build.get("Version").cloned().unwrap_or_default(),
            "sourceCommit": build.get("Commit").cloned().unwrap_or_default(),
            "workingTree": build.get("WorkingTree").cloned().unwrap_or_default(),
            "buildTimestamp": build.get("BuiltAt").cloned().unwrap_or_default(),
        },
        "environment": {
            "os": "Windows",
            "architecture": std::env::consts::ARCH,
            "probe": format!("amd-mobile-power-probe {PROBE_VERSION}"),
        },
        "worker": {
            "status": health.and_then(|health| health.get("status")).cloned().unwrap_or(Value::Null),
            "version": health.and_then(|health| health.get("workerVersion")).cloned().unwrap_or(Value::Null),
            "hardwareInitialized": hardware_initialized,
            "writeControlsEnabled": false,
        },
        "platform": platform.map(redact_platform).unwrap_or(Value::Null),
        "profileCatalog": collection.profiles.clone().unwrap_or(Value::Null),
        "telemetry": telemetry.map(redact_telemetry).unwrap_or(Value::Null),
        "powerPolicy": collection.policy.clone().unwrap_or(Value::Null),
        "powerPolicyNote": "state of the private diagnostic worker, not the installed app's saved policy",
        "checks": checks,
        "error": collection.error.clone(),
    })
}

fn check(id: &str, status: &str, detail: String) -> Value {
    json!({ "id": id, "status": status, "detail": detail })
}

fn number_text(value: Option<&Value>) -> String {
    match value.and_then(Value::as_f64) {
        Some(number) => format!("{number:.2}W"),
        None => "unavailable".to_owned(),
    }
}

fn redact_platform(platform: &Value) -> Value {
    let cpu = platform.get("cpu");
    json!({
        "processorName": cpu
            .and_then(|cpu| cpu.get("processorName"))
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or(""),
        "vendor": cpu.and_then(|cpu| cpu.get("vendor")).cloned().unwrap_or(Value::Null),
        "ryzenAdjFamily": cpu.and_then(|cpu| cpu.get("ryzenAdjFamily")).cloned().unwrap_or(Value::Null),
        "ryzenAdjFamilyName": cpu.and_then(|cpu| cpu.get("ryzenAdjFamilyName")).cloned().unwrap_or(Value::Null),
        "smuBiosVersion": cpu.and_then(|cpu| cpu.get("smuBiosVersion")).cloned().unwrap_or(Value::Null),
        "pmTableVersion": cpu.and_then(|cpu| cpu.get("pmTableVersion")).cloned().unwrap_or(Value::Null),
        "isSupported": platform.get("isSupported").cloned().unwrap_or(Value::Bool(false)),
        "unsupportedReason": platform.get("unsupportedReason").cloned().unwrap_or(Value::Null),
        "limits": platform.get("limits").cloned().unwrap_or(Value::Null),
        "profile": platform.get("matchedProfile").cloned().unwrap_or(Value::Null),
    })
}

fn redact_telemetry(telemetry: &Value) -> Value {
    json!({
        "powerLine": telemetry.get("powerLine").cloned().unwrap_or(Value::Null),
        "targetWatts": telemetry.get("targetWatts").cloned().unwrap_or(Value::Null),
        "stapmLimitWatts": telemetry.get("stapmLimitWatts").cloned().unwrap_or(Value::Null),
        "fastLimitWatts": telemetry.get("fastLimitWatts").cloned().unwrap_or(Value::Null),
        "slowLimitWatts": telemetry.get("slowLimitWatts").cloned().unwrap_or(Value::Null),
        "stapmValueWatts": telemetry.get("stapmValueWatts").cloned().unwrap_or(Value::Null),
        "fastValueWatts": telemetry.get("fastValueWatts").cloned().unwrap_or(Value::Null),
        "slowValueWatts": telemetry.get("slowValueWatts").cloned().unwrap_or(Value::Null),
        "tctlValueCelsius": telemetry.get("tctlValueCelsius").cloned().unwrap_or(Value::Null),
        "tctlLimitCelsius": telemetry.get("tctlLimitCelsius").cloned().unwrap_or(Value::Null),
        "hasFirmwareClamp": telemetry.get("hasFirmwareClamp").cloned().unwrap_or(Value::Null),
        "updatedAt": telemetry.get("updatedAt").cloned().unwrap_or(Value::Null),
    })
}

fn render_markdown(report: &Value) -> String {
    let host = report.get("host").cloned().unwrap_or(Value::Null);
    let platform = report.get("platform").cloned().unwrap_or(Value::Null);
    let telemetry = report.get("telemetry").cloned().unwrap_or(Value::Null);
    let package = report.get("package").cloned().unwrap_or(Value::Null);
    let mut lines = Vec::new();
    lines.push("# AMD Mobile Power Compatibility Report".to_owned());
    lines.push(String::new());
    lines.push(format!(
        "- Collection status: `{}`",
        text(report, "collectionStatus")
    ));
    lines.push(format!("- Collected at: {}", text(report, "collectedAt")));
    lines.push(format!(
        "- Package version: {} ({})",
        text(&package, "version"),
        text(&package, "name")
    ));
    lines.push(format!(
        "- System: {} {}",
        text(&host, "manufacturer"),
        text(&host, "model")
    ));
    lines.push(format!(
        "- BIOS: {} ({})",
        text(&host, "biosVersion"),
        text(&host, "biosReleaseDate")
    ));
    lines.push(format!("- CPU: {}", text(&platform, "processorName")));
    lines.push(format!(
        "- RyzenAdj family: {} ({})",
        text(&platform, "ryzenAdjFamilyName"),
        text(&platform, "ryzenAdjFamily")
    ));
    lines.push(format!(
        "- Platform supported: {}",
        platform
            .get("isSupported")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    ));
    let profile = platform.get("profile").cloned().unwrap_or(Value::Null);
    lines.push(format!(
        "- Matched profile: {} ({} W - {} W)",
        text(&profile, "displayName"),
        text(&profile, "minimumWatts"),
        text(&profile, "maximumWatts")
    ));
    lines.push(String::new());
    lines.push("## Telemetry".to_owned());
    lines.push(String::new());
    lines.push(format!("- Power line: {}", text(&telemetry, "powerLine")));
    lines.push(format!(
        "- STAPM limit: {} W",
        text(&telemetry, "stapmLimitWatts")
    ));
    lines.push(format!(
        "- Fast limit: {} W",
        text(&telemetry, "fastLimitWatts")
    ));
    lines.push(format!(
        "- Slow limit: {} W",
        text(&telemetry, "slowLimitWatts")
    ));

    let policy = report.get("powerPolicy").cloned().unwrap_or(Value::Null);
    let policy_enabled = policy
        .get("settings")
        .and_then(|settings| settings.get("enabled"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if policy.get("settings").is_some() && policy_enabled {
        let settings = policy.get("settings").cloned().unwrap_or(Value::Null);
        let battery = settings
            .get("batteryTarget")
            .cloned()
            .unwrap_or(Value::Null);
        let ac = settings.get("acTarget").cloned().unwrap_or(Value::Null);
        lines.push(String::new());
        lines.push("## Power Policy".to_owned());
        lines.push(String::new());
        lines.push(format!(
            "- Policy enabled: {}",
            settings
                .get("enabled")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        ));
        lines.push(format!(
            "- Battery target: {}/{}/{} W",
            text(&battery, "stapmWatts"),
            text(&battery, "fastWatts"),
            text(&battery, "slowWatts")
        ));
        lines.push(format!(
            "- AC target: {}/{}/{} W",
            text(&ac, "stapmWatts"),
            text(&ac, "fastWatts"),
            text(&ac, "slowWatts")
        ));
        lines.push(format!(
            "- Last attempt succeeded: {}",
            policy
                .get("lastAttemptSucceeded")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        ));
    }
    lines.push(String::new());
    lines.push("## Checks".to_owned());
    lines.push(String::new());
    if let Some(checks) = report.get("checks").and_then(Value::as_array) {
        for check in checks {
            lines.push(format!(
                "- `{}` {}: {}",
                check.get("id").and_then(Value::as_str).unwrap_or("unknown"),
                check
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("UNKNOWN"),
                check.get("detail").and_then(Value::as_str).unwrap_or("")
            ));
        }
    }
    lines.push(String::new());
    lines.push("## Privacy".to_owned());
    lines.push(String::new());
    lines.push(
        "This report was generated locally. It contains no local paths, pipe names, account names, serial numbers, or recent logs, and nothing was uploaded."
            .to_owned(),
    );
    if let Some(error) = report.get("error").and_then(Value::as_str) {
        if !error.is_empty() {
            lines.push(String::new());
            lines.push("## Error".to_owned());
            lines.push(String::new());
            lines.push(format!("- {error}"));
        }
    }
    lines.push(String::new());
    lines.join("\n")
}

fn text(value: &Value, key: &str) -> String {
    match value.get(key) {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::Bool(flag)) => flag.to_string(),
        Some(Value::Null) | None => "Unavailable".to_owned(),
        Some(other) => other.to_string(),
    }
}

fn read_build_info(directory: &Path) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    let Ok(text) = std::fs::read_to_string(directory.join(BUILD_INFO_FILE)) else {
        return values;
    };
    for line in text.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if key.is_empty() {
            continue;
        }
        values.insert(key.to_owned(), value.trim().to_owned());
    }
    values
}

fn host_information() -> Value {
    json!({
        "manufacturer": read_registry_string(
            r"HARDWARE\DESCRIPTION\System\BIOS",
            "SystemManufacturer",
        ),
        "model": read_registry_string(
            r"HARDWARE\DESCRIPTION\System\BIOS",
            "SystemProductName",
        ),
        "biosVersion": read_registry_string(
            r"HARDWARE\DESCRIPTION\System\BIOS",
            "BIOSVersion",
        ),
        "biosReleaseDate": read_registry_string(
            r"HARDWARE\DESCRIPTION\System\BIOS",
            "BIOSReleaseDate",
        ),
        "windowsEdition": read_registry_string(
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ProductName",
        ),
        "windowsVersion": read_registry_string(
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "CurrentVersion",
        ),
        "windowsBuild": read_registry_string(
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "CurrentBuild",
        ),
        "windowsDisplayVersion": read_registry_string(
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "DisplayVersion",
        ),
    })
}

#[link(name = "advapi32")]
extern "system" {
    fn RegGetValueW(
        hkey: usize,
        sub_key: *const u16,
        value: *const u16,
        flags: u32,
        value_type: *mut u32,
        data: *mut u8,
        data_size: *mut u32,
    ) -> i32;
}

const HKEY_LOCAL_MACHINE: usize = 0x8000_0002;
const RRF_RT_REG_SZ: u32 = 0x0000_0002;

#[link(name = "kernel32")]
extern "system" {
    fn OpenMutexW(desired_access: u32, inherit_handle: i32, name: *const u16) -> isize;
    fn CloseHandle(handle: isize) -> i32;
}

const SYNCHRONIZE: u32 = 0x0010_0000;

fn read_registry_string(sub_key: &str, value_name: &str) -> Option<String> {
    let sub_key: Vec<u16> = sub_key.encode_utf16().chain(std::iter::once(0)).collect();
    let value_name: Vec<u16> = value_name
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();

    let mut size: u32 = 0;
    let status = unsafe {
        RegGetValueW(
            HKEY_LOCAL_MACHINE,
            sub_key.as_ptr(),
            value_name.as_ptr(),
            RRF_RT_REG_SZ,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut size,
        )
    };
    if status != 0 || size == 0 || size > 64 * 1024 {
        return None;
    }

    let mut buffer = vec![0u8; size as usize];
    let status = unsafe {
        RegGetValueW(
            HKEY_LOCAL_MACHINE,
            sub_key.as_ptr(),
            value_name.as_ptr(),
            RRF_RT_REG_SZ,
            std::ptr::null_mut(),
            buffer.as_mut_ptr(),
            &mut size,
        )
    };
    if status != 0 {
        return None;
    }

    let (pairs, _remainder) = buffer.as_chunks::<2>();
    let utf16: Vec<u16> = pairs.iter().map(|pair| u16::from_le_bytes(*pair)).collect();
    let end = utf16
        .iter()
        .position(|&unit| unit == 0)
        .unwrap_or(utf16.len());
    let text = String::from_utf16(&utf16[..end]).ok()?;
    let text = text.trim();
    if text.is_empty() {
        None
    } else {
        Some(text.to_owned())
    }
}

/// True when another AMD Mobile Power process already holds the exclusive
/// `Local\AmdMobilePower.HardwareOwner.v1` mutex.
fn hardware_owner_is_active() -> bool {
    let name: Vec<u16> = HARDWARE_OWNER_MUTEX
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let handle = unsafe { OpenMutexW(SYNCHRONIZE, 0, name.as_ptr()) };
    if handle == 0 {
        return false;
    }
    unsafe {
        CloseHandle(handle);
    }
    true
}

fn take_child_stderr(stderr: &mut Option<ChildStderr>) -> String {
    use std::io::Read;
    let Some(mut pipe) = stderr.take() else {
        return String::new();
    };
    let mut bytes = Vec::new();
    let _ = pipe.read_to_end(&mut bytes);
    String::from_utf8_lossy(&bytes).trim().to_owned()
}

fn iso8601_now() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0);
    iso8601_from_unix_seconds(seconds)
}

fn iso8601_from_unix_seconds(seconds: i64) -> String {
    let days = seconds.div_euclid(86_400);
    let seconds_of_day = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        seconds_of_day / 3_600,
        (seconds_of_day % 3_600) / 60,
        seconds_of_day % 60
    )
}

/// Howard Hinnant's civil-from-days algorithm.
fn civil_from_days(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let day_of_era = z - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = if month_prime < 10 {
        month_prime + 3
    } else {
        month_prime - 9
    };
    if month <= 2 {
        year += 1;
    }
    (year, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso8601_matches_known_instants() {
        assert_eq!(iso8601_from_unix_seconds(0), "1970-01-01T00:00:00Z");
        assert_eq!(
            iso8601_from_unix_seconds(1_764_000_000),
            "2025-11-24T16:00:00Z"
        );
        assert_eq!(
            iso8601_from_unix_seconds(1_791_273_600),
            "2026-10-06T08:00:00Z"
        );
    }

    #[test]
    fn build_info_parser_ignores_malformed_lines() {
        let directory =
            std::env::temp_dir().join(format!("probe-build-info-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::write(
            directory.join(BUILD_INFO_FILE),
            "Name=amd-mobile-power\nVersion=1.0.10-native\nbroken line\nCommit=abc123\n",
        )
        .unwrap();
        let values = read_build_info(&directory);
        assert_eq!(
            values.get("Version").map(String::as_str),
            Some("1.0.10-native")
        );
        assert_eq!(values.get("Commit").map(String::as_str), Some("abc123"));
        assert!(!values.contains_key("broken line"));
        std::fs::remove_dir_all(&directory).ok();
    }

    #[test]
    fn failed_collection_reports_failed_status() {
        let report = build_report(&BTreeMap::new(), &Collection::default());
        assert_eq!(
            report.get("collectionStatus").and_then(Value::as_str),
            Some("FAILED")
        );
        assert_eq!(
            report
                .get("privacy")
                .and_then(|privacy| privacy.get("localPathsIncluded"))
                .and_then(Value::as_bool),
            Some(false)
        );
    }

    #[test]
    fn platform_redaction_keeps_only_public_fields() {
        let platform = json!({
            "cpu": { "processorName": " AMD Ryzen 7 8845HS ", "vendor": "AuthenticAMD" },
            "isSupported": true,
            "matchedProfile": { "id": "hawk-point-8845hs" },
            "internalPath": "C:\\secret"
        });
        let redacted = redact_platform(&platform);
        assert_eq!(
            redacted.get("processorName").and_then(Value::as_str),
            Some("AMD Ryzen 7 8845HS")
        );
        assert!(redacted.get("internalPath").is_none());
    }

    #[test]
    fn markdown_summary_contains_core_sections() {
        let report = build_report(&BTreeMap::new(), &Collection::default());
        let markdown = render_markdown(&report);
        assert!(markdown.starts_with("# AMD Mobile Power Compatibility Report"));
        assert!(markdown.contains("## Telemetry"));
        assert!(markdown.contains("## Checks"));
        assert!(markdown.contains("## Privacy"));
    }

    #[test]
    fn open_pipe_reports_a_missing_pipe_immediately() {
        let name = format!(r"\\.\pipe\AmdMobilePower.ProbeTest.{}", std::process::id());
        let started = std::time::Instant::now();
        let error = open_pipe(&name).expect_err("missing pipe must fail");
        assert!(error.contains("unable to open the worker pipe"));
        assert!(
            started.elapsed() < Duration::from_secs(1),
            "a missing pipe must not go through the busy-retry loop"
        );
    }

    #[test]
    fn markdown_lists_power_policy_targets() {
        let collection = Collection {
            policy: Some(json!({
                "settings": {
                    "enabled": true,
                    "batteryTarget": { "stapmWatts": 10, "fastWatts": 10, "slowWatts": 10 },
                    "acTarget": { "stapmWatts": 10, "fastWatts": 10, "slowWatts": 10 }
                },
                "lastAttemptSucceeded": true
            })),
            ..Collection::default()
        };
        let report = build_report(&BTreeMap::new(), &collection);
        let markdown = render_markdown(&report);
        assert!(markdown.contains("## Power Policy"));
        assert!(markdown.contains("- Battery target: 10/10/10 W"));
        assert!(markdown.contains("- AC target: 10/10/10 W"));
    }
}
