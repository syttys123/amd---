#![windows_subsystem = "windows"]

use amd_mobile_power_gui::lifecycle::{
    LifecycleAction, LifecycleEvent, LifecycleState, Transition, WindowVisibility,
};
use amd_mobile_power_gui::state;
use amd_mobile_power_gui::worker::{
    ApplyTargetResult, PowerLimitTarget, PowerLineState, PowerPolicySettings, PowerPolicyState,
    ProfilePayload, SnapshotPayload, WorkerClient, DEFAULT_PIPE_NAME,
};
use std::ffi::c_void;
use std::mem::size_of;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, ERROR_ALREADY_EXISTS, HANDLE, HINSTANCE, HWND, LPARAM, LRESULT,
    WPARAM,
};
use windows_sys::Win32::Graphics::Gdi::{UpdateWindow, HBRUSH};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::SystemServices::SS_LEFT;
use windows_sys::Win32::System::Threading::CreateMutexW;
use windows_sys::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NOTIFYICONDATAW,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreatePopupMenu, CreateWindowExW, DefWindowProcW, DestroyMenu, DestroyWindow,
    DispatchMessageW, FindWindowW, GetCursorPos, GetMessageW, GetWindowLongPtrW, LoadCursorW,
    LoadIconW, PostMessageW, PostQuitMessage, RegisterClassExW, SetForegroundWindow,
    SetWindowLongPtrW, SetWindowTextW, ShowWindow, TrackPopupMenu, TranslateMessage, CS_HREDRAW,
    CS_VREDRAW, CW_USEDEFAULT, GWLP_USERDATA, HMENU, IDC_ARROW, IDI_APPLICATION, MF_SEPARATOR,
    MF_STRING, MSG, SIZE_MINIMIZED, SIZE_RESTORED, SW_HIDE, SW_MINIMIZE, SW_RESTORE, SW_SHOWNORMAL,
    TPM_RIGHTBUTTON, WM_APP, WM_CLOSE, WM_COMMAND, WM_CONTEXTMENU, WM_DESTROY, WM_ENDSESSION,
    WM_LBUTTONUP, WM_QUERYENDSESSION, WM_RBUTTONUP, WM_SHOWWINDOW, WM_SIZE, WM_SYSCOMMAND,
    WNDCLASSEXW, WS_BORDER, WS_CHILD, WS_EX_APPWINDOW, WS_OVERLAPPEDWINDOW, WS_VISIBLE,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    GetWindowTextLengthW, GetWindowTextW, SendMessageW, BM_GETCHECK, BM_SETCHECK, BS_AUTOCHECKBOX,
    BS_AUTORADIOBUTTON, ES_NUMBER, ES_RIGHT, SC_MINIMIZE, WS_TABSTOP,
};

const APP_TITLE: &str = "AMD Mobile Power（原生预览）";
const WINDOW_CLASS: &str = "AmdMobilePower.RustGui.Migration.v1";
const MUTEX_NAME: &str = "Local\\AmdMobilePower.RustGui.Migration.v1";
const TRAY_ICON_ID: u32 = 1;
const WM_APP_WAKE: u32 = WM_APP + 1;
const WM_APP_TRAY: u32 = WM_APP + 2;
const WM_APP_STATUS: u32 = WM_APP + 3;
const WM_APP_APPLY_RESULT: u32 = WM_APP + 4;
const WM_APP_POLICY_RESULT: u32 = WM_APP + 5;
const MENU_SHOW: usize = 1;
const MENU_EXIT: usize = 2;
const PRESET_12: usize = 101;
const PRESET_25: usize = 102;
const PRESET_45: usize = 103;
const APPLY_TARGET: usize = 104;
const POLICY_SAVE: usize = 105;
const PRESET_SAVE: usize = 106;
const PRESET_MENU_START: usize = 201;
const PRESET_EDIT_START: usize = 301;

#[derive(Clone, Copy)]
struct PolicyControls {
    enabled: HWND,
    battery_target: HWND,
    ac_target: HWND,
}

struct GuiApp {
    state: LifecycleState,
    _mutex: HANDLE,
    status_label: HWND,
    stop_monitor: Arc<AtomicBool>,
    monitor_thread: Option<JoinHandle<()>>,
    worker_child: Option<Child>,
    worker_pipe: String,
    write_enabled: bool,
    selected_target: PowerLimitTarget,
    apply_in_flight: bool,
    policy_in_flight: bool,
    preset_watts: [i32; 3],
    preset_buttons: Option<[HWND; 3]>,
    preset_edits: Option<[HWND; 3]>,
    selected_preset: Option<usize>,
    policy_controls: Option<PolicyControls>,
    profile: Option<ProfilePayload>,
    saved_policy: Option<PowerPolicySettings>,
    policy_profile_applied: bool,
}

impl GuiApp {
    fn new(mutex: HANDLE) -> Self {
        let preset_watts = state::load_presets();
        Self {
            state: LifecycleState::default(),
            _mutex: mutex,
            status_label: std::ptr::null_mut(),
            stop_monitor: Arc::new(AtomicBool::new(false)),
            monitor_thread: None,
            worker_child: None,
            worker_pipe: String::new(),
            write_enabled: false,
            selected_target: PowerLimitTarget::uniform(preset_watts[0]),
            apply_in_flight: false,
            policy_in_flight: false,
            preset_watts,
            preset_buttons: None,
            preset_edits: None,
            selected_preset: Some(0),
            policy_controls: None,
            profile: None,
            saved_policy: None,
            policy_profile_applied: false,
        }
    }
}

struct StatusUpdate {
    text: String,
    profile: Option<ProfilePayload>,
}

