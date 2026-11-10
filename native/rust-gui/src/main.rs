#![windows_subsystem = "windows"]

use amd_mobile_power_gui::lifecycle::{
    LifecycleAction, LifecycleEvent, LifecycleState, Transition, WindowVisibility,
};
use amd_mobile_power_gui::worker::{
    ApplyTargetResult, PowerLimitTarget, ProfilePayload, SnapshotPayload, WorkerClient,
    DEFAULT_PIPE_NAME,
};
use std::ffi::c_void;
use std::mem::size_of;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;
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
    WNDCLASSEXW, WS_CHILD, WS_EX_APPWINDOW, WS_OVERLAPPEDWINDOW, WS_VISIBLE,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    SendMessageW, BM_SETCHECK, BS_AUTORADIOBUTTON, SC_MINIMIZE, WS_TABSTOP,
};

const APP_TITLE: &str = "AMD Mobile Power - Rust GUI Preview";
const WINDOW_CLASS: &str = "AmdMobilePower.RustGui.Migration.v1";
const MUTEX_NAME: &str = "Local\\AmdMobilePower.RustGui.Migration.v1";
const TRAY_ICON_ID: u32 = 1;
const WM_APP_WAKE: u32 = WM_APP + 1;
const WM_APP_TRAY: u32 = WM_APP + 2;
const WM_APP_STATUS: u32 = WM_APP + 3;
const WM_APP_APPLY_RESULT: u32 = WM_APP + 4;
const MENU_SHOW: usize = 1;
const MENU_EXIT: usize = 2;
const PRESET_12: usize = 101;
const PRESET_25: usize = 102;
const PRESET_45: usize = 103;
const APPLY_TARGET: usize = 104;

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
    preset_watts: [i32; 3],
    preset_buttons: Option<[HWND; 3]>,
}

impl GuiApp {
    fn new(mutex: HANDLE) -> Self {
        Self {
            state: LifecycleState::default(),
            _mutex: mutex,
            status_label: std::ptr::null_mut(),
            stop_monitor: Arc::new(AtomicBool::new(false)),
            monitor_thread: None,
            worker_child: None,
            worker_pipe: String::new(),
            write_enabled: false,
            selected_target: PowerLimitTarget::uniform(12),
            apply_in_flight: false,
            preset_watts: [12, 25, 45],
            preset_buttons: None,
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

fn format_watts(value: Option<f64>) -> String {
    match value {
        Some(value) => format!("{value:.2} W"),
        None => "n/a".to_owned(),
    }
}

fn format_celsius(value: Option<f64>) -> String {
    match value {
        Some(value) => format!("{value:.1} C"),
        None => "n/a".to_owned(),
    }
}

fn format_snapshot(snapshot: &SnapshotPayload) -> String {
    let cpu = &snapshot.platform.cpu;
    let limits = &snapshot.platform.limits;
    let telemetry = &snapshot.telemetry;
    let support = if snapshot.platform.is_supported {
        "supported"
    } else {
        snapshot
            .platform
            .unsupported_reason
            .as_deref()
            .unwrap_or("unsupported")
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
                    " (unverified)"
                }
            )
        })
        .unwrap_or_else(|| "n/a".to_owned());