impl Drop for GuiApp {
    fn drop(&mut self) {
        self.stop_monitor.store(true, Ordering::SeqCst);
        if let Some(thread) = self.monitor_thread.take() {
            let _ = thread.join();
        }
        if let Some(mut child) = self.worker_child.take() {
            if !self.worker_pipe.is_empty() {
                let _ = WorkerClient::new(self.worker_pipe.clone()).shutdown();
            }
            let _ = child.try_wait();
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[derive(Debug)]
struct Options {
    start_hidden: bool,
    pipe_name: String,
    worker_executable: Option<PathBuf>,
    enable_write_controls: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            start_hidden: false,
            pipe_name: DEFAULT_PIPE_NAME.to_owned(),
            worker_executable: None,
            enable_write_controls: false,
        }
    }
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn write_wide(buffer: &mut [u16], value: &str) {
    let encoded: Vec<u16> = value.encode_utf16().take(buffer.len() - 1).collect();
    buffer[..encoded.len()].copy_from_slice(&encoded);
    buffer[encoded.len()] = 0;
}

fn format_power_line_raw(value: &str) -> &'static str {
    match value {
        "ac" => "交流电",
        "battery" => "电池",
        _ => "未知",
    }
}

fn format_flag(value: bool) -> &'static str {
    if value {
        "是"
    } else {
        "否"
    }
}

fn format_watts(value: Option<f64>) -> String {
    match value {
        Some(value) => format!("{value:.2} W"),
        None => "无数据".to_owned(),
    }
}

fn format_celsius(value: Option<f64>) -> String {
    match value {
        Some(value) => format!("{value:.1} °C"),
        None => "无数据".to_owned(),
    }
}

fn format_power_line(value: Option<PowerLineState>) -> &'static str {
    match value {
        Some(PowerLineState::Ac) => "交流电",
        Some(PowerLineState::Battery) => "电池",
        Some(PowerLineState::Unknown) | None => "未知",
    }
}

fn format_policy_state(state: Option<&PowerPolicyState>) -> String {
    let Some(state) = state else {
        return "自动策略：不可用".to_owned();
    };
    let Some(settings) = state.settings else {
        return "自动策略：未配置".to_owned();
    };
    let status = if settings.enabled {
        "已启用"
    } else {
        "已停用"
    };
    let last = match (state.last_attempt_succeeded, state.last_observed_power_line) {
        (Some(true), Some(line)) => format!("上次应用：{} · 成功", format_power_line(Some(line))),
        (Some(false), Some(line)) => format!("上次应用：{} · 失败", format_power_line(Some(line))),
        (Some(false), None) => "上次应用：失败".to_owned(),
        (Some(true), None) => "上次应用：成功".to_owned(),
        (None, _) => "上次应用：未执行".to_owned(),
    };
    let error = state
        .last_error
        .as_deref()
        .map(|error| format!("\n策略错误：{error}"))
        .unwrap_or_default();
    format!(
        "自动策略：{}（电池 {} W / 交流 {} W）\n{}{}",
        status, settings.battery_target.stapm_watts, settings.ac_target.stapm_watts, last, error
    )
}

fn format_snapshot(snapshot: &SnapshotPayload, policy: Option<&PowerPolicyState>) -> String {
    let cpu = &snapshot.platform.cpu;
    let limits = &snapshot.platform.limits;
    let telemetry = &snapshot.telemetry;
    let support = if snapshot.platform.is_supported {
        "支持写入"
    } else {
        snapshot
            .platform
            .unsupported_reason
            .as_deref()
            .unwrap_or("不支持写入")
    };
    let profile = snapshot
        .platform
        .matched_profile
        .as_ref()
        .map(|profile| {
            format!(
                "{} [{}-{} W]{}",
                profile.display_name,
                profile.minimum_watts,
                profile.maximum_watts,
                if profile.is_verified {
                    ""
                } else {
                    "（未验证）"
                }
            )
        })
        .unwrap_or_else(|| "无匹配配置".to_owned());

    let status = format!(
        concat!(
            "已连接 worker\n",
            "处理器：{}\n",
            "家族：{} {}\n",
            "平台配置：{}\n",
            "PM 表：{}\n",
            "供电：{}\n",
            "\n",
            "目标功耗：{}\n",
            "STAPM 上限：{}\n",
            "Fast 上限：{}\n",
            "Slow 上限：{}\n",
            "CPU 温度：{}\n",
            "可写字段：STAPM={} Fast={} Slow={}\n",
            "平台状态：{}\n",
            "固件钳制：{}\n",
            "更新时间：{}"
        ),
        cpu.processor_name,
        cpu.ryzen_adj_family
            .map(|value| value.to_string())
            .unwrap_or_else(|| "未知".to_owned()),
        cpu.ryzen_adj_family_name.as_deref().unwrap_or(""),
        profile,
        cpu.pm_table_version.as_deref().unwrap_or("未知"),
        format_power_line_raw(&telemetry.power_line),
        format_watts(telemetry.target_watts),
        format_watts(telemetry.stapm_limit_watts),
        format_watts(telemetry.fast_limit_watts),
        format_watts(telemetry.slow_limit_watts),
        format_celsius(telemetry.tctl_value_celsius),
        format_flag(limits.supports_stapm),
        format_flag(limits.supports_fast),
        format_flag(limits.supports_slow),
        support,
        format_flag(telemetry.has_firmware_clamp),
        telemetry.updated_at.as_deref().unwrap_or("未知")
    );
    format!("{status}\n{}", format_policy_state(policy))
}

fn parse_options() -> Result<Options, String> {
    let mut options = Options::default();
    let mut arguments = std::env::args().skip(1);
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--tray" => options.start_hidden = true,
            "--pipe-name" => {
                options.pipe_name = arguments
                    .next()
                    .ok_or_else(|| "--pipe-name requires a value".to_owned())?;
            }
            "--worker-executable" => {
                options.worker_executable =
                    Some(PathBuf::from(arguments.next().ok_or_else(|| {
                        "--worker-executable requires a value".to_owned()
                    })?));
            }
            "--enable-write-controls" => options.enable_write_controls = true,
            value => return Err(format!("unknown argument: {value}")),
        }
    }
    Ok(options)
}

fn worker_executable_path(options: &Options) -> Option<PathBuf> {
    if let Some(path) = &options.worker_executable {
        return path.is_file().then(|| path.clone());
    }

    std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(|parent| parent.to_path_buf()))
        .map(|directory| directory.join("amdmobilepower_native_worker.exe"))
        .filter(|path| path.is_file())
}

fn start_worker(options: &Options) -> Result<Option<Child>, String> {
    let client = WorkerClient::new(options.pipe_name.clone());
    if client.health().is_ok() {
        return Ok(None);
    }

    let Some(executable) = worker_executable_path(options) else {
        return Ok(None);
    };
    let mut command = Command::new(&executable);
    command
        .arg("--pipe-name")
        .arg(&options.pipe_name)
        .arg("--enable-hardware");
    if options.enable_write_controls {
        command.arg("--enable-write-controls");
    }
    let child = command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .creation_flags(0x08000000)
        .spawn()
        .map_err(|error| format!("unable to start {}: {error}", executable.display()))?;
    Ok(Some(child))
}

unsafe fn app_from_window(hwnd: HWND) -> *mut GuiApp {
    GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut GuiApp
}

unsafe fn post_status(hwnd: HWND, update: StatusUpdate) {
    let pointer = Box::into_raw(Box::new(update));
    if PostMessageW(hwnd, WM_APP_STATUS, 0, pointer as isize) == 0 {
        drop(Box::from_raw(pointer));
    }
}

fn start_worker_monitor(
    hwnd_address: usize,
    pipe_name: String,
    stop: Arc<AtomicBool>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let hwnd = hwnd_address as HWND;
        let client = WorkerClient::new(pipe_name);
        while !stop.load(Ordering::SeqCst) {
            let policy = client.get_power_policy().ok();
            let update = match client.snapshot() {
                Ok(snapshot) => StatusUpdate {
                    text: format_snapshot(&snapshot, policy.as_ref()),
                    profile: snapshot.platform.matched_profile.clone(),
                },
                Err(error) => StatusUpdate {
                    text: format!("worker 不可用\n{error}"),
                    profile: None,
                },
            };
            unsafe {
                post_status(hwnd, update);
            }
            thread::sleep(Duration::from_secs(1));
        }
    })
}

unsafe fn create_status_label(
    hwnd: HWND,
    instance: windows_sys::Win32::Foundation::HINSTANCE,
) -> HWND {
    let class_name = wide("STATIC");
    let text = wide("正在连接 worker…");
    CreateWindowExW(
        0,
        class_name.as_ptr(),
        text.as_ptr(),
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        18,
        40,
        580,
        290,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    )
}

unsafe fn create_title_label(
    hwnd: HWND,
    instance: windows_sys::Win32::Foundation::HINSTANCE,
) -> HWND {
    let class_name = wide("STATIC");
    let text = wide("AMD Mobile Power");
    CreateWindowExW(
        0,
        class_name.as_ptr(),
        text.as_ptr(),
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        18,
        12,
        580,
        22,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    )
}

unsafe fn create_action_buttons(
    hwnd: HWND,
    instance: HINSTANCE,
    preset_watts: [i32; 3],
) -> [HWND; 3] {
    let button_class = wide("BUTTON");
    let controls = [
        (PRESET_12, format!("{} W", preset_watts[0]), 18, 348, 90),
        (PRESET_25, format!("{} W", preset_watts[1]), 116, 348, 90),
        (PRESET_45, format!("{} W", preset_watts[2]), 214, 348, 90),
        (APPLY_TARGET, "应用".to_owned(), 360, 348, 120),
    ];
    let mut presets = [std::ptr::null_mut(); 3];
    let mut first_preset = true;
    for (index, (id, label, x, y, width)) in controls.into_iter().enumerate() {
        let text = wide(&label);
        let is_apply = id == APPLY_TARGET;
        let style = WS_CHILD
            | WS_VISIBLE
            | WS_TABSTOP
            | if is_apply {
                0
            } else {
                BS_AUTORADIOBUTTON as u32
            };
        let button = CreateWindowExW(
            0,
            button_class.as_ptr(),
            text.as_ptr(),
            style,
            x,
            y,
            width,
            32,
            hwnd,
            id as HMENU,
            instance,
            std::ptr::null(),
        );
        if first_preset && !button.is_null() {
            SendMessageW(button, BM_SETCHECK, 1, 0);
            first_preset = false;
        }
        if index < presets.len() {
            presets[index] = button;
        }
    }
    presets
}

unsafe fn create_preset_controls(
    hwnd: HWND,
    instance: HINSTANCE,
    preset_watts: [i32; 3],
) -> [HWND; 3] {
    let static_class = wide("STATIC");
    let edit_class = wide("EDIT");
    let button_class = wide("BUTTON");
    let label_text = wide("快捷预设");
    let save_text = wide("保存预设");
    let edit_style =
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_NUMBER as u32 | ES_RIGHT as u32;

    CreateWindowExW(
        0,
        static_class.as_ptr(),
        label_text.as_ptr(),
        WS_CHILD | WS_VISIBLE,
        18,
        396,
        76,
        22,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );

    let mut edits = [std::ptr::null_mut(); 3];
    for (index, watts) in preset_watts.into_iter().enumerate() {
        let value = wide(&watts.to_string());
        edits[index] = CreateWindowExW(
            0,
            edit_class.as_ptr(),
            value.as_ptr(),
            edit_style,
            98 + index as i32 * 72,
            392,
            58,
            26,
            hwnd,
            (PRESET_EDIT_START + index) as HMENU,
            instance,
            std::ptr::null(),
        );
    }

    CreateWindowExW(
        0,
        button_class.as_ptr(),
        save_text.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP,
        320,
        390,
        100,
        30,
        hwnd,
        PRESET_SAVE as HMENU,
        instance,
        std::ptr::null(),
    );

    edits
}