    format!(
        concat!(
            "Worker: connected\n",
            "CPU: {}\n",
            "Family: {} {}\n",
            "Profile: {}\n",
            "PM table: {}\n",
            "Power source: {}\n",
            "\n",
            "Target: {}\n",
            "STAPM like target: {}\n",
            "Fast limit: {}\n",
            "Slow limit: {}\n",
            "Temperature: {}\n",
            "\n",
            "Capabilities: STAPM={} Fast={} Slow={}\n",
            "Platform: {}\n",
            "Firmware clamp: {}\n",
            "Updated: {}"
        ),
        cpu.processor_name,
        cpu.ryzen_adj_family
            .map(|value| value.to_string())
            .unwrap_or_else(|| "n/a".to_owned()),
        cpu.ryzen_adj_family_name.as_deref().unwrap_or(""),
        profile,
        cpu.pm_table_version.as_deref().unwrap_or("n/a"),
        telemetry.power_line,
        format_watts(telemetry.target_watts),
        format_watts(telemetry.stapm_limit_watts),
        format_watts(telemetry.fast_limit_watts),
        format_watts(telemetry.slow_limit_watts),
        format_celsius(telemetry.tctl_value_celsius),
        limits.supports_stapm,
        limits.supports_fast,
        limits.supports_slow,
        support,
        telemetry.has_firmware_clamp,
        telemetry.updated_at.as_deref().unwrap_or("n/a")
    )
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
            let update = match client.snapshot() {
                Ok(snapshot) => StatusUpdate {
                    text: format_snapshot(&snapshot),
                    profile: snapshot.platform.matched_profile.clone(),
                },
                Err(error) => StatusUpdate {
                    text: format!("Worker: unavailable\n{error}"),
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
    let text = wide("Connecting to worker...");
    CreateWindowExW(
        0,
        class_name.as_ptr(),
        text.as_ptr(),
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        18,
        18,
        580,
        300,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    )
}

unsafe fn create_action_buttons(hwnd: HWND, instance: HINSTANCE) -> [HWND; 3] {
    let button_class = wide("BUTTON");
    let controls = [
        (PRESET_12, "12 W", 18, 330, 90),
        (PRESET_25, "25 W", 116, 330, 90),
        (PRESET_45, "45 W", 214, 330, 90),
        (APPLY_TARGET, "Apply", 360, 330, 120),
    ];
    let mut presets = [std::ptr::null_mut(); 3];
    let mut first_preset = true;
    for (index, (id, label, x, y, width)) in controls.into_iter().enumerate() {
        let text = wide(label);
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
            id as usize as HMENU,
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

fn format_apply_result(
    target: PowerLimitTarget,
    result: Result<ApplyTargetResult, String>,
) -> String {
    match result {
        Ok(result) if result.is_successful => {
            let mut text = format!(
                "Applied {} W / {} W / {} W.\n",
                target.stapm_watts, target.fast_watts, target.slow_watts
            );
            if result.has_firmware_clamp || result.has_stapm_warning {
                text.push_str("Firmware reported a clamp or STAPM warning.");
            } else {
                text.push_str("Readback verified.");
            }
            text
        }
        Ok(result) => format!(
            "Apply failed.\n{}\nRestore attempted: {}\nRestore succeeded: {}",
            result
                .error
                .unwrap_or_else(|| "worker returned an unsuccessful result".to_owned()),
            result.restore_attempted,
            result.restored_previous_limits
        ),
        Err(error) => format!("Apply failed.\n{error}"),
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

unsafe fn apply_profile_to_presets(app: &mut GuiApp, profile: &ProfilePayload) {
    let minimum = profile.minimum_watts;
    let maximum = profile.maximum_watts;
    if minimum > maximum {
        return;
    }
    app.preset_watts = [
        12.clamp(minimum, maximum),
        25.clamp(minimum, maximum),
        45.clamp(minimum, maximum),
    ];
    if app.selected_target.stapm_watts < minimum || app.selected_target.stapm_watts > maximum {
        app.selected_target = PowerLimitTarget::uniform(app.preset_watts[0]);
    }
    if let Some(buttons) = app.preset_buttons {
        for (index, button) in buttons.into_iter().enumerate() {
            if button.is_null() {
                continue;
            }
            let text = wide(&format!("{} W", app.preset_watts[index]));
            SetWindowTextW(button, text.as_ptr());
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
    let mut data = NOTIFYICONDATAW::default();
    data.cbSize = size_of::<NOTIFYICONDATAW>() as u32;
    data.hWnd = hwnd;
    data.uID = TRAY_ICON_ID;
    data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    data.uCallbackMessage = WM_APP_TRAY;
    data.hIcon = LoadIconW(std::ptr::null_mut(), IDI_APPLICATION);
    write_wide(&mut data.szTip, APP_TITLE);
    Shell_NotifyIconW(NIM_ADD, &data);
}

unsafe fn remove_tray_icon(hwnd: HWND) {
    let mut data = NOTIFYICONDATAW::default();
    data.cbSize = size_of::<NOTIFYICONDATAW>() as u32;
    data.hWnd = hwnd;
    data.uID = TRAY_ICON_ID;
    Shell_NotifyIconW(NIM_DELETE, &data);
}

unsafe fn show_tray_menu(hwnd: HWND) {
    let menu: HMENU = CreatePopupMenu();
    if menu.is_null() {
        return;
    }

    let show_text = wide("Show");
    let exit_text = wide("Exit");
    AppendMenuW(menu, MF_STRING, MENU_SHOW, show_text.as_ptr());
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
                show_tray_menu(hwnd);
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
                    apply_profile_to_presets(app, profile);
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
        WM_COMMAND => {
            match wparam & 0xFFFF {
                MENU_SHOW => {
                    dispatch(app, hwnd, LifecycleEvent::TrayShowRequested);
                }
                MENU_EXIT => {
                    dispatch(app, hwnd, LifecycleEvent::TrayExitRequested);
                }
                PRESET_12 | PRESET_25 | PRESET_45 if app.write_enabled => {
                    let preset_index = match wparam & 0xFFFF {
                        PRESET_12 => 0,
                        PRESET_25 => 1,
                        PRESET_45 => 2,
                        _ => 0,
                    };
                    app.selected_target = PowerLimitTarget::uniform(app.preset_watts[preset_index]);
                }
                APPLY_TARGET if app.write_enabled && !app.apply_in_flight => {
                    app.apply_in_flight = true;
                    if !app.status_label.is_null() {
                        let text = wide(&format!(
                            "Applying {} W / {} W / {} W...",
                            app.selected_target.stapm_watts,
                            app.selected_target.fast_watts,
                            app.selected_target.slow_watts
                        ));
                        SetWindowTextW(app.status_label, text.as_ptr());
                    }
                    start_apply(hwnd as usize, app.worker_pipe.clone(), app.selected_target);
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
    let mut window_class = WNDCLASSEXW::default();
    window_class.cbSize = size_of::<WNDCLASSEXW>() as u32;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = Some(window_proc);
    window_class.hInstance = instance;
    window_class.hCursor = unsafe { LoadCursorW(std::ptr::null_mut(), IDC_ARROW) };
    window_class.hbrBackground = std::ptr::null_mut::<c_void>() as HBRUSH;
    window_class.lpszClassName = class_name.as_ptr();
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
        420
    } else {
        360
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
        (*app).status_label = create_status_label(hwnd, instance);
        if options.enable_write_controls {
            (*app).preset_buttons = Some(create_action_buttons(hwnd, instance));
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