unsafe fn get_control_text(hwnd: HWND) -> String {
    if hwnd.is_null() {
        return String::new();
    }
    let length = GetWindowTextLengthW(hwnd);
    if length <= 0 {
        return String::new();
    }
    let mut buffer = vec![0u16; length as usize + 1];
    let copied = GetWindowTextW(hwnd, buffer.as_mut_ptr(), buffer.len() as i32);
    if copied <= 0 {
        return String::new();
    }
    String::from_utf16_lossy(&buffer[..copied as usize])
}

unsafe fn read_edit_watts(hwnd: HWND, fallback: i32, minimum: i32, maximum: i32) -> i32 {
    let text = get_control_text(hwnd);
    let parsed = text.trim().parse::<i32>().unwrap_or(fallback);
    parsed.clamp(minimum, maximum)
}

unsafe fn set_edit_watts(hwnd: HWND, watts: i32) {
    if hwnd.is_null() {
        return;
    }
    let text = wide(&watts.to_string());
    SetWindowTextW(hwnd, text.as_ptr());
}

fn clamp_preset_values(presets: [i32; 3], minimum: i32, maximum: i32) -> [i32; 3] {
    presets.map(|watts| watts.clamp(minimum, maximum))
}

fn preset_menu_label(index: usize, watts: i32) -> String {
    format!("应用预设 {}：{} W", index + 1, watts)
}

unsafe fn refresh_preset_controls(app: &GuiApp) {
    if let Some(buttons) = app.preset_buttons {
        for (index, button) in buttons.into_iter().enumerate() {
            if !button.is_null() {
                let text = wide(&format!("{} W", app.preset_watts[index]));
                SetWindowTextW(button, text.as_ptr());
            }
        }
    }
    if let Some(edits) = app.preset_edits {
        for (index, edit) in edits.into_iter().enumerate() {
            set_edit_watts(edit, app.preset_watts[index]);
        }
    }
}

unsafe fn create_policy_controls(hwnd: HWND, instance: HINSTANCE) -> PolicyControls {
    let static_class = wide("STATIC");
    let edit_class = wide("EDIT");
    let button_class = wide("BUTTON");
    let battery_label = wide("电池目标");
    let ac_label = wide("交流目标");
    let enabled_label = wide("启用");
    let save_label = wide("保存策略");
    let edit_style =
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_NUMBER as u32 | ES_RIGHT as u32;

    CreateWindowExW(
        0,
        static_class.as_ptr(),
        battery_label.as_ptr(),
        WS_CHILD | WS_VISIBLE,
        18,
        440,
        108,
        22,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );
    let battery_target = CreateWindowExW(
        0,
        edit_class.as_ptr(),
        wide("12").as_ptr(),
        edit_style,
        132,
        436,
        54,
        26,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );
    CreateWindowExW(
        0,
        static_class.as_ptr(),
        ac_label.as_ptr(),
        WS_CHILD | WS_VISIBLE,
        200,
        440,
        62,
        22,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );
    let ac_target = CreateWindowExW(
        0,
        edit_class.as_ptr(),
        wide("45").as_ptr(),
        edit_style,
        266,
        436,
        54,
        26,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );
    let enabled = CreateWindowExW(
        0,
        button_class.as_ptr(),
        enabled_label.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX as u32,
        336,
        436,
        82,
        26,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );
    let _save = CreateWindowExW(
        0,
        button_class.as_ptr(),
        save_label.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP,
        428,
        434,
        120,
        30,
        hwnd,
        POLICY_SAVE as HMENU,
        instance,
        std::ptr::null(),
    );

    PolicyControls {
        enabled,
        battery_target,
        ac_target,
    }
}

fn format_policy_result(settings: PowerPolicySettings, result: Result<(), String>) -> String {
    match result {
        Ok(()) => format!(
            "自动策略已保存。\n电池 {} W / 交流 {} W。\n{}",
            settings.battery_target.stapm_watts,
            settings.ac_target.stapm_watts,
            if settings.enabled {
                "已启用。"
            } else {
                "已停用。"
            }
        ),
        Err(error) => format!("策略保存失败。\n{error}"),
    }
}

unsafe fn save_preset_edits(app: &mut GuiApp) -> Result<(), String> {
    let Some(edits) = app.preset_edits else {
        return Err("预设编辑框尚未创建。".to_owned());
    };
    let (minimum, maximum) = app
        .profile
        .as_ref()
        .map(|profile| (profile.minimum_watts, profile.maximum_watts))
        .unwrap_or((5, 60));
    let mut presets = app.preset_watts;
    for (index, edit) in edits.into_iter().enumerate() {
        presets[index] = read_edit_watts(edit, presets[index], minimum, maximum);
    }
    app.preset_watts = presets;
    refresh_preset_controls(app);
    if let Some(index) = app.selected_preset {
        select_preset(app, index);
    }
    state::save_presets(presets)
}

fn start_policy_save(hwnd_address: usize, pipe_name: String, settings: PowerPolicySettings) {
    thread::spawn(move || {
        let client = WorkerClient::new(pipe_name);
        let deadline = Instant::now() + Duration::from_secs(10);
        while client.health().is_err() && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(200));
        }
        let result = client
            .set_power_policy(settings)
            .map(|_| ())
            .and_then(|_| state::save_power_policy(settings));
        let text = format_policy_result(settings, result);
        unsafe {
            let pointer = Box::into_raw(Box::new(text));
            let hwnd = hwnd_address as HWND;
            if PostMessageW(hwnd, WM_APP_POLICY_RESULT, 0, pointer as isize) == 0 {
                drop(Box::from_raw(pointer));
            }
        }
    });
}

fn format_apply_result(
    target: PowerLimitTarget,
    result: Result<ApplyTargetResult, String>,
) -> String {
    match result {
        Ok(result) if result.is_successful => {
            let mut text = format!(
                "已应用 {} W / {} W / {} W。\n",
                target.stapm_watts, target.fast_watts, target.slow_watts
            );
            if result.has_firmware_clamp || result.has_stapm_warning {
                text.push_str("固件报告了钳制或 STAPM 警告。");
            } else {
                text.push_str("回读校验通过。");
            }
            text
        }
        Ok(result) => format!(
            "应用失败。\n{}\n已尝试恢复：{}\n恢复成功：{}",
            result
                .error
                .unwrap_or_else(|| "worker 返回了未成功的结果".to_owned()),
            result.restore_attempted,
            result.restored_previous_limits
        ),
        Err(error) => format!("应用失败。\n{error}"),
    }
}

fn start_apply(hwnd_address: usize, pipe_name: String, target: PowerLimitTarget) {
    thread::spawn(move || {
        let result = WorkerClient::new(pipe_name).apply_target(target);
        let text = format_apply_result(target, result);
        unsafe {
            let pointer = Box::into_raw(Box::new(text));
            let hwnd = hwnd_address as HWND;
            if PostMessageW(hwnd, WM_APP_APPLY_RESULT, 0, pointer as isize) == 0 {
                drop(Box::from_raw(pointer));
            }
        }
    });
}

unsafe fn select_preset(app: &mut GuiApp, index: usize) {
    if index >= app.preset_watts.len() {
        return;
    }
    app.selected_preset = Some(index);
    app.selected_target = PowerLimitTarget::uniform(app.preset_watts[index]);
    if let Some(buttons) = app.preset_buttons {
        for (button_index, button) in buttons.into_iter().enumerate() {
            if !button.is_null() {
                SendMessageW(button, BM_SETCHECK, usize::from(button_index == index), 0);
            }
        }
    }
}

unsafe fn start_preset_apply(app: &mut GuiApp, hwnd: HWND, index: usize) {
    if !app.write_enabled || app.apply_in_flight || index >= app.preset_watts.len() {
        return;
    }
    select_preset(app, index);
    app.apply_in_flight = true;
    if !app.status_label.is_null() {
        let text = wide(&format!(
            "正在应用预设 {}：{} W / {} W / {} W…",
            index + 1,
            app.selected_target.stapm_watts,
            app.selected_target.fast_watts,
            app.selected_target.slow_watts
        ));
        SetWindowTextW(app.status_label, text.as_ptr());
    }
    start_apply(hwnd as usize, app.worker_pipe.clone(), app.selected_target);
}

unsafe fn apply_profile_to_presets(app: &mut GuiApp, hwnd: HWND, profile: &ProfilePayload) {
    let minimum = profile.minimum_watts;
    let maximum = profile.maximum_watts;
    if minimum > maximum {
        return;
    }
    app.profile = Some(profile.clone());
    app.preset_watts = clamp_preset_values(app.preset_watts, minimum, maximum);
    if let Some(index) = app.selected_preset {
        app.selected_target = PowerLimitTarget::uniform(app.preset_watts[index]);
    } else if app.selected_target.stapm_watts < minimum || app.selected_target.stapm_watts > maximum
    {
        app.selected_target = PowerLimitTarget::uniform(app.preset_watts[0]);
        app.selected_preset = Some(0);
    }
    refresh_preset_controls(app);

    if !app.policy_profile_applied {
        if let Some(controls) = app.policy_controls {
            let saved = app.saved_policy;
            let battery = saved
                .map(|settings| settings.battery_target.stapm_watts)
                .unwrap_or(12)
                .clamp(minimum, maximum);
            let ac = saved
                .map(|settings| settings.ac_target.stapm_watts)
                .unwrap_or(45)
                .clamp(minimum, maximum);
            set_edit_watts(controls.battery_target, battery);
            set_edit_watts(controls.ac_target, ac);
            SendMessageW(
                controls.enabled,
                BM_SETCHECK,
                if saved.map(|settings| settings.enabled).unwrap_or(false) {
                    1
                } else {
                    0
                },
                0,
            );
            app.policy_profile_applied = true;
            if saved.map(|settings| settings.enabled).unwrap_or(false) && !app.policy_in_flight {
                app.policy_in_flight = true;
                start_policy_save(hwnd as usize, app.worker_pipe.clone(), saved.unwrap());
            }
        }
    }
}

unsafe fn apply_actions(hwnd: HWND, transition: Transition) {
    for action in transition.actions {
        match action {
            LifecycleAction::AddTrayIcon => add_tray_icon(hwnd),
            LifecycleAction::RemoveTrayIcon => remove_tray_icon(hwnd),
            LifecycleAction::ShowWindow => {
                ShowWindow(hwnd, SW_RESTORE);
                UpdateWindow(hwnd);
            }
            LifecycleAction::MinimizeWindow => {
                ShowWindow(hwnd, SW_MINIMIZE);
            }
            LifecycleAction::HideWindow => {
                ShowWindow(hwnd, SW_HIDE);
            }
            LifecycleAction::BringToForeground => {
                SetForegroundWindow(hwnd);
            }
            LifecycleAction::ExitMessageLoop => {
                PostQuitMessage(0);
            }
        }
    }
}

unsafe fn dispatch(app: &mut GuiApp, hwnd: HWND, event: LifecycleEvent) -> Transition {
    let transition = app.state.handle_event(event);
    apply_actions(hwnd, transition.clone());
    transition
}

unsafe fn add_tray_icon(hwnd: HWND) {
    let mut data = NOTIFYICONDATAW {
        cbSize: size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: TRAY_ICON_ID,
        uFlags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
        uCallbackMessage: WM_APP_TRAY,
        hIcon: LoadIconW(std::ptr::null_mut(), IDI_APPLICATION),
        ..Default::default()
    };
    write_wide(&mut data.szTip, APP_TITLE);
    Shell_NotifyIconW(NIM_ADD, &data);
}

unsafe fn remove_tray_icon(hwnd: HWND) {
    let data = NOTIFYICONDATAW {
        cbSize: size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: TRAY_ICON_ID,
        ..Default::default()
    };
    Shell_NotifyIconW(NIM_DELETE, &data);
}

unsafe fn show_tray_menu(hwnd: HWND, app: &GuiApp) {
    let menu: HMENU = CreatePopupMenu();
    if menu.is_null() {
        return;
    }

    let show_text = wide("显示主界面");
    let exit_text = wide("退出");
    AppendMenuW(menu, MF_STRING, MENU_SHOW, show_text.as_ptr());
    if app.write_enabled {
        AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
        for (index, watts) in app.preset_watts.into_iter().enumerate() {
            let label = wide(&preset_menu_label(index, watts));
            AppendMenuW(menu, MF_STRING, PRESET_MENU_START + index, label.as_ptr());
        }
    }
    AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
    AppendMenuW(menu, MF_STRING, MENU_EXIT, exit_text.as_ptr());

    let mut point = Default::default();
    if GetCursorPos(&mut point) != 0 {
        SetForegroundWindow(hwnd);
        TrackPopupMenu(
            menu,
            TPM_RIGHTBUTTON,
            point.x,
            point.y,
            0,
            hwnd,
            std::ptr::null(),
        );
    }
    DestroyMenu(menu);
}

unsafe extern "system" fn window_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let app = app_from_window(hwnd);
    if app.is_null() {
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }
    let app = &mut *app;

    match message {
        WM_CLOSE => {
            dispatch(app, hwnd, LifecycleEvent::CloseRequested);
            0
        }
        WM_SIZE => {
            match wparam as u32 {
                SIZE_MINIMIZED => {
                    dispatch(app, hwnd, LifecycleEvent::WindowMinimized);
                }
                SIZE_RESTORED => {
                    dispatch(app, hwnd, LifecycleEvent::WindowShown);
                }
                _ => {}
            }
            DefWindowProcW(hwnd, message, wparam, lparam)
        }
        WM_SHOWWINDOW => {
            if wparam != 0 {
                dispatch(app, hwnd, LifecycleEvent::WindowShown);
            } else if app.state.visibility() != WindowVisibility::Hidden {
                dispatch(app, hwnd, LifecycleEvent::WindowHidden);
            }
            0
        }
        WM_SYSCOMMAND if (wparam as u32 & 0xFFF0) == SC_MINIMIZE => {
            dispatch(app, hwnd, LifecycleEvent::MinimizeRequested);
            0
        }
        WM_APP_WAKE => {
            dispatch(app, hwnd, LifecycleEvent::SecondInstanceWakeRequested);
            dispatch(app, hwnd, LifecycleEvent::ProcessPendingWake);
            0
        }
        WM_APP_TRAY => {
            let mouse_message = (lparam as u32) & 0xFFFF;
            if mouse_message == WM_LBUTTONUP {
                dispatch(app, hwnd, LifecycleEvent::TrayShowRequested);
            } else if mouse_message == WM_RBUTTONUP || mouse_message == WM_CONTEXTMENU {
                show_tray_menu(hwnd, app);
            }
            0
        }
        WM_APP_STATUS => {
            let pointer = lparam as *mut StatusUpdate;
            if !pointer.is_null() {
                let update = Box::from_raw(pointer);
                if !app.status_label.is_null() {
                    let text = wide(&update.text);
                    SetWindowTextW(app.status_label, text.as_ptr());
                }
                if let Some(profile) = &update.profile {
                    apply_profile_to_presets(app, hwnd, profile);
                }
            }
            0
        }
        WM_APP_APPLY_RESULT => {
            app.apply_in_flight = false;
            let pointer = lparam as *mut String;
            if !pointer.is_null() {
                let text = Box::from_raw(pointer);
                if !app.status_label.is_null() {
                    let text = wide(&text);
                    SetWindowTextW(app.status_label, text.as_ptr());
                }
            }
            0
        }
        WM_APP_POLICY_RESULT => {
            app.policy_in_flight = false;
            let pointer = lparam as *mut String;
            if !pointer.is_null() {
                let text = Box::from_raw(pointer);
                if !app.status_label.is_null() {
                    let text = wide(&text);
                    SetWindowTextW(app.status_label, text.as_ptr());
                }
            }
            0
        }
        WM_COMMAND => {
            let command = wparam & 0xFFFF;
            match command {
                MENU_SHOW => {
                    dispatch(app, hwnd, LifecycleEvent::TrayShowRequested);
                }
                MENU_EXIT => {
                    dispatch(app, hwnd, LifecycleEvent::TrayExitRequested);
                }
                PRESET_12 | PRESET_25 | PRESET_45 if app.write_enabled => {
                    let preset_index = match command {
                        PRESET_12 => 0,
                        PRESET_25 => 1,
                        PRESET_45 => 2,
                        _ => 0,
                    };
                    select_preset(app, preset_index);
                }
                PRESET_SAVE if app.write_enabled => {
                    let result = save_preset_edits(app);
                    let message = match result {
                        Ok(()) => format!(
                            "快捷预设已保存：{} W / {} W / {} W。",
                            app.preset_watts[0], app.preset_watts[1], app.preset_watts[2]
                        ),
                        Err(error) => format!("快捷预设保存失败。\n{error}"),
                    };
                    if !app.status_label.is_null() {
                        let text = wide(&message);
                        SetWindowTextW(app.status_label, text.as_ptr());
                    }
                }
                APPLY_TARGET if app.write_enabled && !app.apply_in_flight => {
                    app.apply_in_flight = true;
                    if !app.status_label.is_null() {
                        let text = wide(&format!(
                            "正在应用 {} W / {} W / {} W…",
                            app.selected_target.stapm_watts,
                            app.selected_target.fast_watts,
                            app.selected_target.slow_watts
                        ));
                        SetWindowTextW(app.status_label, text.as_ptr());
                    }
                    start_apply(hwnd as usize, app.worker_pipe.clone(), app.selected_target);
                }
                POLICY_SAVE if app.write_enabled && !app.policy_in_flight => {
                    if let Some(controls) = app.policy_controls {
                        let (minimum, maximum) = app
                            .profile
                            .as_ref()
                            .map(|profile| (profile.minimum_watts, profile.maximum_watts))
                            .unwrap_or((5, 60));
                        let battery_target =
                            read_edit_watts(controls.battery_target, 12, minimum, maximum);
                        let ac_target = read_edit_watts(controls.ac_target, 45, minimum, maximum);
                        set_edit_watts(controls.battery_target, battery_target);
                        set_edit_watts(controls.ac_target, ac_target);
                        let settings = PowerPolicySettings {
                            enabled: SendMessageW(controls.enabled, BM_GETCHECK, 0, 0) != 0,
                            battery_target: PowerLimitTarget::uniform(battery_target),
                            ac_target: PowerLimitTarget::uniform(ac_target),
                        };
                        app.saved_policy = Some(settings);
                        app.policy_in_flight = true;
                        if !app.status_label.is_null() {
                            let text = wide("正在保存自动策略…");
                            SetWindowTextW(app.status_label, text.as_ptr());
                        }
                        start_policy_save(hwnd as usize, app.worker_pipe.clone(), settings);
                    }
                }
                _ if app.write_enabled
                    && (PRESET_MENU_START..PRESET_MENU_START + 3).contains(&command) =>
                {
                    start_preset_apply(app, hwnd, command - PRESET_MENU_START);
                }
                _ => {}
            }
            0
        }
        WM_QUERYENDSESSION => 1,
        WM_ENDSESSION => {
            dispatch(app, hwnd, LifecycleEvent::ExitRequested);
            0
        }
        WM_DESTROY => {
            dispatch(app, hwnd, LifecycleEvent::ExitRequested);
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let options = parse_options()?;
    let instance = unsafe { GetModuleHandleW(std::ptr::null()) };
    if instance.is_null() {
        return Err("GetModuleHandleW returned null".into());
    }

    let class_name = wide(WINDOW_CLASS);
    let window_title = wide(APP_TITLE);
    let window_class = WNDCLASSEXW {
        cbSize: size_of::<WNDCLASSEXW>() as u32,
        style: CS_HREDRAW | CS_VREDRAW,
        lpfnWndProc: Some(window_proc),
        hInstance: instance,
        hCursor: unsafe { LoadCursorW(std::ptr::null_mut(), IDC_ARROW) },
        hbrBackground: std::ptr::null_mut::<c_void>() as HBRUSH,
        lpszClassName: class_name.as_ptr(),
        ..Default::default()
    };
    if unsafe { RegisterClassExW(&window_class) } == 0 {
        return Err("RegisterClassExW failed".into());
    }

    let mutex_name = wide(MUTEX_NAME);
    let mutex = unsafe { CreateMutexW(std::ptr::null(), 0, mutex_name.as_ptr()) };
    if mutex.is_null() {
        return Err("CreateMutexW failed".into());
    }
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        let class_name = wide(WINDOW_CLASS);
        let existing = unsafe { FindWindowW(class_name.as_ptr(), std::ptr::null()) };
        if !existing.is_null() {
            unsafe {
                PostMessageW(existing, WM_APP_WAKE, 0, 0);
            }
        }
        unsafe {
            CloseHandle(mutex);
        }
        return Ok(());
    }

    let window_height = if options.enable_write_controls {
        580
    } else {
        380
    };
    let hwnd = unsafe {
        CreateWindowExW(
            WS_EX_APPWINDOW,
            class_name.as_ptr(),
            window_title.as_ptr(),
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            620,
            window_height,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            instance,
            std::ptr::null(),
        )
    };
    if hwnd.is_null() {
        unsafe {
            CloseHandle(mutex);
        }
        return Err("CreateWindowExW failed".into());
    }

    let app = Box::into_raw(Box::new(GuiApp::new(mutex)));
    unsafe {
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, app as isize);
        (*app).write_enabled = options.enable_write_controls;
        let _ = create_title_label(hwnd, instance);
        (*app).status_label = create_status_label(hwnd, instance);
        if options.enable_write_controls {
            (*app).preset_buttons =
                Some(create_action_buttons(hwnd, instance, (*app).preset_watts));
            (*app).preset_edits = Some(create_preset_controls(hwnd, instance, (*app).preset_watts));
            (*app).policy_controls = Some(create_policy_controls(hwnd, instance));
            (*app).saved_policy = state::load_power_policy();
            if let Some(saved) = (*app).saved_policy {
                if let Some(controls) = (*app).policy_controls {
                    set_edit_watts(controls.battery_target, saved.battery_target.stapm_watts);
                    set_edit_watts(controls.ac_target, saved.ac_target.stapm_watts);
                    SendMessageW(
                        controls.enabled,
                        BM_SETCHECK,
                        if saved.enabled { 1 } else { 0 },
                        0,
                    );
                }
            }
        }
    }

    match start_worker(&options) {
        Ok(child) => unsafe {
            (*app).worker_child = child;
            (*app).worker_pipe = options.pipe_name.clone();
        },
        Err(error) => unsafe {
            let text = wide(&format!("Worker start failed\n{error}"));
            SetWindowTextW((*app).status_label, text.as_ptr());
        },
    }
    let monitor = start_worker_monitor(hwnd as usize, options.pipe_name.clone(), unsafe {
        (*app).stop_monitor.clone()
    });
    unsafe {
        (*app).monitor_thread = Some(monitor);
    }

    unsafe {
        dispatch(
            &mut *app,
            hwnd,
            LifecycleEvent::StartupRequested {
                start_hidden: options.start_hidden,
            },
        );
        if !options.start_hidden {
            ShowWindow(hwnd, SW_SHOWNORMAL);
            UpdateWindow(hwnd);
        }
    }

    let mut message = MSG::default();
    loop {
        let result = unsafe { GetMessageW(&mut message, std::ptr::null_mut(), 0, 0) };
        if result <= 0 {
            break;
        }
        unsafe {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }

    unsafe {
        DestroyWindow(hwnd);
        drop(Box::from_raw(app));
        CloseHandle(mutex);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{clamp_preset_values, format_policy_state, format_snapshot, preset_menu_label};
    use amd_mobile_power_gui::worker::{
        CpuPayload, LimitsPayload, PlatformPayload, PowerLimitTarget, PowerLineState,
        PowerPolicySettings, PowerPolicyState, ProfilePayload, SnapshotPayload, TelemetryPayload,
    };

    fn sample_snapshot() -> SnapshotPayload {
        SnapshotPayload {
            platform: PlatformPayload {
                cpu: CpuPayload {
                    processor_name: "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics".to_owned(),
                    vendor: "AuthenticAMD".to_owned(),
                    ryzen_adj_family: Some(10),
                    ryzen_adj_family_name: Some("Hawk Point".to_owned()),
                    smu_bios_version: Some("15".to_owned()),
                    pm_table_version: Some("4c0009".to_owned()),
                },
                limits: LimitsPayload {
                    supports_stapm: true,
                    supports_fast: true,
                    supports_slow: true,
                    supports_any: true,
                },
                matched_profile: Some(ProfilePayload {
                    id: "hawk-point-8845hs".to_owned(),
                    display_name: "Hawk Point 8845HS development profile".to_owned(),
                    minimum_watts: 5,
                    maximum_watts: 60,
                    default_watts: 25,
                    is_verified: true,
                }),
                is_supported: true,
                unsupported_reason: None,
            },
            telemetry: TelemetryPayload {
                target_watts: Some(10.0),
                stapm_value_watts: Some(9.99),
                fast_value_watts: Some(10.0),
                slow_value_watts: Some(10.0),
                stapm_limit_watts: Some(10.0),
                fast_limit_watts: Some(10.0),
                slow_limit_watts: Some(10.0),
                tctl_value_celsius: Some(44.9),
                tctl_limit_celsius: Some(95.0),
                power_line: "battery".to_owned(),
                updated_at: Some("2026-11-10T15:10:00Z".to_owned()),
                has_firmware_clamp: false,
            },
        }
    }

    #[test]
    fn snapshot_dashboard_is_localized() {
        let text = format_snapshot(&sample_snapshot(), None);

        assert!(text.contains("已连接 worker"), "{text}");
        assert!(text.contains("处理器：AMD Ryzen 7 8845HS"), "{text}");
        assert!(
            text.contains("平台配置：Hawk Point 8845HS development profile [5-60 W]"),
            "{text}"
        );
        assert!(text.contains("供电：电池"), "{text}");
        assert!(text.contains("目标功耗：10.00 W"), "{text}");
        assert!(text.contains("Fast 上限：10.00 W"), "{text}");
        assert!(text.contains("CPU 温度：44.9 °C"), "{text}");
        assert!(text.contains("平台状态：支持写入"), "{text}");
        assert!(text.contains("自动策略：不可用"), "{text}");
        assert!(text.contains("固件钳制：否"), "{text}");
        assert!(
            text.contains("可写字段：STAPM=是 Fast=是 Slow=是"),
            "{text}"
        );
        assert!(!text.contains("Worker: connected"), "{text}");
        assert!(!text.contains("Power source"), "{text}");
    }

    #[test]
    fn unverified_profile_is_marked_in_chinese() {
        let mut snapshot = sample_snapshot();
        if let Some(profile) = snapshot.platform.matched_profile.as_mut() {
            profile.is_verified = false;
        }

        let text = format_snapshot(&snapshot, None);

        assert!(text.contains("（未验证）"), "{text}");
    }

    #[test]
    fn policy_state_is_localized() {
        let state = PowerPolicyState {
            settings: Some(PowerPolicySettings {
                enabled: true,
                battery_target: PowerLimitTarget::uniform(10),
                ac_target: PowerLimitTarget::uniform(12),
            }),
            last_observed_power_line: Some(PowerLineState::Battery),
            last_applied_target: Some(PowerLimitTarget::uniform(10)),
            last_attempt_at: Some("2026-11-10T15:10:00Z".to_owned()),
            last_attempt_succeeded: Some(true),
            last_error: None,
        };

        let text = format_policy_state(Some(&state));

        assert!(
            text.contains("自动策略：已启用（电池 10 W / 交流 12 W）"),
            "{text}"
        );
        assert!(text.contains("上次应用：电池 · 成功"), "{text}");
    }

    #[test]
    fn missing_policy_surfaces_chinese_placeholder() {
        assert_eq!(format_policy_state(None), "自动策略：不可用");
    }

    #[test]
    fn presets_are_clamped_to_the_active_profile() {
        assert_eq!(clamp_preset_values([2, 25, 80], 5, 60), [5, 25, 60]);
    }

    #[test]
    fn tray_preset_labels_include_their_editable_value() {
        assert_eq!(preset_menu_label(0, 10), "应用预设 1：10 W");
        assert_eq!(preset_menu_label(2, 43), "应用预设 3：43 W");
    }
}
