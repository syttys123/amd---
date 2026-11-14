#![windows_subsystem = "windows"]

use amd_mobile_power_gui::layout::{
    minimum_client_size, minimum_window_client_size, page_scroll, scroll_position, CommandLayout,
    ADVANCED_CLIENT_SIZE, ADVANCED_CONTENT_WIDTH, SIMPLE_CLIENT_SIZE,
};
use amd_mobile_power_gui::lifecycle::{
    LifecycleAction, LifecycleEvent, LifecycleState, Transition, WindowVisibility,
};
use amd_mobile_power_gui::state;
use amd_mobile_power_gui::unlock_dialog;
use amd_mobile_power_gui::worker::{
    ApplyTargetResult, CpuPayload, LimitsPayload, PlatformPayload, PowerLimitTarget,
    PowerLineState, PowerPolicySettings, PowerPolicyState, ProfilePayload, SnapshotPayload,
    TelemetryPayload, WorkerClient, DEFAULT_PIPE_NAME,
};
use std::mem::size_of;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[link(name = "dwmapi")]
extern "system" {
    fn DwmSetWindowAttribute(
        hwnd: HWND,
        attribute: u32,
        value: *const std::ffi::c_void,
        value_size: u32,
    ) -> i32;
}
use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, ERROR_ALREADY_EXISTS, HANDLE, HINSTANCE, HWND, LPARAM, LRESULT,
    POINT, RECT, WPARAM,
};
use windows_sys::Win32::Graphics::Gdi::{
    BeginPaint, BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, CreateFontW, CreatePen,
    CreateSolidBrush, DeleteDC, DeleteObject, DrawTextW, EndPaint, FillRect, GetMonitorInfoW,
    GetStockObject, InvalidateRect, MonitorFromWindow, RoundRect, ScreenToClient, SelectObject,
    RedrawWindow, SetBkColor, SetBkMode, SetTextColor, SetViewportOrgEx, UpdateWindow, BLACK_BRUSH,
    DT_CENTER, DT_END_ELLIPSIS, DT_LEFT, DT_NOPREFIX, DT_RIGHT, DT_SINGLELINE, DT_VCENTER, FW_BOLD,
    FW_NORMAL, HBRUSH, HGDIOBJ, MONITORINFO, MONITOR_DEFAULTTONEAREST, NULL_BRUSH, PAINTSTRUCT,
    PS_SOLID, RDW_ALLCHILDREN, RDW_ERASE, RDW_INVALIDATE, SRCCOPY, TRANSPARENT, WHITE_BRUSH,
};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::SystemServices::SS_LEFT;
use windows_sys::Win32::System::Threading::{
    CreateMutexW, OpenProcess, TerminateProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE,
    PROCESS_TERMINATE,
};
use windows_sys::Win32::UI::Accessibility::{HCF_HIGHCONTRASTON, HIGHCONTRASTW};
use windows_sys::Win32::UI::Controls::{
    SetScrollInfo, DRAWITEMSTRUCT, NMHDR, NMTTDISPINFOW, ODS_DISABLED, ODS_SELECTED, ODT_BUTTON,
    TOOLTIPS_CLASSW, TTF_IDISHWND, TTF_SUBCLASS, TTM_ADDTOOLW, TTM_NEWTOOLRECTW,
    TTM_SETMAXTIPWIDTH, TTN_GETDISPINFOW, TTS_ALWAYSTIP, TTTOOLINFOW, WM_MOUSELEAVE,
};
use windows_sys::Win32::UI::HiDpi::{
    AdjustWindowRectExForDpi, GetDpiForSystem, GetDpiForWindow, GetSystemMetricsForDpi,
    SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    EnableWindow, GetFocus, GetKeyState, IsWindowEnabled, SetFocus, TrackMouseEvent, TME_LEAVE,
    TRACKMOUSEEVENT, VK_SHIFT,
};
use windows_sys::Win32::UI::Shell::{
    DefSubclassProc, SetWindowSubclass, Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD,
    NIM_DELETE, NOTIFYICONDATAW,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CheckMenuItem, CreateIconFromResourceEx, CreatePopupMenu, CreateWindowExW,
    DefWindowProcW, DestroyIcon, DestroyMenu, DestroyWindow, DispatchMessageW, FindWindowW,
    GetClientRect, GetCursorPos, GetDlgCtrlID, GetDlgItem, GetMessageW, GetParent, GetScrollInfo,
    GetWindowLongPtrW, GetWindowRect, IsDialogMessageW, IsWindowVisible, LoadCursorW, LoadIconW,
    PostMessageW,
    PostQuitMessage, RegisterClassExW, SetCursor, SetForegroundWindow, SetWindowLongPtrW,
    SetWindowPos, SetWindowTextW, ShowWindow, SystemParametersInfoW, TrackPopupMenu,
    TranslateMessage, CS_HREDRAW, CS_VREDRAW, CW_USEDEFAULT, GWLP_USERDATA, HICON, HMENU,
    HWND_NOTOPMOST, HWND_TOPMOST, ICON_BIG, ICON_SMALL, IDC_ARROW, IDC_HAND, IDI_APPLICATION,
    LR_DEFAULTCOLOR, MF_CHECKED, MF_SEPARATOR, MF_STRING, MF_UNCHECKED, MINMAXINFO, MSG, SB_BOTTOM,
    SB_HORZ, SB_LEFT, SB_LINEDOWN, SB_LINELEFT, SB_LINERIGHT, SB_LINEUP, SB_PAGEDOWN, SB_PAGELEFT,
    SB_PAGERIGHT, SB_PAGEUP, SB_RIGHT, SB_THUMBPOSITION, SB_THUMBTRACK, SB_TOP, SB_VERT,
    SCROLLINFO, SIF_PAGE, SIF_POS, SIF_RANGE, SIF_TRACKPOS, SIZE_MAXIMIZED, SIZE_MINIMIZED,
    SIZE_RESTORED, SM_CXVSCROLL, SM_CYHSCROLL, SPI_GETHIGHCONTRAST, SWP_NOACTIVATE, SWP_NOMOVE,
    SWP_NOSIZE, SWP_NOZORDER, SWP_NOREDRAW, SW_HIDE, SW_MINIMIZE, SW_RESTORE, SW_SHOWNORMAL,
    TPM_RIGHTBUTTON,
    WM_APP, WM_CLOSE, WM_COMMAND, WM_CONTEXTMENU, WM_DESTROY, WM_DPICHANGED, WM_ENDSESSION,
    WM_ERASEBKGND, WM_GETICON, WM_GETMINMAXINFO, WM_HSCROLL, WM_LBUTTONUP, WM_MOUSEMOVE,
    WM_MOUSEWHEEL, WM_NOTIFY, WM_SETREDRAW,
    WM_QUERYENDSESSION, WM_RBUTTONUP, WM_SETCURSOR, WM_SETICON, WM_SETTINGCHANGE, WM_SHOWWINDOW,
    WM_SIZE, WM_SYSCOLORCHANGE, WM_SYSCOMMAND, WM_VSCROLL, WNDCLASSEXW, WS_CAPTION, WS_CHILD,
    WS_CLIPCHILDREN, WS_EX_APPWINDOW, WS_HSCROLL, WS_MINIMIZEBOX, WS_OVERLAPPED, WS_POPUP,
    WS_SYSMENU, WS_THICKFRAME, WS_VISIBLE, WS_VSCROLL,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    GetWindowTextLengthW, GetWindowTextW, SendMessageW, BM_SETCHECK, BS_OWNERDRAW, ES_CENTER,
    ES_NUMBER, SC_MINIMIZE, WM_CTLCOLOREDIT, WM_CTLCOLORSTATIC, WM_DRAWITEM, WM_PAINT, WS_TABSTOP,
};

const APP_TITLE: &str = "AMD Mobile Power";
const WINDOW_CLASS: &str = "AmdMobilePower.RustGui.Migration.v1";
const MUTEX_NAME: &str = "Local\\AmdMobilePower.RustGui.Migration.v1";
const TRAY_ICON_ID: u32 = 1;
const WM_APP_WAKE: u32 = WM_APP + 1;
const WM_APP_TRAY: u32 = WM_APP + 2;
const WM_APP_STATUS: u32 = WM_APP + 3;
const WM_APP_APPLY_RESULT: u32 = WM_APP + 4;
const WM_APP_POLICY_RESULT: u32 = WM_APP + 5;
const WM_APP_RESTART_WORKER: u32 = WM_APP + 6;
const WM_APP_FORCE_RESTART_WORKER: u32 = WM_APP + 7;
const WM_APP_FORCE_RESTART_READY: u32 = WM_APP + 8;
const MENU_SHOW: usize = 1;
const MENU_EXIT: usize = 2;
const MENU_SIMPLE_MODE: usize = 3;
const MENU_ADVANCED_MODE: usize = 4;
const MENU_TOPMOST: usize = 5;
const MENU_WRITE: usize = 6;
const PRESET_12: usize = 101;
const PRESET_25: usize = 102;
const PRESET_45: usize = 103;
const APPLY_TARGET: usize = 104;
const POLICY_SAVE: usize = 105;
const PRESET_SAVE: usize = 106;
const EXPORT_DIAGNOSTICS: usize = 107;
const SIMPLE_MODE: usize = 108;
const ADVANCED_MODE: usize = 109;
const TOPMOST_TOGGLE: usize = 110;
const WRITE_UNLOCK: usize = 111;
const PRESET_MENU_START: usize = 201;
const PRESET_EDIT_START: usize = 301;
const PRESET_LABEL: usize = 310;
const POLICY_BATTERY_LABEL: usize = 311;
const POLICY_BATTERY_EDIT: usize = 312;
const POLICY_AC_LABEL: usize = 313;
const POLICY_AC_EDIT: usize = 314;
const POLICY_ENABLED: usize = 315;
const SIMPLE_TARGET_EDIT: usize = 316;
const SIMPLE_APPLY: usize = 317;
const POLICY_BATTERY_ONLY: usize = 318;
const POWER_VALUE_LABEL: usize = 320;
const POWER_SOURCE_LABEL: usize = 321;
const TARGET_LABEL: usize = 322;
const SIMPLE_STATUS_LABEL: usize = 323;
const PRESET_EDIT_OPEN: usize = 324;
const METRIC_TITLE_START: usize = 330;
const METRIC_VALUE_START: usize = 340;
const METRIC_LIMIT_START: usize = 350;
const TITLE_LABEL: usize = 360;
const ADVANCED_DEVICE_LABEL: usize = 370;
const STATUS_HOLD: Duration = Duration::from_secs(5);
const COMMAND_BOTTOM: i32 = 216;

struct Palette {
    canvas: u32,
    surface: u32,
    surface_muted: u32,
    header: u32,
    border: u32,
    rule: u32,
    accent: u32,
    accent_soft: u32,
    accent_pressed: u32,
    on_accent: u32,
    focus_ring: u32,
    focus_ring_header: u32,
    text: u32,
    text_muted: u32,
    header_muted: u32,
    hero_button: u32,
    hero_hover: u32,
    surface_hover: u32,
    disabled_hero: u32,
    disabled_hero_text: u32,
    disabled_hero_border: u32,
    white: u32,
    external: u32,
    external_soft: u32,
    warning: u32,
    warning_soft: u32,
    error: u32,
    error_soft: u32,
    success: u32,
    success_soft: u32,
}

static ACTIVE_HIGH_CONTRAST: AtomicBool = AtomicBool::new(false);

static DEFAULT_PALETTE: Palette = Palette {
    canvas: rgb(247, 248, 250),
    surface: rgb(255, 255, 255),
    surface_muted: rgb(247, 248, 250),
    header: rgb(25, 27, 31),
    border: rgb(203, 208, 215),
    rule: rgb(225, 228, 233),
    accent: rgb(16, 119, 104),
    accent_soft: rgb(228, 245, 240),
    accent_pressed: rgb(10, 92, 80),
    on_accent: rgb(255, 255, 255),
    focus_ring: rgb(16, 119, 104),
    focus_ring_header: rgb(255, 255, 255),
    text: rgb(30, 34, 40),
    text_muted: rgb(96, 104, 116),
    header_muted: rgb(179, 185, 195),
    hero_button: rgb(43, 47, 54),
    hero_hover: rgb(61, 67, 77),
    surface_hover: rgb(235, 239, 241),
    disabled_hero: rgb(34, 37, 43),
    disabled_hero_text: rgb(126, 134, 148),
    disabled_hero_border: rgb(62, 68, 78),
    white: rgb(255, 255, 255),
    external: rgb(36, 99, 235),
    external_soft: rgb(236, 242, 255),
    warning: rgb(156, 82, 7),
    warning_soft: rgb(255, 245, 228),
    error: rgb(185, 48, 42),
    error_soft: rgb(254, 237, 235),
    success: rgb(13, 117, 81),
    success_soft: rgb(231, 248, 241),
};

static HIGH_CONTRAST_PALETTE: Palette = Palette {
    canvas: rgb(0, 0, 0),
    surface: rgb(0, 0, 0),
    surface_muted: rgb(0, 0, 0),
    header: rgb(0, 0, 0),
    border: rgb(255, 255, 0),
    rule: rgb(255, 255, 0),
    accent: rgb(255, 255, 0),
    accent_soft: rgb(0, 0, 0),
    accent_pressed: rgb(255, 255, 0),
    on_accent: rgb(0, 0, 0),
    focus_ring: rgb(255, 255, 0),
    focus_ring_header: rgb(255, 255, 0),
    text: rgb(255, 255, 255),
    text_muted: rgb(255, 255, 255),
    header_muted: rgb(255, 255, 255),
    hero_button: rgb(0, 0, 0),
    hero_hover: rgb(0, 0, 0),
    surface_hover: rgb(0, 0, 0),
    disabled_hero: rgb(0, 0, 0),
    disabled_hero_text: rgb(255, 255, 255),
    disabled_hero_border: rgb(255, 255, 0),
    white: rgb(255, 255, 255),
    external: rgb(255, 255, 0),
    external_soft: rgb(0, 0, 0),
    warning: rgb(255, 255, 0),
    warning_soft: rgb(0, 0, 0),
    error: rgb(255, 120, 120),
    error_soft: rgb(0, 0, 0),
    success: rgb(0, 255, 128),
    success_soft: rgb(0, 0, 0),
};

fn palette() -> &'static Palette {
    if ACTIVE_HIGH_CONTRAST.load(Ordering::Relaxed) {
        &HIGH_CONTRAST_PALETTE
    } else {
        &DEFAULT_PALETTE
    }
}

fn system_high_contrast() -> bool {
    let mut info = HIGHCONTRASTW {
        cbSize: size_of::<HIGHCONTRASTW>() as u32,
        ..Default::default()
    };
    let result = unsafe {
        SystemParametersInfoW(
            SPI_GETHIGHCONTRAST,
            info.cbSize,
            &mut info as *mut HIGHCONTRASTW as *mut std::ffi::c_void,
            0,
        )
    };
    result != 0 && info.dwFlags & HCF_HIGHCONTRASTON != 0
}

fn refresh_high_contrast(force: bool) {
    ACTIVE_HIGH_CONTRAST.store(force || system_high_contrast(), Ordering::Relaxed);
}

fn surface_brush() -> HBRUSH {
    unsafe {
        GetStockObject(if ACTIVE_HIGH_CONTRAST.load(Ordering::Relaxed) {
            BLACK_BRUSH
        } else {
            WHITE_BRUSH
        }) as HBRUSH
    }
}

/// All layout constants in this file are expressed in 96-DPI logical units.
const BASE_DPI: i32 = 96;

fn dpi_percent(dpi: u32) -> i32 {
    let dpi = if dpi == 0 { BASE_DPI as u32 } else { dpi } as i32;
    (dpi * 100 + BASE_DPI / 2) / BASE_DPI
}

/// Logical units to device pixels.
fn scaled(value: i32, percent: i32) -> i32 {
    let product = value * percent;
    if product >= 0 {
        (product + 50) / 100
    } else {
        (product - 50) / 100
    }
}

/// Device pixels to logical units.
fn unscaled(value: i32, percent: i32) -> i32 {
    let percent = percent.max(1);
    (value * 100 + percent / 2) / percent
}

fn content_height(mode: state::UiMode) -> i32 {
    match mode {
        state::UiMode::Simple => SIMPLE_CLIENT_SIZE.1,
        state::UiMode::Advanced => ADVANCED_CLIENT_SIZE.1,
    }
}

const APP_WINDOW_STYLE: u32 = WS_OVERLAPPED
    | WS_CAPTION
    | WS_SYSMENU
    | WS_MINIMIZEBOX
    | WS_THICKFRAME
    | WS_CLIPCHILDREN
    | WS_VSCROLL
    | WS_HSCROLL;

const fn rgb(red: u8, green: u8, blue: u8) -> u32 {
    red as u32 | ((green as u32) << 8) | ((blue as u32) << 16)
}

#[derive(Clone, Copy)]
struct PolicyControls {
    enabled: HWND,
    battery_target: HWND,
    ac_target: HWND,
    battery_only: HWND,
}

#[derive(Clone, Copy)]
struct UiDiagnostics {
    mode: state::UiMode,
    top_most: bool,
    policy_enabled: bool,
    battery_only: bool,
    high_contrast: bool,
    taskbar_icon_available: bool,
    tray_icon_id: u32,
    dpi_percent: i32,
    dpi_fixture_percent: Option<i32>,
}

#[derive(Clone, Copy)]
struct HeaderControls {
    simple: HWND,
    advanced: HWND,
    topmost: HWND,
    write: HWND,
}

#[derive(Clone, Copy)]
struct SimpleViewControls {
    power_value: HWND,
    power_source: HWND,
    target_label: HWND,
    target_edit: HWND,
    apply: HWND,
    metric_titles: [HWND; 4],
    metric_values: [HWND; 4],
    metric_limits: [HWND; 4],
    status: HWND,
    advanced_device: HWND,
}

struct UiFonts {
    display: HGDIOBJ,
    number_display: HGDIOBJ,
    metric: HGDIOBJ,
    number_metric: HGDIOBJ,
    body: HGDIOBJ,
    caption: HGDIOBJ,
    title: HGDIOBJ,
    icon: HGDIOBJ,
}

impl Drop for UiFonts {
    fn drop(&mut self) {
        for font in [
            self.display,
            self.number_display,
            self.metric,
            self.number_metric,
            self.body,
            self.caption,
            self.title,
            self.icon,
        ] {
            if !font.is_null() {
                unsafe {
                    DeleteObject(font);
                }
            }
        }
    }
}

struct GuiApp {
    state: LifecycleState,
    _mutex: HANDLE,
    status_label: HWND,
    stop_monitor: Arc<AtomicBool>,
    monitor_thread: Option<JoinHandle<()>>,
    monitor_heartbeat: Arc<AtomicU64>,
    force_restart_in_flight: Arc<AtomicBool>,
    worker_child: Option<Child>,
    worker_executable: Option<PathBuf>,
    worker_pipe: String,
    write_enabled: bool,
    selected_target: PowerLimitTarget,
    apply_in_flight: bool,
    policy_in_flight: bool,
    preset_watts: [i32; 3],
    preset_buttons: Option<[HWND; 3]>,
    preset_edits: Option<[HWND; 3]>,
    selected_preset: Option<usize>,
    target_edit_dirty: bool,
    policy_controls: Option<PolicyControls>,
    profile: Option<ProfilePayload>,
    saved_policy: Option<PowerPolicySettings>,
    policy_profile_applied: bool,
    latest_snapshot: Option<SnapshotPayload>,
    latest_policy: Option<PowerPolicyState>,
    /// Whether the saved auto-policy was already handed to the current
    /// worker. Reset whenever the worker process is replaced.
    policy_synced: bool,
    worker_error: Option<String>,
    status_hold_until: Instant,
    view_mode: state::UiMode,
    top_most: bool,
    policy_enabled: bool,
    battery_only: bool,
    ui_fixture: Option<UiFixture>,
    focused_control: Option<usize>,
    hovered_control: Option<usize>,
    tooltip: HWND,
    tooltip_texts: Vec<Vec<u16>>,
    tooltip_dynamic: Vec<u16>,
    icon_large: HICON,
    icon_small: HICON,
    header_controls: Option<HeaderControls>,
    simple_controls: Option<SimpleViewControls>,
    fonts: Option<UiFonts>,
    dpi_percent: i32,
    scroll_offset: i32,
    scroll_offset_x: i32,
    layout_in_progress: bool,
    layout_pending: bool,
    redraw_suspended: bool,
    max_target_watts: Option<i32>,
}

impl GuiApp {
    fn new(mutex: HANDLE, mode_override: Option<state::UiMode>) -> Self {
        let max_target_watts = state::load_max_target_watts();
        let preset_watts = clamp_to_ceiling(state::load_presets(), max_target_watts);
        let mut window_preferences = state::load_window_preferences();
        if let Some(mode) = mode_override {
            window_preferences.mode = mode;
            let _ = state::save_window_preferences(window_preferences);
        }
        Self {
            state: LifecycleState::default(),
            _mutex: mutex,
            status_label: std::ptr::null_mut(),
            stop_monitor: Arc::new(AtomicBool::new(false)),
            monitor_thread: None,
            monitor_heartbeat: Arc::new(AtomicU64::new(0)),
            force_restart_in_flight: Arc::new(AtomicBool::new(false)),
            worker_child: None,
            worker_executable: None,
            worker_pipe: String::new(),
            write_enabled: false,
            selected_target: PowerLimitTarget::uniform(preset_watts[0]),
            apply_in_flight: false,
            policy_in_flight: false,
            preset_watts,
            preset_buttons: None,
            preset_edits: None,
            selected_preset: Some(0),
            target_edit_dirty: false,
            policy_controls: None,
            profile: None,
            saved_policy: None,
            policy_profile_applied: false,
            latest_snapshot: None,
            latest_policy: None,
            policy_synced: false,
            worker_error: None,
            status_hold_until: Instant::now(),
            view_mode: window_preferences.mode,
            top_most: window_preferences.top_most,
            policy_enabled: false,
            battery_only: false,
            ui_fixture: None,
            focused_control: None,
            hovered_control: None,
            tooltip: std::ptr::null_mut(),
            tooltip_texts: Vec::new(),
            tooltip_dynamic: Vec::new(),
            icon_large: std::ptr::null_mut(),
            icon_small: std::ptr::null_mut(),
            header_controls: None,
            simple_controls: None,
            fonts: None,
            dpi_percent: 100,
            scroll_offset: 0,
            scroll_offset_x: 0,
            layout_in_progress: false,
            layout_pending: false,
            redraw_suspended: false,
            max_target_watts,
        }
    }
}

struct StatusUpdate {
    text: String,
    profile: Option<ProfilePayload>,
    snapshot: Option<SnapshotPayload>,
    policy: Option<PowerPolicyState>,
    worker_error: Option<String>,
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
        if !self.icon_large.is_null() {
            unsafe {
                DestroyIcon(self.icon_large);
            }
        }
        if !self.icon_small.is_null() && self.icon_small != self.icon_large {
            unsafe {
                DestroyIcon(self.icon_small);
            }
        }
    }
}

#[derive(Debug)]
struct Options {
    start_hidden: bool,
    pipe_name: String,
    worker_executable: Option<PathBuf>,
    enable_write_controls: bool,
    ui_fixture: Option<UiFixture>,
    mode_override: Option<state::UiMode>,
    max_target_watts: Option<i32>,
    uniform_target_watts: Option<i32>,
    dpi_fixture: Option<i32>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            start_hidden: false,
            pipe_name: DEFAULT_PIPE_NAME.to_owned(),
            worker_executable: None,
            enable_write_controls: false,
            ui_fixture: None,
            mode_override: None,
            max_target_watts: None,
            uniform_target_watts: None,
            dpi_fixture: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum UiFixture {
    WorkerOffline,
    FirmwareClamp,
    UnsupportedPlatform,
    LongError,
    HighContrast,
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn write_wide(buffer: &mut [u16], value: &str) {
    let encoded: Vec<u16> = value.encode_utf16().take(buffer.len() - 1).collect();
    buffer[..encoded.len()].copy_from_slice(&encoded);
    buffer[encoded.len()] = 0;
}

const APP_ICON_BYTES: &[u8] = include_bytes!("../../../assets/amd-mobile-power.ico");

unsafe fn create_icon_for_size(desired_size: i32) -> HICON {
    if APP_ICON_BYTES.len() < 6 {
        return std::ptr::null_mut();
    }
    let image_count = u16::from_le_bytes([APP_ICON_BYTES[4], APP_ICON_BYTES[5]]) as usize;
    let mut best: Option<(i32, usize, usize)> = None;
    for index in 0..image_count {
        let entry_offset = 6 + index * 16;
        if entry_offset + 16 > APP_ICON_BYTES.len() {
            break;
        }
        let width = if APP_ICON_BYTES[entry_offset] == 0 {
            256
        } else {
            i32::from(APP_ICON_BYTES[entry_offset])
        };
        let height = if APP_ICON_BYTES[entry_offset + 1] == 0 {
            256
        } else {
            i32::from(APP_ICON_BYTES[entry_offset + 1])
        };
        let byte_count = u32::from_le_bytes(
            APP_ICON_BYTES[entry_offset + 8..entry_offset + 12]
                .try_into()
                .unwrap_or([0; 4]),
        ) as usize;
        let image_offset = u32::from_le_bytes(
            APP_ICON_BYTES[entry_offset + 12..entry_offset + 16]
                .try_into()
                .unwrap_or([0; 4]),
        ) as usize;
        if byte_count == 0 || image_offset + byte_count > APP_ICON_BYTES.len() {
            continue;
        }
        let score = (width - desired_size).abs() + (height - desired_size).abs();
        if best
            .map(|(best_score, _, _)| score < best_score)
            .unwrap_or(true)
        {
            best = Some((score, image_offset, byte_count));
        }
    }

    let Some((_, image_offset, byte_count)) = best else {
        return std::ptr::null_mut();
    };
    CreateIconFromResourceEx(
        APP_ICON_BYTES[image_offset..].as_ptr(),
        byte_count as u32,
        1,
        0x0003_0000,
        desired_size,
        desired_size,
        LR_DEFAULTCOLOR,
    )
}

unsafe fn create_ui_font(face_name: &str, pixel_height: i32, weight: i32) -> HGDIOBJ {
    let face = wide(face_name);
    CreateFontW(
        -pixel_height,
        0,
        0,
        0,
        weight,
        0,
        0,
        0,
        1,
        0,
        0,
        5,
        0,
        face.as_ptr(),
    )
}

/// `percent` is the DPI scale in hundredths: 100 = 96 DPI, 125 = 120 DPI.
///
/// Custom painting selects these into a DC whose mapping mode already scales
/// logical units, so that path uses percent 100. Native child controls have
/// MM_TEXT DCs and need device-sized fonts, so they use the window DPI.
unsafe fn create_ui_fonts(percent: i32) -> UiFonts {
    UiFonts {
        display: create_ui_font("Microsoft YaHei UI", scaled(31, percent), FW_BOLD as i32),
        number_display: create_ui_font("Consolas", scaled(36, percent), FW_BOLD as i32),
        metric: create_ui_font("Microsoft YaHei UI", scaled(16, percent), FW_BOLD as i32),
        number_metric: create_ui_font("Consolas", scaled(18, percent), FW_BOLD as i32),
        body: create_ui_font("Microsoft YaHei UI", scaled(14, percent), FW_NORMAL as i32),
        caption: create_ui_font("Microsoft YaHei UI", scaled(12, percent), FW_NORMAL as i32),
        title: create_ui_font("Microsoft YaHei UI", scaled(18, percent), FW_BOLD as i32),
        icon: create_ui_font("Segoe MDL2 Assets", scaled(16, percent), FW_NORMAL as i32),
    }
}

/// Drawing code keeps using 96-DPI logical coordinates. These primitives turn
/// them into device pixels at the window DPI, which keeps glyphs rendered by
/// GDI at their real size instead of being stretched with the whole window.
static PAINT_PERCENT: AtomicI32 = AtomicI32::new(100);
static DPI_FIXTURE_PERCENT: AtomicI32 = AtomicI32::new(0);

fn paint_percent() -> i32 {
    PAINT_PERCENT.load(Ordering::Relaxed).max(1)
}

fn effective_dpi_percent(hwnd: HWND) -> i32 {
    let fixture = DPI_FIXTURE_PERCENT.load(Ordering::Relaxed);
    if fixture > 0 {
        fixture
    } else {
        unsafe { dpi_percent(window_dpi(hwnd)) }
    }
}

fn scale_rect(rect: &RECT) -> RECT {
    let percent = paint_percent();
    RECT {
        left: scaled(rect.left, percent),
        top: scaled(rect.top, percent),
        right: scaled(rect.right, percent),
        bottom: scaled(rect.bottom, percent),
    }
}

unsafe fn fill_rect_color(hdc: windows_sys::Win32::Graphics::Gdi::HDC, rect: &RECT, color: u32) {
    let device_rect = scale_rect(rect);
    let brush = CreateSolidBrush(color);
    if !brush.is_null() {
        FillRect(hdc, &device_rect, brush);
        DeleteObject(brush);
    }
}

unsafe fn paint_surface(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    rect: RECT,
    radius: i32,
    fill: u32,
    border: u32,
) {
    let rect = scale_rect(&rect);
    let radius = scaled(radius, paint_percent());
    let brush = CreateSolidBrush(fill);
    let pen = CreatePen(PS_SOLID, scaled(1, paint_percent()).max(1), border);
    if brush.is_null() || pen.is_null() {
        if !brush.is_null() {
            DeleteObject(brush);
        }
        if !pen.is_null() {
            DeleteObject(pen);
        }
        return;
    }
    let old_brush = SelectObject(hdc, brush);
    let old_pen = SelectObject(hdc, pen);
    RoundRect(
        hdc,
        rect.left,
        rect.top,
        rect.right,
        rect.bottom,
        radius * 2,
        radius * 2,
    );
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(brush);
    DeleteObject(pen);
}

unsafe fn draw_text_in(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    text: &str,
    font: HGDIOBJ,
    color: u32,
    rect: RECT,
    align: u32,
) {
    if text.is_empty() {
        return;
    }
    let value = wide(text);
    let old_font = if !font.is_null() {
        SelectObject(hdc, font)
    } else {
        std::ptr::null_mut()
    };
    SetBkMode(hdc, TRANSPARENT as i32);
    SetTextColor(hdc, color);
    let mut draw_rect = scale_rect(&rect);
    DrawTextW(
        hdc,
        value.as_ptr(),
        -1,
        &mut draw_rect,
        align | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX | DT_END_ELLIPSIS,
    );
    if !old_font.is_null() {
        SelectObject(hdc, old_font);
    }
}

unsafe fn draw_rule(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
) {
    fill_rect_color(
        hdc,
        &RECT {
            left,
            top,
            right,
            bottom,
        },
        palette().rule,
    );
}

fn command_layout(app: &GuiApp, width: i32) -> CommandLayout {
    CommandLayout::new(width.max(minimum_client_size(app.view_mode).0))
}

unsafe fn text_width(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    text: &str,
    font: HGDIOBJ,
) -> i32 {
    let old_font = SelectObject(hdc, font);
    let mut bounds = RECT::default();
    DrawTextW(
        hdc,
        wide(text).as_ptr(),
        -1,
        &mut bounds,
        windows_sys::Win32::Graphics::Gdi::DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX,
    );
    SelectObject(hdc, old_font);
    unscaled(bounds.right - bounds.left, paint_percent())
}

fn short_processor_name(snapshot: Option<&SnapshotPayload>) -> String {
    snapshot
        .map(|snapshot| {
            snapshot
                .platform
                .cpu
                .processor_name
                .trim_start_matches("AMD ")
                .split(" w/")
                .next()
                .unwrap_or(&snapshot.platform.cpu.processor_name)
                .to_owned()
        })
        .unwrap_or_else(|| "正在检测处理器".to_owned())
}

fn platform_subtitle(app: &GuiApp) -> String {
    let Some(snapshot) = app.latest_snapshot.as_ref() else {
        if app.worker_error.is_some() {
            return "worker 状态异常 · 写入控制不可用".to_owned();
        }
        return "正在连接硬件 worker".to_owned();
    };
    let family = snapshot
        .platform
        .cpu
        .ryzen_adj_family_name
        .as_deref()
        .unwrap_or("AMD 移动平台");
    format!("{} · {}", short_processor_name(Some(snapshot)), family)
}

fn current_power(app: &GuiApp) -> String {
    app.latest_snapshot
        .as_ref()
        .map(|snapshot| format_watts(snapshot.telemetry.stapm_value_watts))
        .unwrap_or_else(|| "等待数据".to_owned())
}

fn current_power_limit(app: &GuiApp) -> String {
    app.latest_snapshot
        .as_ref()
        .map(|snapshot| format_watts(snapshot.telemetry.stapm_limit_watts))
        .unwrap_or_else(|| "--".to_owned())
}

fn current_power_label(app: &GuiApp) -> &'static str {
    match app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.telemetry.power_line.as_str())
    {
        Some("battery") => "电池",
        Some("ac") => "外接电源",
        _ => "电源",
    }
}

unsafe fn visible_status(app: &GuiApp) -> (String, String, u32, u32) {
    if app.apply_in_flight || app.policy_in_flight {
        return (
            "处理中".to_owned(),
            "正在应用，等待硬件回读".to_owned(),
            palette().warning_soft,
            palette().warning,
        );
    }
    if Instant::now() < app.status_hold_until && !app.status_label.is_null() {
        let message = get_control_text(app.status_label);
        if let Some(first_line) = message.lines().find(|line| !line.trim().is_empty()) {
            let is_error = first_line.contains("失败")
                || first_line.contains("异常")
                || first_line.contains("错误");
            return if is_error {
                (
                    "需要处理".to_owned(),
                    first_line.to_owned(),
                    palette().error_soft,
                    palette().error,
                )
            } else {
                (
                    "状态更新".to_owned(),
                    first_line.to_owned(),
                    palette().success_soft,
                    palette().success,
                )
            };
        }
    }
    if let Some(error) = app.worker_error.as_ref() {
        return (
            "连接异常".to_owned(),
            error.lines().next().unwrap_or("worker 连接中断").to_owned(),
            palette().error_soft,
            palette().error,
        );
    }
    if app.latest_snapshot.is_none() {
        return (
            "连接中".to_owned(),
            "正在连接硬件 worker".to_owned(),
            palette().external_soft,
            palette().external,
        );
    }
    if let Some(snapshot) = app.latest_snapshot.as_ref() {
        if !snapshot.platform.is_supported {
            return (
                "平台不支持".to_owned(),
                snapshot
                    .platform
                    .unsupported_reason
                    .clone()
                    .unwrap_or_else(|| "当前平台只允许只读监测".to_owned()),
                palette().error_soft,
                palette().error,
            );
        }
    }
    let clamp = app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.telemetry.has_firmware_clamp)
        .unwrap_or(false);
    if clamp {
        return (
            "固件限制".to_owned(),
            "目标已写入，但固件回读低于请求值".to_owned(),
            palette().warning_soft,
            palette().warning,
        );
    }
    if !app.write_enabled {
        return (
            "只读".to_owned(),
            "可监测实时功耗，写入控制未解锁".to_owned(),
            palette().surface_muted,
            palette().text_muted,
        );
    }
    let telemetry = &app.latest_snapshot.as_ref().unwrap().telemetry;
    (
        "写入已解锁".to_owned(),
        format!(
            "Fast / Slow {} / {} W",
            telemetry
                .fast_limit_watts
                .map(|value| format!("{value:.0}"))
                .unwrap_or_else(|| "--".to_owned()),
            telemetry
                .slow_limit_watts
                .map(|value| format!("{value:.0}"))
                .unwrap_or_else(|| "--".to_owned()),
        ),
        palette().success_soft,
        palette().success,
    )
}

unsafe fn paint_status_banner(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    app: &GuiApp,
    fonts: &UiFonts,
    rect: RECT,
) {
    fill_rect_color(hdc, &rect, palette().surface_muted);
    draw_rule(hdc, rect.left, rect.top, rect.right, rect.top + 1);
    let (label, message, chip_fill, chip_text) = visible_status(app);
    let chip = RECT {
        left: rect.left + 4,
        top: rect.top + 7,
        right: rect.left + 96,
        bottom: rect.bottom - 7,
    };
    paint_surface(hdc, chip, 6, chip_fill, chip_fill);
    draw_text_in(
        hdc,
        &label,
        fonts.caption,
        chip_text,
        RECT {
            left: chip.left + 8,
            top: chip.top,
            right: chip.right - 8,
            bottom: chip.bottom,
        },
        DT_CENTER,
    );
    draw_text_in(
        hdc,
        &message,
        fonts.body,
        palette().text,
        RECT {
            left: chip.right + 12,
            top: rect.top + 6,
            right: rect.right - 52,
            bottom: rect.bottom - 6,
        },
        DT_LEFT,
    );
}

unsafe fn paint_header(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    app: &GuiApp,
    fonts: &UiFonts,
    width: i32,
) {
    fill_rect_color(
        hdc,
        &RECT {
            left: 0,
            top: 0,
            right: width,
            bottom: 56,
        },
        palette().header,
    );
    fill_rect_color(
        hdc,
        &RECT {
            left: 0,
            top: 54,
            right: width,
            bottom: 56,
        },
        palette().hero_button,
    );
    draw_text_in(
        hdc,
        "AMD Mobile Power",
        fonts.title,
        palette().white,
        RECT {
            left: 24,
            top: 6,
            right: width - 212,
            bottom: 31,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        &platform_subtitle(app),
        fonts.caption,
        palette().header_muted,
        RECT {
            left: 24,
            top: 29,
            right: width - 212,
            bottom: 50,
        },
        DT_LEFT,
    );
}

unsafe fn paint_target_region(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    app: &GuiApp,
    fonts: &UiFonts,
    layout: CommandLayout,
) {
    let label_left = layout.target_left;
    let edit_left = layout.target_left;
    let edit_width = 76;
    let (minimum, maximum) = profile_limits(app);
    draw_text_in(
        hdc,
        "目标功耗",
        fonts.body,
        palette().header_muted,
        RECT {
            left: label_left,
            top: 72,
            right: label_left + 100,
            bottom: 94,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        &format!("{minimum}-{maximum} W"),
        fonts.caption,
        palette().header_muted,
        RECT {
            left: label_left + layout.target_width - 96,
            top: 73,
            right: label_left + layout.target_width,
            bottom: 94,
        },
        DT_RIGHT,
    );
    paint_surface(
        hdc,
        RECT {
            left: edit_left,
            top: 98,
            right: edit_left + edit_width,
            bottom: 140,
        },
        6,
        palette().surface,
        if app.focused_control == Some(SIMPLE_TARGET_EDIT) {
            palette().accent
        } else {
            palette().border
        },
    );
    draw_text_in(
        hdc,
        "W",
        fonts.body,
        palette().header_muted,
        RECT {
            left: edit_left + edit_width + 7,
            top: 100,
            right: edit_left + edit_width + 23,
            bottom: 138,
        },
        DT_CENTER,
    );
}

unsafe fn paint_live_region(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    app: &GuiApp,
    fonts: &UiFonts,
    left: i32,
    top: i32,
) {
    draw_text_in(
        hdc,
        "实时功耗",
        fonts.caption,
        palette().header_muted,
        RECT {
            left,
            top,
            right: left + 130,
            bottom: top + 20,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        current_power(app).trim_end_matches(" W"),
        fonts.number_display,
        palette().white,
        RECT {
            left,
            top: top + 20,
            right: left + 210,
            bottom: top + 68,
        },
        DT_LEFT,
    );
    if app.latest_snapshot.is_some() {
        let number = current_power(app);
        let number_width = text_width(hdc, number.trim_end_matches(" W"), fonts.number_display);
        draw_text_in(
            hdc,
            "W",
            fonts.body,
            palette().header_muted,
            RECT {
                left: left + number_width + 8,
                top: top + 34,
                right: left + number_width + 36,
                bottom: top + 62,
            },
            DT_LEFT,
        );
    }
    draw_text_in(
        hdc,
        &format!("STAPM 上限 {}", current_power_limit(app)),
        fonts.caption,
        palette().header_muted,
        RECT {
            left,
            top: top + 70,
            right: left + 174,
            bottom: top + 90,
        },
        DT_LEFT,
    );

    let is_battery = app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.telemetry.power_line == "battery")
        .unwrap_or(false);
    let chip_fill = if is_battery {
        palette().warning_soft
    } else {
        palette().external_soft
    };
    let chip_text = if is_battery {
        palette().warning
    } else {
        palette().external
    };
    let chip = RECT {
        left: left + 174,
        top: top + 68,
        right: left + 254,
        bottom: top + 92,
    };
    paint_surface(hdc, chip, 6, chip_fill, chip_fill);
    draw_text_in(
        hdc,
        current_power_label(app),
        fonts.caption,
        chip_text,
        RECT {
            left: chip.left + 6,
            top: chip.top,
            right: chip.right - 6,
            bottom: chip.bottom,
        },
        DT_CENTER,
    );
}

unsafe fn paint_metric(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    fonts: &UiFonts,
    bounds: RECT,
    title: &str,
    value: &str,
    limit: &str,
) {
    let left = bounds.left;
    let top = bounds.top;
    let width = bounds.right - bounds.left;
    draw_text_in(
        hdc,
        title,
        fonts.caption,
        palette().text_muted,
        RECT {
            left,
            top,
            right: left + width,
            bottom: top + 20,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        value,
        fonts.number_metric,
        palette().text,
        RECT {
            left,
            top: top + 21,
            right: left + width,
            bottom: top + 47,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        limit,
        fonts.caption,
        palette().text_muted,
        RECT {
            left,
            top: top + 46,
            right: left + width,
            bottom: top + 66,
        },
        DT_LEFT,
    );
}

unsafe fn paint_simple_window(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    app: &GuiApp,
    fonts: &UiFonts,
    width: i32,
) {
    let layout = command_layout(app, width);
    fill_rect_color(
        hdc,
        &RECT {
            left: 0,
            top: 56,
            right: width,
            bottom: COMMAND_BOTTOM,
        },
        palette().header,
    );
    fill_rect_color(
        hdc,
        &RECT {
            left: 0,
            top: COMMAND_BOTTOM,
            right: width,
            bottom: 308,
        },
        palette().surface_muted,
    );
    paint_live_region(hdc, app, fonts, 24, 72);
    paint_target_region(hdc, app, fonts, layout);

    draw_text_in(
        hdc,
        "快捷预设",
        fonts.caption,
        palette().header_muted,
        RECT {
            left: 24,
            top: 174,
            right: 88,
            bottom: 208,
        },
        DT_LEFT,
    );

    let (titles, values, limits) = snapshot_metric_text(app);
    let column_width = (width - 48) / 4;
    for index in 0..4 {
        let left = 24 + index as i32 * column_width;
        if index > 0 {
            draw_rule(hdc, left - 10, 234, left - 9, 290);
        }
        paint_metric(
            hdc,
            fonts,
            RECT {
                left,
                top: 230,
                right: left + column_width - 16,
                bottom: 296,
            },
            titles[index],
            &values[index],
            &limits[index],
        );
    }

    paint_status_banner(
        hdc,
        app,
        fonts,
        RECT {
            left: 24,
            top: 312,
            right: width - 24,
            bottom: 352,
        },
    );
}

fn snapshot_metric_text(app: &GuiApp) -> ([&'static str; 4], [String; 4], [String; 4]) {
    let titles = ["STAPM", "PPT Fast", "PPT Slow", "CPU 温度"];
    let Some(snapshot) = app.latest_snapshot.as_ref() else {
        return (
            titles,
            [
                "--".to_owned(),
                "--".to_owned(),
                "--".to_owned(),
                "--".to_owned(),
            ],
            [
                "上限 --".to_owned(),
                "上限 --".to_owned(),
                "上限 --".to_owned(),
                "上限 --".to_owned(),
            ],
        );
    };
    let telemetry = &snapshot.telemetry;
    (
        titles,
        [
            format_watts(telemetry.stapm_value_watts),
            format_watts(telemetry.fast_value_watts),
            format_watts(telemetry.slow_value_watts),
            format_celsius(telemetry.tctl_value_celsius),
        ],
        [
            format!("上限 {}", format_watts(telemetry.stapm_limit_watts)),
            format!("上限 {}", format_watts(telemetry.fast_limit_watts)),
            format!("上限 {}", format_watts(telemetry.slow_limit_watts)),
            format!("上限 {}", format_celsius(telemetry.tctl_limit_celsius)),
        ],
    )
}

unsafe fn paint_advanced_window(
    hdc: windows_sys::Win32::Graphics::Gdi::HDC,
    app: &GuiApp,
    fonts: &UiFonts,
    width: i32,
) {
    let layout = command_layout(app, width);
    let side_left = width - 296;
    let side_right = width - 24;
    fill_rect_color(
        hdc,
        &RECT {
            left: 0,
            top: 56,
            right: width,
            bottom: COMMAND_BOTTOM,
        },
        palette().header,
    );
    fill_rect_color(
        hdc,
        &RECT {
            left: 0,
            top: COMMAND_BOTTOM,
            right: width,
            bottom: COMMAND_BOTTOM + 1,
        },
        palette().rule,
    );
    paint_surface(
        hdc,
        RECT {
            left: 0,
            top: COMMAND_BOTTOM,
            right: width,
            bottom: 616,
        },
        0,
        palette().surface,
        palette().surface,
    );

    paint_live_region(hdc, app, fonts, 24, 72);
    paint_target_region(hdc, app, fonts, layout);

    draw_text_in(
        hdc,
        "快捷预设",
        fonts.caption,
        palette().header_muted,
        RECT {
            left: 24,
            top: 174,
            right: 88,
            bottom: 208,
        },
        DT_LEFT,
    );

    draw_rule(hdc, side_left - 20, 240, side_left - 19, 598);

    draw_text_in(
        hdc,
        "预设编辑",
        fonts.metric,
        palette().text,
        RECT {
            left: 24,
            top: 236,
            right: 180,
            bottom: 262,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        "",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: 24,
            top: 270,
            right: side_left - 24,
            bottom: 290,
        },
        DT_LEFT,
    );
    for (index, left) in [24, 128, 232].into_iter().enumerate() {
        draw_text_in(
            hdc,
            &format!("预设 {}", index + 1),
            fonts.caption,
            palette().text_muted,
            RECT {
                left,
                top: 270,
                right: left + 96,
                bottom: 290,
            },
            DT_LEFT,
        );
        paint_surface(
            hdc,
            RECT {
                left,
                top: 294,
                right: left + 72,
                bottom: 328,
            },
            6,
            palette().surface,
            if app.focused_control == Some(PRESET_EDIT_START + index) {
                palette().accent
            } else {
                palette().border
            },
        );
        draw_text_in(
            hdc,
            "W",
            fonts.caption,
            palette().text_muted,
            RECT {
                left: left + 78,
                top: 296,
                right: left + 96,
                bottom: 326,
            },
            DT_LEFT,
        );
    }
    draw_rule(hdc, 24, 348, side_left - 40, 349);
    draw_text_in(
        hdc,
        "自动电源策略",
        fonts.metric,
        palette().text,
        RECT {
            left: 24,
            top: 364,
            right: 220,
            bottom: 390,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        "供电策略",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: 24,
            top: 454,
            right: 84,
            bottom: 480,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        "电池目标",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: 24,
            top: 402,
            right: 84,
            bottom: 430,
        },
        DT_LEFT,
    );
    paint_surface(
        hdc,
        RECT {
            left: 90,
            top: 398,
            right: 168,
            bottom: 432,
        },
        6,
        palette().surface,
        if app.focused_control == Some(POLICY_BATTERY_EDIT) {
            palette().accent
        } else {
            palette().border
        },
    );
    draw_text_in(
        hdc,
        "外接目标",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: 216,
            top: 402,
            right: 276,
            bottom: 430,
        },
        DT_LEFT,
    );
    paint_surface(
        hdc,
        RECT {
            left: 282,
            top: 398,
            right: 360,
            bottom: 432,
        },
        6,
        palette().surface,
        if app.focused_control == Some(POLICY_AC_EDIT) {
            palette().accent
        } else {
            palette().border
        },
    );
    draw_text_in(
        hdc,
        "W",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: 176,
            top: 400,
            right: 196,
            bottom: 430,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        "W",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: 368,
            top: 400,
            right: 388,
            bottom: 430,
        },
        DT_LEFT,
    );

    draw_text_in(
        hdc,
        "设备与运行",
        fonts.metric,
        palette().text,
        RECT {
            left: side_left,
            top: 236,
            right: side_right,
            bottom: 262,
        },
        DT_LEFT,
    );
    let cpu = short_processor_name(app.latest_snapshot.as_ref());
    let family = app
        .latest_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.platform.cpu.ryzen_adj_family_name.as_deref())
        .unwrap_or("--");
    let smu = app
        .latest_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.platform.cpu.smu_bios_version.as_deref())
        .unwrap_or("--");
    let pm = app
        .latest_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.platform.cpu.pm_table_version.as_deref())
        .unwrap_or("--");
    let profile = app
        .latest_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.platform.matched_profile.as_ref())
        .map(|profile| {
            profile
                .display_name
                .replace(" development profile", "")
                .replace(" profile", "")
        })
        .unwrap_or_else(|| "未匹配".to_owned());
    let smu_pm = format!("{smu} / {pm}");
    draw_text_in(
        hdc,
        "处理器",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: side_left,
            top: 274,
            right: side_right,
            bottom: 294,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        &cpu,
        fonts.body,
        palette().text,
        RECT {
            left: side_left,
            top: 296,
            right: side_right,
            bottom: 322,
        },
        DT_LEFT,
    );
    for (top, label, value) in [
        (332, "平台家族", family),
        (364, "SMU / PM", smu_pm.as_str()),
    ] {
        draw_text_in(
            hdc,
            label,
            fonts.caption,
            palette().text_muted,
            RECT {
                left: side_left,
                top,
                right: side_left + 76,
                bottom: top + 22,
            },
            DT_LEFT,
        );
        draw_text_in(
            hdc,
            value,
            fonts.body,
            palette().text,
            RECT {
                left: side_left + 82,
                top: top - 2,
                right: side_right,
                bottom: top + 24,
            },
            DT_LEFT,
        );
    }
    draw_text_in(
        hdc,
        "匹配配置",
        fonts.caption,
        palette().text_muted,
        RECT {
            left: side_left,
            top: 394,
            right: side_right,
            bottom: 414,
        },
        DT_LEFT,
    );
    draw_text_in(
        hdc,
        &profile,
        fonts.body,
        palette().text,
        RECT {
            left: side_left,
            top: 416,
            right: side_right,
            bottom: 440,
        },
        DT_LEFT,
    );

    let supported = app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.platform.is_supported)
        .unwrap_or(false);
    let chip_fill = if supported {
        palette().success_soft
    } else {
        palette().error_soft
    };
    let chip_color = if supported {
        palette().success
    } else {
        palette().error
    };
    let chip = RECT {
        left: side_left,
        top: 450,
        right: side_left + 92,
        bottom: 476,
    };
    paint_surface(hdc, chip, 6, chip_fill, chip_fill);
    draw_text_in(
        hdc,
        if supported {
            "平台可写"
        } else {
            "平台不可写"
        },
        fonts.caption,
        chip_color,
        RECT {
            left: chip.left + 8,
            top: chip.top,
            right: chip.right - 8,
            bottom: chip.bottom,
        },
        DT_CENTER,
    );
    draw_text_in(
        hdc,
        &format!(
            "可写：{}",
            format_writable_fields(
                app.latest_snapshot
                    .as_ref()
                    .map(|snapshot| snapshot.platform.limits.supports_stapm)
                    .unwrap_or(false),
                app.latest_snapshot
                    .as_ref()
                    .map(|snapshot| snapshot.platform.limits.supports_fast)
                    .unwrap_or(false),
                app.latest_snapshot
                    .as_ref()
                    .map(|snapshot| snapshot.platform.limits.supports_slow)
                    .unwrap_or(false)
            )
        ),
        fonts.caption,
        palette().text_muted,
        RECT {
            left: side_left,
            top: 478,
            right: side_right,
            bottom: 500,
        },
        DT_LEFT,
    );

    draw_rule(hdc, side_left, 508, side_right, 509);
    draw_text_in(
        hdc,
        "运行状态",
        fonts.metric,
        palette().text,
        RECT {
            left: side_left,
            top: 518,
            right: side_right,
            bottom: 542,
        },
        DT_LEFT,
    );
    let worker_line = match (app.ui_fixture, app.worker_error.as_ref()) {
        (Some(_), _) => "测试状态 · 未连接硬件".to_owned(),
        (None, Some(_)) => "worker 异常 · 查看诊断详情".to_owned(),
        (None, None) if app.latest_snapshot.is_some() => "worker 已连接 · 1 秒刷新".to_owned(),
        (None, None) => "worker 连接中".to_owned(),
    };
    draw_text_in(
        hdc,
        &worker_line,
        fonts.caption,
        palette().text_muted,
        RECT {
            left: side_left,
            top: 546,
            right: side_right,
            bottom: 568,
        },
        DT_LEFT,
    );
    let policy = match app.saved_policy {
        Some(settings) => {
            let status = if settings.enabled {
                "已启用"
            } else {
                "已停用"
            };
            if settings.battery_enabled && settings.ac_enabled {
                format!(
                    "策略 {} · 电池/外接 · {} W / {} W",
                    status, settings.battery_target.stapm_watts, settings.ac_target.stapm_watts
                )
            } else if settings.battery_enabled {
                format!(
                    "策略 {} · 仅电池 · {} W",
                    status, settings.battery_target.stapm_watts
                )
            } else if settings.ac_enabled {
                format!(
                    "策略 {} · 仅外接 · {} W",
                    status, settings.ac_target.stapm_watts
                )
            } else {
                format!("策略 {status} · 未选择供电路径")
            }
        }
        None => "自动策略 · 尚未配置".to_owned(),
    };
    draw_text_in(
        hdc,
        &policy,
        fonts.caption,
        palette().text_muted,
        RECT {
            left: side_left,
            top: 570,
            right: side_right,
            bottom: 592,
        },
        DT_LEFT,
    );
    let supported = app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.platform.is_supported)
        .unwrap_or(false);
    let clamp = app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.telemetry.has_firmware_clamp)
        .unwrap_or(false);
    draw_text_in(
        hdc,
        if app.latest_snapshot.is_none() {
            "无实时回读；查看底部状态"
        } else if !supported {
            "只读监测；平台未通过写入门禁"
        } else if clamp {
            "限流：STAPM 被固件压低"
        } else {
            "回读正常，每秒刷新一次"
        },
        fonts.caption,
        palette().text_muted,
        RECT {
            left: side_left,
            top: 594,
            right: side_right,
            bottom: 616,
        },
        DT_LEFT,
    );
    draw_rule(hdc, 24, 504, side_left - 40, 505);
    draw_text_in(
        hdc,
        "实时回读",
        fonts.metric,
        palette().text,
        RECT {
            left: 24,
            top: 520,
            right: 140,
            bottom: 546,
        },
        DT_LEFT,
    );
    let (titles, values, limits) = snapshot_metric_text(app);
    for index in 0..3 {
        let column_width = (side_left - 64) / 3;
        let left = 24 + index as i32 * column_width;
        if index > 0 {
            draw_rule(hdc, left - 10, 556, left - 9, 604);
        }
        paint_metric(
            hdc,
            fonts,
            RECT {
                left,
                top: 550,
                right: left + column_width - 16,
                bottom: 616,
            },
            titles[index],
            &values[index],
            &limits[index],
        );
    }
    paint_status_banner(
        hdc,
        app,
        fonts,
        RECT {
            left: 24,
            top: 628,
            right: width - 24,
            bottom: 668,
        },
    );
}

unsafe fn paint_window(app: &GuiApp, hwnd: HWND) {
    let mut paint = PAINTSTRUCT::default();
    let hdc = BeginPaint(hwnd, &mut paint);
    if hdc.is_null() {
        return;
    }
    let mut client = RECT::default();
    GetClientRect(hwnd, &mut client);
    let percent = effective_dpi_percent(hwnd);
    PAINT_PERCENT.store(percent, Ordering::Relaxed);
    let physical_width = client.right.max(1);
    let physical_height = client.bottom.max(1);
    // The paint code below keeps working in 96-DPI logical units; the drawing
    // helpers convert those to device pixels.
    let width = unscaled(physical_width, percent).max(1);
    let height = unscaled(physical_height, percent).max(1);
    let memory_dc = CreateCompatibleDC(hdc);
    let bitmap = CreateCompatibleBitmap(hdc, physical_width, physical_height);
    let old_bitmap = if !memory_dc.is_null() && !bitmap.is_null() {
        SelectObject(memory_dc, bitmap)
    } else {
        std::ptr::null_mut()
    };
    let target_dc = if memory_dc.is_null() { hdc } else { memory_dc };

    fill_rect_color(
        target_dc,
        &RECT {
            left: 0,
            top: 0,
            right: width,
            bottom: height,
        },
        palette().canvas,
    );
    if let Some(fonts) = app.fonts.as_ref() {
        SetViewportOrgEx(
            target_dc,
            -scaled(app.scroll_offset_x, percent),
            -scaled(app.scroll_offset, percent),
            std::ptr::null_mut(),
        );
        paint_header(target_dc, app, fonts, width);
        match app.view_mode {
            state::UiMode::Simple => paint_simple_window(target_dc, app, fonts, width),
            state::UiMode::Advanced => paint_advanced_window(target_dc, app, fonts, width),
        }
        SetViewportOrgEx(target_dc, 0, 0, std::ptr::null_mut());
    }

    if !memory_dc.is_null() && !bitmap.is_null() {
        BitBlt(
            hdc,
            0,
            0,
            physical_width,
            physical_height,
            memory_dc,
            0,
            0,
            SRCCOPY,
        );
        SelectObject(memory_dc, old_bitmap);
        DeleteObject(bitmap);
        DeleteDC(memory_dc);
    }
    EndPaint(hwnd, &paint);
}

unsafe fn draw_owner_button(app: &GuiApp, draw: &DRAWITEMSTRUCT) {
    if draw.CtlType != ODT_BUTTON {
        return;
    }
    let id = draw.CtlID as usize;
    let disabled = draw.itemState & ODS_DISABLED != 0;
    let pressed = draw.itemState & ODS_SELECTED != 0;
    let hovered = app.hovered_control == Some(draw.CtlID as usize);
    // Match paint_window: keep drawing in 96-DPI logical units and let the
    // drawing helpers scale to the real DPI.
    let percent = effective_dpi_percent(draw.hwndItem);
    PAINT_PERCENT.store(percent, Ordering::Relaxed);
    let rc = RECT {
        left: unscaled(draw.rcItem.left, percent),
        top: unscaled(draw.rcItem.top, percent),
        right: unscaled(draw.rcItem.right, percent),
        bottom: unscaled(draw.rcItem.bottom, percent),
    };
    let selected = match id {
        SIMPLE_MODE => app.view_mode == state::UiMode::Simple,
        ADVANCED_MODE => app.view_mode == state::UiMode::Advanced,
        TOPMOST_TOGGLE => app.top_most,
        WRITE_UNLOCK => app.write_enabled,
        PRESET_12 => app.selected_preset == Some(0),
        PRESET_25 => app.selected_preset == Some(1),
        PRESET_45 => app.selected_preset == Some(2),
        POLICY_ENABLED => app.policy_enabled,
        POLICY_BATTERY_ONLY => app.battery_only,
        _ => false,
    };
    let primary = matches!(id, SIMPLE_APPLY | APPLY_TARGET);
    let header_button = matches!(
        id,
        SIMPLE_MODE | ADVANCED_MODE | TOPMOST_TOGGLE | WRITE_UNLOCK
    );
    let hero_button = matches!(id, PRESET_12 | PRESET_25 | PRESET_45 | PRESET_EDIT_OPEN);
    let (fill, text_color, border) = if disabled && hero_button {
        (
            palette().disabled_hero,
            palette().disabled_hero_text,
            palette().disabled_hero_border,
        )
    } else if disabled {
        (
            palette().surface_muted,
            palette().text_muted,
            palette().border,
        )
    } else if header_button {
        if selected {
            (palette().white, palette().header, palette().white)
        } else {
            (
                if hovered {
                    palette().hero_hover
                } else {
                    palette().header
                },
                palette().header_muted,
                palette().header,
            )
        }
    } else if hero_button {
        if selected {
            (palette().white, palette().header, palette().white)
        } else if pressed {
            (
                palette().accent_soft,
                palette().accent,
                palette().accent_soft,
            )
        } else {
            (
                if hovered {
                    palette().hero_hover
                } else {
                    palette().hero_button
                },
                palette().white,
                palette().hero_button,
            )
        }
    } else if primary {
        (
            if pressed || hovered {
                palette().accent_pressed
            } else {
                palette().accent
            },
            palette().on_accent,
            palette().accent,
        )
    } else if selected || pressed {
        (palette().accent_soft, palette().accent, palette().accent)
    } else {
        (
            if hovered {
                palette().surface_hover
            } else {
                palette().surface
            },
            palette().text,
            palette().rule,
        )
    };
    fill_rect_color(
        draw.hDC,
        &rc,
        if hero_button || header_button || primary {
            palette().header
        } else {
            palette().surface
        },
    );
    paint_surface(draw.hDC, rc, 6, fill, border);
    if app.focused_control == Some(id) {
        paint_surface(
            draw.hDC,
            RECT {
                left: rc.left + 2,
                top: rc.top + 2,
                right: rc.right - 2,
                bottom: rc.bottom - 2,
            },
            5,
            fill,
            if primary {
                palette().on_accent
            } else if (header_button || hero_button) && selected {
                palette().header
            } else if header_button || hero_button {
                palette().focus_ring_header
            } else {
                palette().focus_ring
            },
        );
    }

    let icon = match id {
        TOPMOST_TOGGLE => Some("\u{e718}"),
        WRITE_UNLOCK => Some(if app.write_enabled {
            "\u{e785}"
        } else {
            "\u{e72e}"
        }),
        PRESET_EDIT_OPEN => Some("\u{e70f}"),
        EXPORT_DIAGNOSTICS => Some("\u{e896}"),
        _ => None,
    };
    let mut text_rect = rc;
    if id == POLICY_ENABLED {
        let center_y = (rc.top + rc.bottom) / 2;
        paint_surface(
            draw.hDC,
            RECT {
                left: 8,
                top: center_y - 7,
                right: 36,
                bottom: center_y + 7,
            },
            7,
            if selected {
                palette().accent
            } else {
                palette().text_muted
            },
            if selected {
                palette().accent
            } else {
                palette().text_muted
            },
        );
        let knob_left = if selected { 24 } else { 10 };
        paint_surface(
            draw.hDC,
            RECT {
                left: knob_left,
                top: center_y - 5,
                right: knob_left + 10,
                bottom: center_y + 5,
            },
            5,
            palette().on_accent,
            palette().on_accent,
        );
        text_rect.left = 38;
    } else if id == POLICY_BATTERY_ONLY {
        let center_y = (rc.top + rc.bottom) / 2;
        paint_surface(
            draw.hDC,
            RECT {
                left: 10,
                top: center_y - 7,
                right: 24,
                bottom: center_y + 7,
            },
            2,
            if selected { palette().accent } else { fill },
            if selected {
                palette().accent
            } else {
                palette().text_muted
            },
        );
        if selected {
            if let Some(fonts) = app.fonts.as_ref() {
                draw_text_in(
                    draw.hDC,
                    "\u{e73e}",
                    fonts.icon,
                    palette().on_accent,
                    RECT {
                        left: 9,
                        top: center_y - 9,
                        right: 25,
                        bottom: center_y + 9,
                    },
                    DT_CENTER,
                );
            }
        }
        text_rect.left = 28;
    }
    let text = if let Some(icon) = icon {
        icon.to_owned()
    } else if id == SIMPLE_APPLY && app.apply_in_flight {
        "应用中".to_owned()
    } else if id == POLICY_ENABLED {
        if app.policy_enabled {
            "已启用"
        } else {
            "已停用"
        }
        .to_owned()
    } else {
        get_control_text(draw.hwndItem)
    };
    let value = wide(&text);
    let font = app
        .fonts
        .as_ref()
        .map(|fonts| {
            if icon.is_some() {
                fonts.icon
            } else {
                fonts.body
            }
        })
        .unwrap_or(std::ptr::null_mut());
    let old_font = if !font.is_null() {
        SelectObject(draw.hDC, font)
    } else {
        std::ptr::null_mut()
    };
    SetBkMode(draw.hDC, TRANSPARENT as i32);
    SetTextColor(draw.hDC, text_color);
    let mut rect = scale_rect(&text_rect);
    DrawTextW(
        draw.hDC,
        value.as_ptr(),
        -1,
        &mut rect,
        DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX,
    );
    if !old_font.is_null() {
        SelectObject(draw.hDC, old_font);
    }
}

fn static_text_color(control_id: i32) -> u32 {
    let control_id = control_id as usize;
    match control_id {
        TITLE_LABEL => palette().white,
        POWER_VALUE_LABEL => palette().accent,
        POWER_SOURCE_LABEL | TARGET_LABEL | SIMPLE_STATUS_LABEL => palette().text_muted,
        id if (METRIC_VALUE_START..METRIC_VALUE_START + 4).contains(&id) => palette().text,
        id if (METRIC_TITLE_START..METRIC_TITLE_START + 4).contains(&id)
            || (METRIC_LIMIT_START..METRIC_LIMIT_START + 4).contains(&id) =>
        {
            palette().text_muted
        }
        _ => palette().text,
    }
}

fn format_power_line_raw(value: &str) -> &'static str {
    match value {
        "ac" => "外接电源",
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

fn format_writable_fields(stapm: bool, fast: bool, slow: bool) -> String {
    let fields: Vec<&str> = [(stapm, "STAPM"), (fast, "Fast"), (slow, "Slow")]
        .into_iter()
        .filter_map(|(supported, name)| supported.then_some(name))
        .collect();
    if fields.is_empty() {
        "无".to_owned()
    } else {
        fields.join(" / ")
    }
}

fn format_watts(value: Option<f64>) -> String {
    match value {
        Some(value) => format!("{value:.2} W"),
        None => "--".to_owned(),
    }
}

fn format_celsius(value: Option<f64>) -> String {
    match value {
        Some(value) => format!("{value:.1} °C"),
        None => "--".to_owned(),
    }
}

fn format_power_line(value: Option<PowerLineState>) -> &'static str {
    match value {
        Some(PowerLineState::Ac) => "外接电源",
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
    let scope = if settings.battery_enabled && settings.ac_enabled {
        format!(
            "电池 {} W / 外接 {} W",
            settings.battery_target.stapm_watts, settings.ac_target.stapm_watts
        )
    } else if settings.battery_enabled {
        format!(
            "仅电池 {} W（外接不控制）",
            settings.battery_target.stapm_watts
        )
    } else if settings.ac_enabled {
        format!("仅外接 {} W（电池不控制）", settings.ac_target.stapm_watts)
    } else {
        "未选择供电路径".to_owned()
    };
    format!("自动策略：{}（{}）\n{}{}", status, scope, last, error)
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
            "支持写入：{}\n",
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
        format_writable_fields(
            limits.supports_stapm,
            limits.supports_fast,
            limits.supports_slow
        ),
        support,
        format_flag(telemetry.has_firmware_clamp),
        telemetry.updated_at.as_deref().unwrap_or("未知")
    );
    format!("{status}\n{}", format_policy_state(policy))
}

fn format_snapshot_simple(snapshot: &SnapshotPayload, policy: Option<&PowerPolicyState>) -> String {
    let telemetry = &snapshot.telemetry;
    format!(
        concat!(
            "已连接 worker · {}\n",
            "{}\n",
            "\n",
            "STAPM / Fast / Slow 上限\n",
            "{} / {} / {}\n",
            "\n",
            "目标功耗：{}    CPU：{}\n",
            "{}"
        ),
        format_power_line_raw(&telemetry.power_line),
        snapshot.platform.cpu.processor_name,
        format_watts(telemetry.stapm_limit_watts),
        format_watts(telemetry.fast_limit_watts),
        format_watts(telemetry.slow_limit_watts),
        format_watts(telemetry.target_watts),
        format_celsius(telemetry.tctl_value_celsius),
        format_policy_state(policy)
    )
}

fn package_version_from_build_info() -> Option<String> {
    let executable = std::env::current_exe().ok()?;
    let path = executable.parent()?.join("BUILD-INFO.txt");
    let contents = std::fs::read_to_string(path).ok()?;
    contents.lines().find_map(|line| {
        line.strip_prefix("Version=")
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
    })
}

fn diagnostics_document(
    snapshot: &SnapshotPayload,
    policy: Option<&PowerPolicyState>,
    write_controls_enabled: bool,
    package_version: Option<&str>,
    captured_at_unix_ms: u128,
    ui_state: UiDiagnostics,
) -> serde_json::Value {
    serde_json::json!({
        "schemaVersion": 1,
        "product": "AMD Mobile Power native preview",
        "guiVersion": env!("CARGO_PKG_VERSION"),
        "packageVersion": package_version,
        "capturedAtUnixMs": captured_at_unix_ms,
        "writeControlsEnabled": write_controls_enabled,
        "ui": {
            "mode": ui_state.mode,
            "topMost": ui_state.top_most,
            "policyEnabled": ui_state.policy_enabled,
            "batteryOnly": ui_state.battery_only,
            "highContrast": ui_state.high_contrast,
            "taskbarIconAvailable": ui_state.taskbar_icon_available,
            "trayIconId": ui_state.tray_icon_id,
            "dpiPercent": ui_state.dpi_percent,
            "dpiFixturePercent": ui_state.dpi_fixture_percent
        },
        "powerPolicy": policy,
        "snapshot": snapshot,
        "privacy": {
            "containsLocalPaths": false,
            "containsProcessIds": false,
            "containsAccountNames": false,
            "containsSerialNumbers": false,
            "containsLogs": false,
            "uploaded": false
        }
    })
}

fn export_diagnostics(app: &GuiApp) -> Result<PathBuf, String> {
    let snapshot = app
        .latest_snapshot
        .as_ref()
        .ok_or_else(|| "尚未收到可导出的 worker 遥测。".to_owned())?;
    let local_app_data =
        std::env::var_os("LOCALAPPDATA").ok_or_else(|| "LOCALAPPDATA 不可用。".to_owned())?;
    let directory = PathBuf::from(local_app_data)
        .join("AmdMobilePower")
        .join("diagnostics");
    std::fs::create_dir_all(&directory)
        .map_err(|error| format!("无法创建 {}：{error}", directory.display()))?;
    let captured_at_unix_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("系统时间不可用：{error}"))?
        .as_millis();
    let package_version = package_version_from_build_info();
    let dpi_fixture = DPI_FIXTURE_PERCENT.load(Ordering::Relaxed);
    let dpi_fixture_percent = (dpi_fixture > 0).then_some(dpi_fixture);
    let document = diagnostics_document(
        snapshot,
        app.latest_policy.as_ref(),
        app.write_enabled,
        package_version.as_deref(),
        captured_at_unix_ms,
        UiDiagnostics {
            mode: app.view_mode,
            top_most: app.top_most,
            policy_enabled: app.policy_enabled,
            battery_only: app.battery_only,
            high_contrast: ACTIVE_HIGH_CONTRAST.load(Ordering::Relaxed),
            taskbar_icon_available: !app.icon_large.is_null(),
            tray_icon_id: TRAY_ICON_ID,
            dpi_percent: app.dpi_percent,
            dpi_fixture_percent,
        },
    );
    let contents = serde_json::to_vec_pretty(&document)
        .map_err(|error| format!("无法序列化诊断报告：{error}"))?;
    let path = directory.join(format!("native-gui-diagnostics-{captured_at_unix_ms}.json"));
    std::fs::write(&path, contents)
        .map_err(|error| format!("无法写入 {}：{error}", path.display()))?;
    Ok(path)
}

fn parse_options() -> Result<Options, String> {
    parse_arguments(std::env::args().skip(1))
}

// The supported argument set is mirrored in native/gui-cli-contract.json so
// promotion scripts and release gates cannot drift away from the parser.
fn parse_arguments<I>(arguments: I) -> Result<Options, String>
where
    I: IntoIterator<Item = String>,
{
    let mut options = Options::default();
    let mut arguments = arguments.into_iter();
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--tray" => options.start_hidden = true,
            "--simple-mode" => options.mode_override = Some(state::UiMode::Simple),
            "--advanced-mode" => options.mode_override = Some(state::UiMode::Advanced),
            "--max-target-watts" => {
                let value = arguments
                    .next()
                    .ok_or_else(|| "--max-target-watts requires a value".to_owned())?;
                options.max_target_watts =
                    Some(parse_watts_argument("--max-target-watts", &value)?);
            }
            "--uniform-target-watts" => {
                let value = arguments
                    .next()
                    .ok_or_else(|| "--uniform-target-watts requires a value".to_owned())?;
                options.uniform_target_watts =
                    Some(parse_watts_argument("--uniform-target-watts", &value)?);
            }
            "--dpi-fixture" => {
                let value = arguments
                    .next()
                    .ok_or_else(|| "--dpi-fixture requires a value".to_owned())?;
                options.dpi_fixture = Some(parse_dpi_fixture(&value)?);
            }
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
            "--ui-fixture" => {
                let value = arguments
                    .next()
                    .ok_or_else(|| "--ui-fixture requires a value".to_owned())?;
                options.ui_fixture = Some(parse_ui_fixture(&value)?);
            }
            value => return Err(format!("unknown argument: {value}")),
        }
    }
    if let (Some(uniform), Some(ceiling)) = (options.uniform_target_watts, options.max_target_watts)
    {
        if uniform > ceiling {
            return Err(format!(
                "--uniform-target-watts {uniform} exceeds --max-target-watts {ceiling}"
            ));
        }
    }
    Ok(options)
}

fn parse_watts_argument(name: &str, value: &str) -> Result<i32, String> {
    let watts = value
        .parse::<i32>()
        .map_err(|_| format!("{name} needs a number, got {value}"))?;
    if !(1..=250).contains(&watts) {
        return Err(format!("{name} out of range: {watts}"));
    }
    Ok(watts)
}

fn parse_dpi_fixture(value: &str) -> Result<i32, String> {
    match value.parse::<i32>() {
        Ok(percent) if matches!(percent, 100 | 125 | 150 | 200) => Ok(percent),
        _ => Err(format!(
            "--dpi-fixture only supports 100, 125, 150, or 200, got {value}"
        )),
    }
}

fn uniform_power_policy(watts: i32) -> PowerPolicySettings {
    PowerPolicySettings {
        enabled: true,
        battery_enabled: true,
        ac_enabled: true,
        battery_target: PowerLimitTarget::uniform(watts),
        ac_target: PowerLimitTarget::uniform(watts),
    }
}

fn parse_ui_fixture(value: &str) -> Result<UiFixture, String> {
    match value {
        "worker-offline" => Ok(UiFixture::WorkerOffline),
        "firmware-clamp" => Ok(UiFixture::FirmwareClamp),
        "unsupported-platform" => Ok(UiFixture::UnsupportedPlatform),
        "long-error" => Ok(UiFixture::LongError),
        "high-contrast" => Ok(UiFixture::HighContrast),
        _ => Err(format!(
            "unknown UI fixture: {value}; expected worker-offline, firmware-clamp, unsupported-platform, long-error, or high-contrast"
        )),
    }
}

fn fixture_worker_error(fixture: UiFixture) -> Option<String> {
    match fixture {
        UiFixture::WorkerOffline => Some(
            "worker 离线：请重启应用或检查 worker。\n\
             无法打开命名管道。\n\
             错误：系统找不到指定的文件。"
                .to_owned(),
        ),
        UiFixture::LongError => Some(
            "应用失败：关闭其他 RyzenAdj 后重启 Windows。\n\
             RyzenAdj 返回 MP1 SMU 对象不可用。\n\
             STAPM、PPT Fast、PPT Slow 均未确认写入。\n\
             恢复路径已经停止，因为硬件所有权仍可能被旧版后台任务占用。\n\
             这不是固件钳制，也不是目标值超出范围。"
                .to_owned(),
        ),
        UiFixture::FirmwareClamp | UiFixture::UnsupportedPlatform | UiFixture::HighContrast => None,
    }
}

fn fixture_snapshot(fixture: UiFixture) -> Option<SnapshotPayload> {
    match fixture {
        UiFixture::FirmwareClamp => Some(SnapshotPayload {
            platform: fixture_platform(
                "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics",
                Some(10),
                Some("Hawk Point"),
                Some("hawk-point-8845hs"),
                true,
                None,
                LimitsPayload {
                    supports_stapm: true,
                    supports_fast: true,
                    supports_slow: true,
                    supports_any: true,
                },
            ),
            telemetry: TelemetryPayload {
                target_watts: Some(12.0),
                stapm_value_watts: Some(10.02),
                fast_value_watts: Some(12.0),
                slow_value_watts: Some(12.0),
                stapm_limit_watts: Some(10.0),
                fast_limit_watts: Some(12.0),
                slow_limit_watts: Some(12.0),
                tctl_value_celsius: Some(61.4),
                tctl_limit_celsius: Some(95.0),
                power_line: "battery".to_owned(),
                updated_at: Some("2026-11-11T07:45:00Z".to_owned()),
                has_firmware_clamp: true,
            },
        }),
        UiFixture::UnsupportedPlatform => Some(SnapshotPayload {
            platform: fixture_platform(
                "AMD Ryzen 7 7840U w/ Radeon 780M Graphics",
                Some(10),
                Some("Phoenix"),
                None,
                false,
                Some("未验证平台：仅允许只读监测。"),
                LimitsPayload {
                    supports_stapm: true,
                    supports_fast: false,
                    supports_slow: false,
                    supports_any: true,
                },
            ),
            telemetry: TelemetryPayload {
                target_watts: None,
                stapm_value_watts: Some(8.3),
                fast_value_watts: None,
                slow_value_watts: None,
                stapm_limit_watts: Some(15.0),
                fast_limit_watts: None,
                slow_limit_watts: None,
                tctl_value_celsius: Some(57.2),
                tctl_limit_celsius: Some(95.0),
                power_line: "battery".to_owned(),
                updated_at: Some("2026-11-11T07:45:00Z".to_owned()),
                has_firmware_clamp: false,
            },
        }),
        UiFixture::HighContrast => Some(SnapshotPayload {
            platform: fixture_platform(
                "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics",
                Some(10),
                Some("Hawk Point"),
                Some("hawk-point-8845hs"),
                true,
                None,
                LimitsPayload {
                    supports_stapm: true,
                    supports_fast: true,
                    supports_slow: true,
                    supports_any: true,
                },
            ),
            telemetry: TelemetryPayload {
                target_watts: Some(12.0),
                stapm_value_watts: Some(12.0),
                fast_value_watts: Some(12.0),
                slow_value_watts: Some(12.0),
                stapm_limit_watts: Some(12.0),
                fast_limit_watts: Some(12.0),
                slow_limit_watts: Some(12.0),
                tctl_value_celsius: Some(61.4),
                tctl_limit_celsius: Some(95.0),
                power_line: "battery".to_owned(),
                updated_at: Some("2026-11-11T07:45:00Z".to_owned()),
                has_firmware_clamp: false,
            },
        }),
        UiFixture::WorkerOffline | UiFixture::LongError => None,
    }
}

fn fixture_platform(
    processor_name: &str,
    family: Option<i32>,
    family_name: Option<&str>,
    profile_id: Option<&str>,
    is_supported: bool,
    unsupported_reason: Option<&str>,
    limits: LimitsPayload,
) -> PlatformPayload {
    PlatformPayload {
        cpu: CpuPayload {
            processor_name: processor_name.to_owned(),
            vendor: "AuthenticAMD".to_owned(),
            ryzen_adj_family: family,
            ryzen_adj_family_name: family_name.map(str::to_owned),
            smu_bios_version: Some("15".to_owned()),
            pm_table_version: Some("4c0009".to_owned()),
        },
        limits,
        matched_profile: profile_id.map(|id| ProfilePayload {
            id: id.to_owned(),
            display_name: format!("{id} profile"),
            minimum_watts: 5,
            maximum_watts: 60,
            default_watts: 25,
            is_verified: is_supported,
        }),
        is_supported,
        unsupported_reason: unsupported_reason.map(str::to_owned),
    }
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
    // The privileged worker decides at launch whether it accepts writes and
    // whether it runs the auto-policy ticker, so the persisted unlock state
    // must reach it exactly like the launch flag does.
    if options.enable_write_controls || state::load_write_unlocked() {
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

/// Backoff for worker restarts: 5 s, 10 s, 20 s, 40 s, then 60 s.
fn restart_delay(consecutive_failures: u32) -> Duration {
    let seconds = 5u64 << consecutive_failures.min(4);
    Duration::from_secs(seconds.min(60))
}

/// Restart a worker that exited unexpectedly. Returns true when a new process
/// was spawned. A worker that is still alive (or was started outside this GUI)
/// is left alone so two hardware owners can never race.
fn try_restart_worker(app: &mut GuiApp) -> bool {
    if app.ui_fixture.is_some() || app.worker_pipe.is_empty() {
        return false;
    }

    if let Some(child) = app.worker_child.as_mut() {
        match child.try_wait() {
            Ok(None) => return false,
            Ok(Some(_)) | Err(_) => app.worker_child = None,
        }
    } else {
        // No child handle: the worker may have been started by another
        // launcher. Only spawn when the pipe is genuinely gone.
        let client = WorkerClient::new(app.worker_pipe.clone());
        if client.health().is_ok() {
            return false;
        }
    }

    let Some(executable) = app.worker_executable.clone() else {
        return false;
    };
    let mut command = Command::new(&executable);
    command
        .arg("--pipe-name")
        .arg(&app.worker_pipe)
        .arg("--enable-hardware");
    if app.write_enabled {
        command.arg("--enable-write-controls");
    }
    match command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .creation_flags(0x08000000)
        .spawn()
    {
        Ok(child) => {
            app.worker_child = Some(child);
            app.policy_synced = false;
            true
        }
        Err(_) => false,
    }
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
    heartbeat: Arc<AtomicU64>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let hwnd = hwnd_address as HWND;
        let client = WorkerClient::new(pipe_name);
        let mut consecutive_failures: u32 = 0;
        let mut next_restart = Instant::now();
        while !stop.load(Ordering::SeqCst) {
            let policy = client.get_power_policy().ok();
            let update = match client.snapshot() {
                Ok(snapshot) => {
                    consecutive_failures = 0;
                    next_restart = Instant::now();
                    let profile = snapshot.platform.matched_profile.clone();
                    StatusUpdate {
                        text: format_snapshot(&snapshot, policy.as_ref()),
                        profile,
                        snapshot: Some(snapshot),
                        policy,
                        worker_error: None,
                    }
                }
                Err(error) => {
                    // Ask the UI thread to respawn a worker that exited. The
                    // check is rate-limited so a driver fault cannot cause a
                    // tight restart loop.
                    if Instant::now() >= next_restart {
                        unsafe {
                            PostMessageW(hwnd, WM_APP_RESTART_WORKER, 0, 0);
                        }
                        next_restart = Instant::now() + restart_delay(consecutive_failures);
                    }
                    consecutive_failures = consecutive_failures.saturating_add(1);
                    StatusUpdate {
                        text: format!("worker 不可用\n{error}"),
                        profile: None,
                        snapshot: None,
                        policy,
                        worker_error: Some(error),
                    }
                }
            };
            unsafe {
                post_status(hwnd, update);
            }
            heartbeat.fetch_add(1, Ordering::SeqCst);
            thread::sleep(Duration::from_secs(1));
        }
    })
}

/// A worker that stops answering blocks the monitor inside a pipe read, so the
/// monitor cannot report its own failure. The watchdog only watches the
/// heartbeat and asks the UI thread to replace the worker after 30 s without a
/// single completed sample.
fn watchdog_should_restart(stalled_checks: u32) -> bool {
    stalled_checks >= 6
}

/// Kill a hung worker without blocking the UI thread indefinitely. A worker
/// stuck inside a driver call can outlive TerminateProcess for a moment, so the
/// wait is bounded and the next watchdog cycle retries if it is still alive.
fn terminate_process_bounded(pid: u32, timeout: Duration) -> bool {
    unsafe {
        let handle = OpenProcess(PROCESS_TERMINATE | PROCESS_SYNCHRONIZE, 0, pid);
        if handle.is_null() {
            return false;
        }
        let terminated = TerminateProcess(handle, 1) != 0;
        let wait_ms = timeout.as_millis().min(u32::MAX as u128) as u32;
        let _ = WaitForSingleObject(handle, wait_ms);
        CloseHandle(handle);
        terminated
    }
}

fn start_worker_watchdog(
    hwnd_address: usize,
    heartbeat: Arc<AtomicU64>,
    stop: Arc<AtomicBool>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let hwnd = hwnd_address as HWND;
        let mut last = heartbeat.load(Ordering::SeqCst);
        let mut stalled_checks = 0u32;
        while !stop.load(Ordering::SeqCst) {
            thread::sleep(Duration::from_secs(5));
            if stop.load(Ordering::SeqCst) {
                return;
            }
            let current = heartbeat.load(Ordering::SeqCst);
            if current != last {
                last = current;
                stalled_checks = 0;
                continue;
            }
            stalled_checks = stalled_checks.saturating_add(1);
            if watchdog_should_restart(stalled_checks) {
                unsafe {
                    PostMessageW(hwnd, WM_APP_FORCE_RESTART_WORKER, 0, 0);
                }
                // Give the replacement a full window before forcing again.
                stalled_checks = 0;
                last = current;
            }
        }
    })
}

unsafe fn apply_ui_fixture(app: &mut GuiApp, hwnd: HWND, fixture: UiFixture) {
    if fixture == UiFixture::HighContrast {
        refresh_high_contrast(true);
    }
    app.ui_fixture = Some(fixture);
    app.worker_error = fixture_worker_error(fixture);
    if let Some(snapshot) = fixture_snapshot(fixture) {
        if let Some(profile) = snapshot.platform.matched_profile.clone() {
            apply_profile_to_presets(app, hwnd, &profile);
        }
        app.latest_snapshot = Some(snapshot);
        app.latest_policy = None;
    }
    if let Some(error) = app.worker_error.as_ref() {
        if !app.status_label.is_null() {
            let text = wide(error);
            SetWindowTextW(app.status_label, text.as_ptr());
        }
        if fixture == UiFixture::LongError {
            hold_status(app);
        }
    }
    update_simple_view(app);
    InvalidateRect(hwnd, std::ptr::null(), 0);
    UpdateWindow(hwnd);
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
        WS_CHILD | SS_LEFT,
        -10000,
        -10000,
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
        WS_CHILD | SS_LEFT,
        -10000,
        -10000,
        300,
        22,
        hwnd,
        TITLE_LABEL as HMENU,
        instance,
        std::ptr::null(),
    )
}

unsafe fn create_header_controls(
    hwnd: HWND,
    instance: HINSTANCE,
    mode: state::UiMode,
    top_most: bool,
    write_enabled: bool,
) -> HeaderControls {
    let button_class = wide("BUTTON");
    let labels = [
        (SIMPLE_MODE, "简洁", 422),
        (ADVANCED_MODE, "高级", 486),
        (TOPMOST_TOGGLE, "置顶", 550),
        (WRITE_UNLOCK, "写入", 614),
    ];
    let mut controls = HeaderControls {
        simple: std::ptr::null_mut(),
        advanced: std::ptr::null_mut(),
        topmost: std::ptr::null_mut(),
        write: std::ptr::null_mut(),
    };
    for (id, label, x) in labels {
        let text = wide(label);
        let style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32;
        let button = CreateWindowExW(
            0,
            button_class.as_ptr(),
            text.as_ptr(),
            style,
            x,
            14,
            56,
            32,
            hwnd,
            id as HMENU,
            instance,
            std::ptr::null(),
        );
        match id {
            SIMPLE_MODE => {
                controls.simple = button;
                SendMessageW(
                    button,
                    BM_SETCHECK,
                    usize::from(mode == state::UiMode::Simple),
                    0,
                );
            }
            ADVANCED_MODE => {
                controls.advanced = button;
                SendMessageW(
                    button,
                    BM_SETCHECK,
                    usize::from(mode == state::UiMode::Advanced),
                    0,
                );
            }
            TOPMOST_TOGGLE => {
                controls.topmost = button;
                SendMessageW(button, BM_SETCHECK, usize::from(top_most), 0);
            }
            WRITE_UNLOCK => {
                controls.write = button;
                SendMessageW(button, BM_SETCHECK, usize::from(write_enabled), 0);
            }
            _ => {}
        }
    }
    controls
}

unsafe fn set_control_font(control: HWND, font: HGDIOBJ) {
    if !control.is_null() && !font.is_null() {
        SendMessageW(control, 0x0030, font as usize, 1);
    }
}

unsafe fn create_simple_controls(
    hwnd: HWND,
    instance: HINSTANCE,
    fonts: &UiFonts,
    write_enabled: bool,
) -> SimpleViewControls {
    let static_class = wide("STATIC");
    let edit_class = wide("EDIT");
    let button_class = wide("BUTTON");
    let static_style = WS_CHILD | SS_LEFT;
    let create_label = |text: &str, x: i32, y: i32, width: i32, height: i32, id: usize| {
        let value = wide(text);
        CreateWindowExW(
            0,
            static_class.as_ptr(),
            value.as_ptr(),
            static_style,
            x,
            y,
            width,
            height,
            hwnd,
            id as HMENU,
            instance,
            std::ptr::null(),
        )
    };

    let power_value = create_label("--", -10000, -10000, 190, 52, POWER_VALUE_LABEL);
    let power_source = create_label("等待数据", -10000, -10000, 120, 24, POWER_SOURCE_LABEL);
    let target_label = create_label("目标功耗", -10000, -10000, 190, 22, TARGET_LABEL);
    let status = create_label(
        "正在连接 worker",
        -10000,
        -10000,
        458,
        30,
        SIMPLE_STATUS_LABEL,
    );
    let advanced_device = create_label(
        "设备信息\n等待 worker",
        -10000,
        -10000,
        560,
        72,
        ADVANCED_DEVICE_LABEL,
    );

    let target_edit = CreateWindowExW(
        0,
        edit_class.as_ptr(),
        wide("12").as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_NUMBER as u32 | ES_CENTER as u32,
        434,
        114,
        70,
        28,
        hwnd,
        SIMPLE_TARGET_EDIT as HMENU,
        instance,
        std::ptr::null(),
    );
    let apply = CreateWindowExW(
        0,
        button_class.as_ptr(),
        wide("应用").as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
        522,
        110,
        88,
        36,
        hwnd,
        SIMPLE_APPLY as HMENU,
        instance,
        std::ptr::null(),
    );

    let metric_names = ["STAPM", "PPT Fast", "PPT Slow", "CPU 温度"];
    let mut metric_titles = [std::ptr::null_mut(); 4];
    let mut metric_values = [std::ptr::null_mut(); 4];
    let mut metric_limits = [std::ptr::null_mut(); 4];
    for index in 0..4 {
        let x = -10000;
        metric_titles[index] = create_label(
            metric_names[index],
            x,
            -10000,
            132,
            20,
            METRIC_TITLE_START + index,
        );
        metric_values[index] = create_label("--", x, -10000, 132, 28, METRIC_VALUE_START + index);
        metric_limits[index] =
            create_label("上限 --", x, -10000, 132, 20, METRIC_LIMIT_START + index);
    }

    set_control_font(power_value, fonts.display);
    set_control_font(power_source, fonts.caption);
    set_control_font(target_label, fonts.body);
    set_control_font(status, fonts.body);
    set_control_font(advanced_device, fonts.body);
    set_control_font(target_edit, fonts.metric);
    set_control_font(apply, fonts.body);
    for index in 0..4 {
        set_control_font(metric_titles[index], fonts.caption);
        set_control_font(metric_values[index], fonts.metric);
        set_control_font(metric_limits[index], fonts.caption);
    }

    if !write_enabled {
        ShowWindow(target_edit, SW_HIDE);
        ShowWindow(apply, SW_HIDE);
    }

    SimpleViewControls {
        power_value,
        power_source,
        target_label,
        target_edit,
        apply,
        metric_titles,
        metric_values,
        metric_limits,
        status,
        advanced_device,
    }
}

unsafe fn create_action_buttons(
    hwnd: HWND,
    instance: HINSTANCE,
    preset_watts: [i32; 3],
) -> [HWND; 3] {
    let button_class = wide("BUTTON");
    let controls = [
        (PRESET_12, format!("{} W", preset_watts[0]), 110, 196, 92),
        (PRESET_25, format!("{} W", preset_watts[1]), 210, 196, 92),
        (PRESET_45, format!("{} W", preset_watts[2]), 310, 196, 92),
        (APPLY_TARGET, "应用".to_owned(), 360, 348, 120),
        (PRESET_EDIT_OPEN, "编辑".to_owned(), 410, 196, 60),
    ];
    let mut presets = [std::ptr::null_mut(); 3];
    for (index, (id, label, x, y, width)) in controls.into_iter().enumerate() {
        let text = wide(&label);
        let style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32;
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
    let edit_style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_NUMBER as u32 | ES_CENTER as u32;

    CreateWindowExW(
        0,
        static_class.as_ptr(),
        label_text.as_ptr(),
        WS_CHILD,
        -10000,
        -10000,
        76,
        22,
        hwnd,
        PRESET_LABEL as HMENU,
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
            110 + index as i32 * 68,
            266,
            58,
            28,
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
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
        112,
        304,
        100,
        32,
        hwnd,
        PRESET_SAVE as HMENU,
        instance,
        std::ptr::null(),
    );

    edits
}

unsafe fn create_export_button(
    hwnd: HWND,
    instance: HINSTANCE,
    x: i32,
    y: i32,
    width: i32,
) -> HWND {
    let button_class = wide("BUTTON");
    let text = wide("导出诊断");
    CreateWindowExW(
        0,
        button_class.as_ptr(),
        text.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
        x,
        y,
        width,
        30,
        hwnd,
        EXPORT_DIAGNOSTICS as HMENU,
        instance,
        std::ptr::null(),
    )
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

fn clamp_to_ceiling(presets: [i32; 3], ceiling: Option<i32>) -> [i32; 3] {
    match ceiling {
        Some(cap) => presets.map(|watts| watts.min(cap).max(1)),
        None => presets,
    }
}

/// Effective upper bound for any target, combining the platform profile with
/// the optional per-installation ceiling.
fn target_ceiling(app: &GuiApp) -> Option<i32> {
    let profile_maximum = app.profile.as_ref().map(|profile| profile.maximum_watts);
    match (app.max_target_watts, profile_maximum) {
        (Some(cap), Some(profile)) => Some(cap.min(profile)),
        (Some(cap), None) => Some(cap),
        (None, Some(profile)) => Some(profile),
        (None, None) => None,
    }
}

fn profile_limits(app: &GuiApp) -> (i32, i32) {
    let minimum = app
        .profile
        .as_ref()
        .map(|profile| profile.minimum_watts)
        .unwrap_or(5);
    let maximum = target_ceiling(app).unwrap_or(60);
    (minimum, maximum)
}

fn preset_menu_label(index: usize, watts: i32) -> String {
    format!("应用预设 {}：{} W", index + 1, watts)
}

/// Presets that duplicate the previous value are hidden so a capped
/// installation shows only its distinct choices.
fn preset_is_visible(app: &GuiApp, index: usize) -> bool {
    index == 0 || app.preset_watts[index] != app.preset_watts[index - 1]
}

unsafe fn apply_preset_visibility(app: &GuiApp, hwnd: HWND) {
    for (index, id) in [PRESET_12, PRESET_25, PRESET_45].into_iter().enumerate() {
        set_control_visible(hwnd, id, preset_is_visible(app, index));
    }
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
    let ac_label = wide("外接目标");
    let enabled_label = wide("启用");
    let save_label = wide("保存策略");
    let battery_only_label = wide("仅电池");
    let edit_style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_NUMBER as u32 | ES_CENTER as u32;

    CreateWindowExW(
        0,
        static_class.as_ptr(),
        battery_label.as_ptr(),
        WS_CHILD,
        -10000,
        -10000,
        108,
        22,
        hwnd,
        POLICY_BATTERY_LABEL as HMENU,
        instance,
        std::ptr::null(),
    );
    let battery_target = CreateWindowExW(
        0,
        edit_class.as_ptr(),
        wide("12").as_ptr(),
        edit_style,
        84,
        376,
        54,
        28,
        hwnd,
        POLICY_BATTERY_EDIT as HMENU,
        instance,
        std::ptr::null(),
    );
    CreateWindowExW(
        0,
        static_class.as_ptr(),
        ac_label.as_ptr(),
        WS_CHILD,
        -10000,
        -10000,
        62,
        22,
        hwnd,
        POLICY_AC_LABEL as HMENU,
        instance,
        std::ptr::null(),
    );
    let ac_target = CreateWindowExW(
        0,
        edit_class.as_ptr(),
        wide("45").as_ptr(),
        edit_style,
        198,
        376,
        54,
        28,
        hwnd,
        POLICY_AC_EDIT as HMENU,
        instance,
        std::ptr::null(),
    );
    let enabled = CreateWindowExW(
        0,
        button_class.as_ptr(),
        enabled_label.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
        274,
        374,
        74,
        32,
        hwnd,
        POLICY_ENABLED as HMENU,
        instance,
        std::ptr::null(),
    );
    let _save = CreateWindowExW(
        0,
        button_class.as_ptr(),
        save_label.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
        40,
        416,
        112,
        32,
        hwnd,
        POLICY_SAVE as HMENU,
        instance,
        std::ptr::null(),
    );
    let battery_only = CreateWindowExW(
        0,
        button_class.as_ptr(),
        battery_only_label.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
        166,
        480,
        112,
        32,
        hwnd,
        POLICY_BATTERY_ONLY as HMENU,
        instance,
        std::ptr::null(),
    );

    PolicyControls {
        enabled,
        battery_target,
        ac_target,
        battery_only,
    }
}

fn format_policy_result(settings: PowerPolicySettings, result: Result<(), String>) -> String {
    match result {
        Ok(()) => {
            let scope = if settings.battery_enabled && settings.ac_enabled {
                format!(
                    "电池 {} W / 外接 {} W。",
                    settings.battery_target.stapm_watts, settings.ac_target.stapm_watts
                )
            } else if settings.battery_enabled {
                format!(
                    "仅电池 {} W，外接不控制。",
                    settings.battery_target.stapm_watts
                )
            } else if settings.ac_enabled {
                format!("仅外接 {} W，电池不控制。", settings.ac_target.stapm_watts)
            } else {
                "未选择供电路径。".to_owned()
            };
            format!(
                "自动策略已保存。\n{}\n{}",
                scope,
                if settings.enabled {
                    "已启用。"
                } else {
                    "已停用。"
                }
            )
        }
        Err(error) => format!("策略保存失败。\n{error}"),
    }
}

fn hold_status(app: &mut GuiApp) {
    app.status_hold_until = Instant::now() + STATUS_HOLD;
}

unsafe fn set_control_visible(hwnd: HWND, id: usize, visible: bool) {
    let control = GetDlgItem(hwnd, id as i32);
    if !control.is_null() {
        ShowWindow(control, if visible { SW_SHOWNORMAL } else { SW_HIDE });
    }
}

unsafe fn update_write_availability(app: &GuiApp, hwnd: HWND) {
    let supported = app
        .latest_snapshot
        .as_ref()
        .map(|snapshot| snapshot.platform.is_supported)
        .unwrap_or(false);
    let available =
        app.write_enabled && !app.apply_in_flight && app.worker_error.is_none() && supported;

    if let Some(controls) = app.simple_controls {
        EnableWindow(controls.target_edit, i32::from(available));
        EnableWindow(controls.apply, i32::from(available));
    }
    if let Some(buttons) = app.preset_buttons {
        for button in buttons {
            EnableWindow(button, i32::from(available));
        }
    }
    if let Some(edits) = app.preset_edits {
        for edit in edits {
            EnableWindow(edit, i32::from(available));
        }
    }
    if let Some(controls) = app.policy_controls {
        for control in [
            controls.battery_target,
            controls.ac_target,
            controls.enabled,
            controls.battery_only,
        ] {
            EnableWindow(control, i32::from(available));
        }
    }
    for id in [POLICY_SAVE, PRESET_SAVE] {
        let control = GetDlgItem(hwnd, id as i32);
        if !control.is_null() {
            EnableWindow(control, i32::from(available));
        }
    }
}

unsafe fn update_simple_view(app: &GuiApp) {
    let Some(controls) = app.simple_controls else {
        return;
    };
    update_write_availability(app, GetParent(controls.target_edit));
    let (range_minimum, range_maximum) = profile_limits(app);
    let expected_target = app
        .selected_preset
        .map(|index| app.preset_watts[index])
        .unwrap_or(app.selected_target.stapm_watts)
        .clamp(range_minimum, range_maximum);
    if !app.target_edit_dirty
        && GetFocus() != controls.target_edit
        && get_control_text(controls.target_edit).trim() != expected_target.to_string()
    {
        set_edit_watts(controls.target_edit, expected_target);
    }
    let target_label = wide(&format!(
        "目标功耗 · 范围 {range_minimum}-{range_maximum} W"
    ));
    SetWindowTextW(controls.target_label, target_label.as_ptr());

    let Some(snapshot) = app.latest_snapshot.as_ref() else {
        let waiting = wide("等待 worker");
        SetWindowTextW(controls.power_value, waiting.as_ptr());
        let status = if let Some(error) = app.worker_error.as_ref() {
            format!(
                "连接异常 · {}",
                error.lines().next().unwrap_or("worker 不可用")
            )
        } else if app.write_enabled {
            "写入已解锁 · 正在连接 worker".to_owned()
        } else {
            "只读模式 · 写入未解锁".to_owned()
        };
        let status = wide(&status);
        SetWindowTextW(controls.status, status.as_ptr());
        let device = wide("设备信息\n等待 worker");
        SetWindowTextW(controls.advanced_device, device.as_ptr());
        return;
    };
    let telemetry = &snapshot.telemetry;
    let live_value = format_watts(telemetry.stapm_value_watts);
    let live_value = wide(&live_value);
    SetWindowTextW(controls.power_value, live_value.as_ptr());
    let source = wide(&format!(
        "{} · {}",
        format_power_line_raw(&telemetry.power_line),
        format_watts(telemetry.stapm_limit_watts)
    ));
    SetWindowTextW(controls.power_source, source.as_ptr());

    let actual_values = [
        format_watts(telemetry.stapm_value_watts),
        format_watts(telemetry.fast_value_watts),
        format_watts(telemetry.slow_value_watts),
        format_celsius(telemetry.tctl_value_celsius),
    ];
    let limits = [
        format!("上限 {}", format_watts(telemetry.stapm_limit_watts)),
        format!("上限 {}", format_watts(telemetry.fast_limit_watts)),
        format!("上限 {}", format_watts(telemetry.slow_limit_watts)),
        format!("上限 {}", format_celsius(telemetry.tctl_limit_celsius)),
    ];
    for index in 0..4 {
        let value = wide(&actual_values[index]);
        SetWindowTextW(controls.metric_values[index], value.as_ptr());
        let limit = wide(&limits[index]);
        SetWindowTextW(controls.metric_limits[index], limit.as_ptr());
    }

    let status = if let Some(error) = app.worker_error.as_ref() {
        format!(
            "连接异常 · {}",
            error.lines().next().unwrap_or("worker 不可用")
        )
    } else if !snapshot.platform.is_supported {
        format!(
            "平台不支持 · {}",
            snapshot
                .platform
                .unsupported_reason
                .as_deref()
                .unwrap_or("仅允许只读监测")
        )
    } else if telemetry.has_firmware_clamp {
        "固件钳制生效 · 查看实际回读".to_owned()
    } else if !app.write_enabled {
        "只读模式 · 写入未解锁".to_owned()
    } else if let Some(target) = telemetry.target_watts {
        format!("写入已解锁 · 当前目标 {}", format_watts(Some(target)))
    } else {
        "写入已解锁 · 等待目标".to_owned()
    };
    let status = wide(&status);
    SetWindowTextW(controls.status, status.as_ptr());
    let profile = snapshot
        .platform
        .matched_profile
        .as_ref()
        .map(|profile| {
            format!(
                "{} [{}-{} W]",
                profile.display_name, profile.minimum_watts, profile.maximum_watts
            )
        })
        .unwrap_or_else(|| "无匹配配置".to_owned());
    let device = wide(&format!(
        "处理器：{}\n平台：{} · PM {}\n供电：{} · 可写：{}",
        snapshot.platform.cpu.processor_name,
        profile,
        snapshot
            .platform
            .cpu
            .pm_table_version
            .as_deref()
            .unwrap_or("未知"),
        format_power_line_raw(&telemetry.power_line),
        format_writable_fields(
            snapshot.platform.limits.supports_stapm,
            snapshot.platform.limits.supports_fast,
            snapshot.platform.limits.supports_slow
        )
    ));
    SetWindowTextW(controls.advanced_device, device.as_ptr());

    if GetWindowTextLengthW(controls.target_edit) == 0 {
        set_edit_watts(
            controls.target_edit,
            app.selected_target
                .stapm_watts
                .clamp(range_minimum, range_maximum),
        );
    }
}

unsafe fn apply_topmost_style(hwnd: HWND, enabled: bool) {
    SetWindowPos(
        hwnd,
        if enabled {
            HWND_TOPMOST
        } else {
            HWND_NOTOPMOST
        },
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
    );
}

unsafe fn window_dpi(hwnd: HWND) -> u32 {
    let dpi = GetDpiForWindow(hwnd);
    if dpi == 0 {
        BASE_DPI as u32
    } else {
        dpi
    }
}

unsafe fn outer_window_size(client_width: i32, client_height: i32, dpi: u32) -> (i32, i32) {
    let mut rect = RECT {
        left: 0,
        top: 0,
        right: client_width,
        bottom: client_height,
    };
    AdjustWindowRectExForDpi(&mut rect, APP_WINDOW_STYLE, 0, WS_EX_APPWINDOW, dpi);
    (rect.right - rect.left, rect.bottom - rect.top)
}

unsafe fn move_control(hwnd: HWND, id: usize, x: i32, y: i32, width: i32, height: i32) {
    let control = GetDlgItem(hwnd, id as i32);
    if !control.is_null() {
        let app = app_from_window(hwnd);
        let (offset_x, offset_y) = if app.is_null() {
            (0, 0)
        } else {
            (
                scaled((*app).scroll_offset_x, (*app).dpi_percent),
                scaled((*app).scroll_offset, (*app).dpi_percent),
            )
        };
        SetWindowPos(
            control,
            std::ptr::null_mut(),
            x - offset_x,
            y - offset_y,
            width,
            height,
            SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOREDRAW,
        );
    }
}

unsafe fn monitor_work_area(hwnd: HWND) -> Option<RECT> {
    if let Ok(value) = std::env::var("AMD_MOBILE_POWER_WORK_AREA_FIXTURE") {
        if let Some((width, height)) = value.split_once('x') {
            if let (Ok(width), Ok(height)) = (width.parse::<i32>(), height.parse::<i32>()) {
                if width > 0 && height > 0 {
                    return Some(RECT {
                        left: 0,
                        top: 0,
                        right: width,
                        bottom: height,
                    });
                }
            }
        }
    }
    let mut monitor = MONITORINFO {
        cbSize: size_of::<MONITORINFO>() as u32,
        ..Default::default()
    };
    (GetMonitorInfoW(
        MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
        &mut monitor,
    ) != 0)
        .then_some(monitor.rcWork)
}

unsafe fn set_scroll_offsets(app: &mut GuiApp, hwnd: HWND, x: i32, y: i32) {
    let mut client = RECT::default();
    GetClientRect(hwnd, &mut client);
    let advanced = app.view_mode == state::UiMode::Advanced;
    let x = if advanced {
        scroll_position(
            x,
            ADVANCED_CONTENT_WIDTH,
            unscaled(client.right.max(1), app.dpi_percent),
        )
    } else {
        0
    };
    let y = scroll_position(
        y,
        content_height(app.view_mode),
        unscaled(client.bottom.max(1), app.dpi_percent),
    );
    if app.scroll_offset != y || app.scroll_offset_x != x {
        app.scroll_offset = y;
        app.scroll_offset_x = x;
        layout_mode_controls(app, hwnd);
    }
}

unsafe fn set_scroll_offset(app: &mut GuiApp, hwnd: HWND, position: i32) {
    set_scroll_offsets(app, hwnd, app.scroll_offset_x, position);
}

unsafe fn reveal_control(app: &mut GuiApp, hwnd: HWND, control: HWND) {
    if control.is_null() || app.layout_in_progress {
        return;
    }
    let mut bounds = RECT::default();
    let mut client = RECT::default();
    if GetWindowRect(control, &mut bounds) == 0 || GetClientRect(hwnd, &mut client) == 0 {
        return;
    }
    let mut top = POINT {
        x: bounds.left,
        y: bounds.top,
    };
    let mut bottom = POINT {
        x: bounds.right,
        y: bounds.bottom,
    };
    ScreenToClient(hwnd, &mut top);
    ScreenToClient(hwnd, &mut bottom);
    let margin = scaled(8, app.dpi_percent);
    let delta_y = if top.y < margin {
        top.y - margin
    } else if bottom.y > client.bottom - margin {
        bottom.y - client.bottom + margin
    } else {
        0
    };
    let delta_x = if top.x < margin {
        top.x - margin
    } else if bottom.x > client.right - margin {
        bottom.x - client.right + margin
    } else {
        0
    };
    if delta_x != 0 || delta_y != 0 {
        set_scroll_offsets(
            app,
            hwnd,
            app.scroll_offset_x + unscaled(delta_x, app.dpi_percent),
            app.scroll_offset + unscaled(delta_y, app.dpi_percent),
        );
    }
}

unsafe extern "system" fn button_feedback_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    _subclass_id: usize,
    _reference: usize,
) -> LRESULT {
    let parent = GetParent(hwnd);
    let pointer = app_from_window(parent);
    if !pointer.is_null() {
        let app = &mut *pointer;
        let id = GetDlgCtrlID(hwnd) as usize;
        match message {
            0x0007 => {
                app.focused_control = Some(id);
                reveal_control(app, parent, hwnd);
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            0x0008 if app.focused_control == Some(id) => {
                app.focused_control = None;
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            WM_MOUSEMOVE if IsWindowEnabled(hwnd) != 0 => {
                if app.hovered_control != Some(id) {
                    if let Some(previous) = app.hovered_control.replace(id) {
                        InvalidateRect(GetDlgItem(parent, previous as i32), std::ptr::null(), 0);
                    }
                    InvalidateRect(hwnd, std::ptr::null(), 0);
                    let mut tracking = TRACKMOUSEEVENT {
                        cbSize: size_of::<TRACKMOUSEEVENT>() as u32,
                        dwFlags: TME_LEAVE,
                        hwndTrack: hwnd,
                        dwHoverTime: 0,
                    };
                    TrackMouseEvent(&mut tracking);
                }
            }
            WM_MOUSELEAVE if app.hovered_control == Some(id) => {
                app.hovered_control = None;
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            WM_SETCURSOR if IsWindowEnabled(hwnd) != 0 => {
                SetCursor(LoadCursorW(std::ptr::null_mut(), IDC_HAND));
                return 1;
            }
            _ => {}
        }
    }
    DefSubclassProc(hwnd, message, wparam, lparam)
}

unsafe fn register_control_tooltip(app: &mut GuiApp, hwnd: HWND, id: usize, text: &str) {
    let control = GetDlgItem(hwnd, id as i32);
    if control.is_null() || app.tooltip.is_null() {
        return;
    }
    app.tooltip_texts.push(wide(text));
    let mut tool = TTTOOLINFOW {
        cbSize: size_of::<TTTOOLINFOW>() as u32,
        uFlags: TTF_IDISHWND | TTF_SUBCLASS,
        hwnd,
        uId: control as usize,
        lpszText: app.tooltip_texts.last_mut().unwrap().as_mut_ptr(),
        ..Default::default()
    };
    SendMessageW(app.tooltip, TTM_ADDTOOLW, 0, &mut tool as *mut _ as isize);
}

unsafe fn initialize_control_feedback(app: &mut GuiApp, hwnd: HWND, instance: HINSTANCE) {
    app.tooltip = CreateWindowExW(
        0,
        TOOLTIPS_CLASSW,
        std::ptr::null(),
        WS_POPUP | TTS_ALWAYSTIP,
        0,
        0,
        0,
        0,
        hwnd,
        std::ptr::null_mut(),
        instance,
        std::ptr::null(),
    );
    SendMessageW(
        app.tooltip,
        TTM_SETMAXTIPWIDTH,
        0,
        scaled(440, app.dpi_percent) as isize,
    );
    for (id, text) in [
        (SIMPLE_MODE, "简洁模式"),
        (ADVANCED_MODE, "高级模式"),
        (TOPMOST_TOGGLE, "切换窗口置顶"),
        (WRITE_UNLOCK, "解锁或重新锁定写入"),
        (PRESET_12, "预设 1"),
        (PRESET_25, "预设 2"),
        (PRESET_45, "预设 3"),
        (PRESET_EDIT_OPEN, "编辑三档快捷预设"),
        (SIMPLE_APPLY, "应用目标功耗，并验证硬件回读"),
        (PRESET_SAVE, "保存三档快捷预设"),
        (POLICY_ENABLED, "启用或停用自动电源策略，保存后生效"),
        (POLICY_BATTERY_ONLY, "仅在电池供电时应用自动策略"),
        (POLICY_SAVE, "保存自动电源策略"),
        (EXPORT_DIAGNOSTICS, "导出诊断报告"),
    ] {
        let control = GetDlgItem(hwnd, id as i32);
        if !control.is_null() {
            SetWindowSubclass(control, Some(button_feedback_proc), 1, 0);
            register_control_tooltip(app, hwnd, id, text);
        }
    }
    for id in 9001..=9005 {
        let mut tool = TTTOOLINFOW {
            cbSize: size_of::<TTTOOLINFOW>() as u32,
            uFlags: TTF_SUBCLASS,
            hwnd,
            uId: id,
            lpszText: -1_isize as *mut u16,
            ..Default::default()
        };
        SendMessageW(app.tooltip, TTM_ADDTOOLW, 0, &mut tool as *mut _ as isize);
    }
}

unsafe fn layout_text_tooltips(app: &GuiApp, hwnd: HWND, width: i32) {
    if app.tooltip.is_null() {
        return;
    }
    let advanced = app.view_mode == state::UiMode::Advanced;
    let side_left = width - 296;
    let status_top = if advanced { 628 } else { 312 };
    for (id, bounds) in [
        (9001, (24, 6, width - 212, 52)),
        (9002, (24, status_top, width - 76, status_top + 40)),
        (9003, (side_left, 274, width - 24, 322)),
        (9004, (side_left, 394, width - 24, 440)),
        (9005, (side_left, 570, width - 24, 616)),
    ] {
        let (left, top, right, bottom) = if id >= 9003 && !advanced {
            (0, 0, 0, 0)
        } else {
            bounds
        };
        let left = left - app.scroll_offset_x;
        let right = right - app.scroll_offset_x;
        let top = top - app.scroll_offset;
        let bottom = bottom - app.scroll_offset;
        let s = |value| scaled(value, app.dpi_percent);
        let mut tool = TTTOOLINFOW {
            cbSize: size_of::<TTTOOLINFOW>() as u32,
            hwnd,
            uId: id,
            rect: RECT {
                left: s(left),
                top: s(top),
                right: s(right),
                bottom: s(bottom),
            },
            ..Default::default()
        };
        SendMessageW(
            app.tooltip,
            TTM_NEWTOOLRECTW,
            0,
            &mut tool as *mut _ as isize,
        );
    }
}

unsafe fn apply_view_mode(app: &mut GuiApp, hwnd: HWND, mode: state::UiMode) {
    apply_view_mode_inner(app, hwnd, mode, false);
}

unsafe fn apply_view_mode_inner(
    app: &mut GuiApp,
    hwnd: HWND,
    mode: state::UiMode,
    preserve_scroll: bool,
) {
    app.view_mode = mode;
    if !preserve_scroll {
        app.scroll_offset = 0;
        app.scroll_offset_x = 0;
    }
    let percent = app.dpi_percent.max(1);
    let (width, height) = match mode {
        state::UiMode::Simple => SIMPLE_CLIENT_SIZE,
        state::UiMode::Advanced => ADVANCED_CLIENT_SIZE,
    };
    let (outer_width_requested, outer_height_requested) = outer_window_size(
        scaled(width, percent),
        scaled(height, percent),
        window_dpi(hwnd),
    );
    let mut outer_width = outer_width_requested;
    let mut outer_height = outer_height_requested;
    let mut position = POINT::default();
    let mut bounds = RECT::default();
    GetWindowRect(hwnd, &mut bounds);
    position.x = bounds.left;
    position.y = bounds.top;
    // Logical screenshot fixtures keep their full canvas; real windows fit
    // the current monitor work area and scroll any remaining advanced content.
    if DPI_FIXTURE_PERCENT.load(Ordering::Relaxed) == 0
        || std::env::var_os("AMD_MOBILE_POWER_WORK_AREA_FIXTURE").is_some()
    {
        if let Some(work) = monitor_work_area(hwnd) {
            outer_height = outer_height.min(work.bottom - work.top);
            outer_width = outer_width.min(work.right - work.left);
            position.x = position
                .x
                .clamp(work.left, (work.right - outer_width).max(work.left));
            position.y = position
                .y
                .clamp(work.top, (work.bottom - outer_height).max(work.top));
        }
    }
    let suspended = suspend_redraw(app, hwnd);
    SetWindowPos(
        hwnd,
        std::ptr::null_mut(),
        position.x,
        position.y,
        outer_width,
        outer_height,
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOREDRAW,
    );
    layout_mode_controls(app, hwnd);

    let preferences = state::WindowPreferences {
        mode,
        top_most: app.top_most,
    };
    if let Err(error) = state::save_window_preferences(preferences) {
        if !app.status_label.is_null() {
            hold_status(app);
            let text = wide(&format!("窗口设置保存失败。\n{error}"));
            SetWindowTextW(app.status_label, text.as_ptr());
        }
    }
    resume_redraw(app, hwnd, suspended);
}

/// Freezes the window for one layout pass so the resize, the child moves and
/// the final frame reach the screen together. Nested calls are no-ops.
unsafe fn suspend_redraw(app: &mut GuiApp, hwnd: HWND) -> bool {
    if app.redraw_suspended || IsWindowVisible(hwnd) == 0 {
        return false;
    }
    SendMessageW(hwnd, WM_SETREDRAW, 0, 0);
    app.redraw_suspended = true;
    true
}

unsafe fn resume_redraw(app: &mut GuiApp, hwnd: HWND, suspended: bool) {
    if !suspended || !app.redraw_suspended {
        return;
    }
    app.redraw_suspended = false;
    SendMessageW(hwnd, WM_SETREDRAW, 1, 0);
    RedrawWindow(
        hwnd,
        std::ptr::null(),
        std::ptr::null_mut(),
        RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN,
    );
}

/// Places the child controls for the current mode using the live client width,
/// so a user-resized window keeps its right-aligned controls in place.
unsafe fn layout_mode_controls(app: &mut GuiApp, hwnd: HWND) {
    layout_mode_controls_depth(app, hwnd, 0);
}

unsafe fn layout_mode_controls_depth(app: &mut GuiApp, hwnd: HWND, depth: u32) {
    if app.layout_in_progress {
        // A resize or scrollbar toggle can land while the previous pass is
        // still running; remember it instead of dropping the new geometry.
        app.layout_pending = true;
        return;
    }
    app.layout_in_progress = true;
    let suspended = suspend_redraw(app, hwnd);
    let mode = app.view_mode;
    let advanced = mode == state::UiMode::Advanced;
    let percent = app.dpi_percent.max(1);
    let s = |value: i32| scaled(value, percent);
    let mut client = RECT::default();
    GetClientRect(hwnd, &mut client);
    let mut viewport_width = unscaled(client.right.max(1), percent);
    let mut viewport_height = unscaled(client.bottom.max(1), percent);
    // Showing or hiding one native scrollbar changes the client area, which
    // changes whether the other bar is needed. Recompute until the client
    // size stabilises, otherwise an advanced window can keep a phantom bar
    // that eats 17 logical pixels.
    for _ in 0..3 {
        app.scroll_offset =
            scroll_position(app.scroll_offset, content_height(mode), viewport_height);
        app.scroll_offset_x = if advanced {
            scroll_position(app.scroll_offset_x, ADVANCED_CONTENT_WIDTH, viewport_width)
        } else {
            0
        };
        let vscroll = SCROLLINFO {
            cbSize: size_of::<SCROLLINFO>() as u32,
            fMask: SIF_RANGE | SIF_PAGE | SIF_POS,
            nMin: 0,
            nMax: if content_height(mode) > 0 {
                content_height(mode) - 1
            } else {
                0
            },
            nPage: viewport_height.max(1) as u32,
            nPos: app.scroll_offset,
            ..Default::default()
        };
        let hscroll = SCROLLINFO {
            cbSize: size_of::<SCROLLINFO>() as u32,
            fMask: SIF_RANGE | SIF_PAGE | SIF_POS,
            nMin: 0,
            nMax: if advanced {
                ADVANCED_CONTENT_WIDTH - 1
            } else {
                0
            },
            nPage: if advanced {
                viewport_width.max(1) as u32
            } else {
                1
            },
            nPos: app.scroll_offset_x,
            ..Default::default()
        };
        SetScrollInfo(hwnd, SB_VERT, &vscroll, 1);
        SetScrollInfo(hwnd, SB_HORZ, &hscroll, 1);

        let mut next_client = RECT::default();
        GetClientRect(hwnd, &mut next_client);
        if next_client.right == client.right && next_client.bottom == client.bottom {
            break;
        }
        client = next_client;
        viewport_width = unscaled(client.right.max(1), percent);
        viewport_height = unscaled(client.bottom.max(1), percent);
    }
    let viewport_width = unscaled(client.right.max(1), percent);
    let width = if advanced {
        ADVANCED_CONTENT_WIDTH.max(viewport_width)
    } else {
        minimum_client_size(mode).0.max(viewport_width)
    };
    let layout = CommandLayout::new(width);

    if let Some(controls) = app.header_controls {
        let topmost_left = width - 60;
        let write_left = width - 104;
        let advanced_left = width - 172;
        let simple_left = width - 232;
        for (control, left, control_width, checked) in [
            (
                controls.simple,
                simple_left,
                56,
                mode == state::UiMode::Simple,
            ),
            (controls.advanced, advanced_left, 56, advanced),
            (controls.write, write_left, 36, app.write_enabled),
            (controls.topmost, topmost_left, 36, app.top_most),
        ] {
            SetWindowPos(
                control,
                std::ptr::null_mut(),
                s(left) - scaled(app.scroll_offset_x, percent),
                s(12) - scaled(app.scroll_offset, percent),
                s(control_width),
                s(32),
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
            SendMessageW(control, BM_SETCHECK, usize::from(checked), 0);
            InvalidateRect(control, std::ptr::null(), 1);
        }
    }

    apply_preset_visibility(app, hwnd);
    set_control_visible(hwnd, PRESET_EDIT_OPEN, true);
    set_control_visible(hwnd, APPLY_TARGET, false);
    set_control_visible(hwnd, EXPORT_DIAGNOSTICS, true);

    for id in [
        PRESET_SAVE,
        PRESET_EDIT_START,
        PRESET_EDIT_START + 1,
        PRESET_EDIT_START + 2,
        POLICY_BATTERY_EDIT,
        POLICY_AC_EDIT,
        POLICY_ENABLED,
        POLICY_BATTERY_ONLY,
        POLICY_SAVE,
    ] {
        set_control_visible(hwnd, id, advanced);
    }
    for id in [PRESET_LABEL, POLICY_BATTERY_LABEL, POLICY_AC_LABEL] {
        set_control_visible(hwnd, id, advanced);
    }

    if let Some(controls) = app.simple_controls {
        for control in [
            controls.power_value,
            controls.power_source,
            controls.target_label,
            controls.status,
        ]
        .into_iter()
        .chain(controls.metric_titles)
        .chain(controls.metric_values)
        .chain(controls.metric_limits)
        {
            if !control.is_null() {
                ShowWindow(control, SW_HIDE);
            }
        }
        ShowWindow(
            controls.advanced_device,
            if advanced { SW_SHOWNORMAL } else { SW_HIDE },
        );
        ShowWindow(controls.target_edit, SW_SHOWNORMAL);
        ShowWindow(controls.apply, SW_SHOWNORMAL);
    }
    if !app.status_label.is_null() {
        ShowWindow(app.status_label, SW_HIDE);
    }
    set_control_visible(hwnd, TITLE_LABEL, false);

    move_control(
        hwnd,
        SIMPLE_TARGET_EDIT,
        s(layout.target_left + 4),
        s(109),
        s(68),
        s(26),
    );
    move_control(
        hwnd,
        SIMPLE_APPLY,
        s(layout.apply_left),
        s(98),
        s(layout.apply_width),
        s(42),
    );
    let mut slot = 0;
    for (index, id) in [PRESET_12, PRESET_25, PRESET_45].into_iter().enumerate() {
        if preset_is_visible(app, index) {
            move_control(
                hwnd,
                id,
                s(layout.preset_x(slot)),
                s(174),
                s(layout.preset_width),
                s(34),
            );
            slot += 1;
        }
    }
    move_control(
        hwnd,
        PRESET_EDIT_OPEN,
        s(layout.edit_left),
        s(174),
        s(44),
        s(34),
    );
    if advanced {
        for (index, id) in [
            PRESET_EDIT_START,
            PRESET_EDIT_START + 1,
            PRESET_EDIT_START + 2,
        ]
        .into_iter()
        .enumerate()
        {
            move_control(hwnd, id, s(28 + index as i32 * 104), s(298), s(64), s(26));
        }
        move_control(hwnd, PRESET_SAVE, s(336), s(294), s(100), s(34));
        move_control(hwnd, POLICY_BATTERY_EDIT, s(94), s(402), s(70), s(26));
        move_control(hwnd, POLICY_AC_EDIT, s(286), s(402), s(70), s(26));
        move_control(hwnd, POLICY_ENABLED, s(336), s(360), s(100), s(32));
        move_control(hwnd, POLICY_BATTERY_ONLY, s(90), s(450), s(112), s(34));
        move_control(hwnd, POLICY_SAVE, s(324), s(450), s(112), s(34));
        move_control(
            hwnd,
            EXPORT_DIAGNOSTICS,
            s(width - 64),
            s(632),
            s(36),
            s(32),
        );
        for id in [
            PRESET_LABEL,
            POLICY_BATTERY_LABEL,
            POLICY_AC_LABEL,
            ADVANCED_DEVICE_LABEL,
        ] {
            move_control(hwnd, id, -10000, -10000, 220, 24);
        }
    } else {
        move_control(
            hwnd,
            EXPORT_DIAGNOSTICS,
            s(width - 64),
            s(316),
            s(36),
            s(32),
        );
    }

    update_write_availability(app, hwnd);
    layout_text_tooltips(app, hwnd, width);

    for id in [
        SIMPLE_MODE,
        ADVANCED_MODE,
        TOPMOST_TOGGLE,
        PRESET_12,
        PRESET_25,
        PRESET_45,
        PRESET_EDIT_OPEN,
        PRESET_SAVE,
        POLICY_ENABLED,
        POLICY_BATTERY_ONLY,
        POLICY_SAVE,
        SIMPLE_APPLY,
        EXPORT_DIAGNOSTICS,
    ] {
        let control = GetDlgItem(hwnd, id as i32);
        if !control.is_null() {
            InvalidateRect(control, std::ptr::null(), 1);
        }
    }

    update_simple_view(app);
    InvalidateRect(hwnd, std::ptr::null(), 0);
    app.layout_in_progress = false;
    resume_redraw(app, hwnd, suspended);
    while app.layout_pending && depth < 3 {
        app.layout_pending = false;
        layout_mode_controls_depth(app, hwnd, depth + 1);
    }
}

/// Rebuilds the device-sized fonts used by native child controls after a DPI
/// change. Custom painting keeps its logical font set.
unsafe fn refresh_control_fonts(app: &mut GuiApp) {
    let fonts = create_ui_fonts(app.dpi_percent.max(1));
    if let Some(controls) = app.simple_controls {
        set_control_font(controls.power_value, fonts.display);
        set_control_font(controls.power_source, fonts.caption);
        set_control_font(controls.target_label, fonts.body);
        set_control_font(controls.status, fonts.body);
        set_control_font(controls.advanced_device, fonts.body);
        set_control_font(controls.target_edit, fonts.metric);
        set_control_font(controls.apply, fonts.body);
        for index in 0..4 {
            set_control_font(controls.metric_titles[index], fonts.caption);
            set_control_font(controls.metric_values[index], fonts.metric);
            set_control_font(controls.metric_limits[index], fonts.caption);
        }
    }
    if !app.status_label.is_null() {
        set_control_font(app.status_label, fonts.body);
    }
    if let Some(edits) = app.preset_edits {
        for edit in edits {
            set_control_font(edit, fonts.metric);
        }
    }
    if let Some(controls) = app.policy_controls {
        set_control_font(controls.battery_target, fonts.metric);
        set_control_font(controls.ac_target, fonts.metric);
    }
    app.fonts = Some(fonts);
}

unsafe fn toggle_topmost(app: &mut GuiApp, hwnd: HWND) {
    app.top_most = !app.top_most;
    apply_topmost_style(hwnd, app.top_most);
    if let Some(controls) = app.header_controls {
        SendMessageW(controls.topmost, BM_SETCHECK, usize::from(app.top_most), 0);
        InvalidateRect(controls.topmost, std::ptr::null(), 1);
    }
    let preferences = state::WindowPreferences {
        mode: app.view_mode,
        top_most: app.top_most,
    };
    if let Err(error) = state::save_window_preferences(preferences) {
        if !app.status_label.is_null() {
            hold_status(app);
            let text = wide(&format!("置顶设置保存失败。\n{error}"));
            SetWindowTextW(app.status_label, text.as_ptr());
        }
    }
}

/// Flip write access. Enabling shows the consent dialog first and only then
/// restarts the privileged worker with the write flag; disabling drops the
/// UI gate and restarts the worker read-only again.
unsafe fn toggle_write_unlock(app: &mut GuiApp, hwnd: HWND) {
    if app.apply_in_flight || app.policy_in_flight {
        if !app.status_label.is_null() {
            hold_status(app);
            let waiting = wide("正在应用，写入状态稍后再切换。");
            SetWindowTextW(app.status_label, waiting.as_ptr());
        }
        if let Some(controls) = app.simple_controls {
            let waiting = wide("正在应用，请稍候");
            SetWindowTextW(controls.status, waiting.as_ptr());
        }
        InvalidateRect(hwnd, std::ptr::null(), 0);
        return;
    }

    let enabling = !app.write_enabled;
    if enabling {
        let agreed = unlock_dialog::show_unlock_dialog(hwnd, effective_dpi_percent(hwnd));
        if !agreed {
            return;
        }
    }
    app.write_enabled = enabling;
    let _ = state::save_write_unlocked(enabling);

    // The privileged worker decides whether it accepts writes at launch, so
    // the flag change takes effect by replacing the worker this GUI owns.
    let mut note = String::new();
    if app.ui_fixture.is_none() && !app.worker_pipe.is_empty() {
        if app.worker_child.is_some() {
            if let Some(child) = app.worker_child.as_mut() {
                let _ = child.kill();
                let _ = child.wait();
            }
            app.worker_child = None;
            app.worker_error = None;
            app.policy_synced = false;
            let restarted = try_restart_worker(app);
            note = if restarted {
                "后台服务已重启".to_owned()
            } else {
                "后台服务重启失败，请重启应用".to_owned()
            };
        } else {
            note = "后台服务由外部启动，请重启应用后生效".to_owned();
        }
    }

    if let Some(controls) = app.header_controls {
        SendMessageW(
            controls.write,
            BM_SETCHECK,
            usize::from(app.write_enabled),
            0,
        );
        InvalidateRect(controls.write, std::ptr::null(), 0);
    }
    update_write_availability(app, hwnd);
    update_simple_view(app);
    if !app.status_label.is_null() {
        hold_status(app);
        let message = if app.write_enabled {
            let suffix = if note.is_empty() {
                String::new()
            } else {
                format!(" · {note}")
            };
            format!(
                "写入已解锁 · 当前目标 {} W{}",
                app.selected_target.stapm_watts, suffix
            )
        } else {
            let suffix = if note.is_empty() {
                String::new()
            } else {
                format!(" · {note}")
            };
            format!("已重新锁定 · 只读模式{suffix}")
        };
        let text = wide(&message);
        SetWindowTextW(app.status_label, text.as_ptr());
        if let Some(controls) = app.simple_controls {
            let short = if app.write_enabled {
                "写入已解锁"
            } else {
                "已切换为只读"
            };
            let text = wide(short);
            SetWindowTextW(controls.status, text.as_ptr());
        }
    }
    InvalidateRect(hwnd, std::ptr::null(), 0);
}

unsafe fn save_preset_edits(app: &mut GuiApp) -> Result<(), String> {
    let Some(edits) = app.preset_edits else {
        return Err("预设编辑框尚未创建。".to_owned());
    };
    let (minimum, maximum) = profile_limits(app);
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

fn start_apply(
    hwnd_address: usize,
    pipe_name: String,
    target: PowerLimitTarget,
    fixture: Option<UiFixture>,
) {
    thread::spawn(move || {
        // UI fixtures never touch hardware: simulate the firmware answer so
        // screenshot/video captures show the real apply -> read-back flow.
        let text = match fixture {
            Some(UiFixture::FirmwareClamp) => {
                thread::sleep(Duration::from_millis(500));
                let clamp_note = if target.stapm_watts > 10 {
                    "\n固件报告了钳制或 STAPM 警告。"
                } else {
                    ""
                };
                format!(
                    "已应用 {} W / {} W / {} W。{}",
                    target.stapm_watts, target.fast_watts, target.slow_watts, clamp_note
                )
            }
            Some(_) => {
                thread::sleep(Duration::from_millis(500));
                "应用失败。\n当前界面为夹具状态，未连接硬件 worker。".to_owned()
            }
            None => {
                let result = WorkerClient::new(pipe_name).apply_target(target);
                format_apply_result(target, result)
            }
        };
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
    if let Some(controls) = app.simple_controls {
        set_edit_watts(controls.target_edit, app.preset_watts[index]);
    }
    app.target_edit_dirty = false;
    if let Some(buttons) = app.preset_buttons {
        for (button_index, button) in buttons.into_iter().enumerate() {
            if !button.is_null() {
                SendMessageW(button, BM_SETCHECK, usize::from(button_index == index), 0);
                InvalidateRect(button, std::ptr::null(), 1);
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
    if let Some(controls) = app.simple_controls {
        let text = wide(&format!(
            "正在应用预设 {} · {} W",
            index + 1,
            app.preset_watts[index]
        ));
        SetWindowTextW(controls.status, text.as_ptr());
    }
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
    update_write_availability(app, hwnd);
    start_apply(
        hwnd as usize,
        app.worker_pipe.clone(),
        app.selected_target,
        app.ui_fixture,
    );
}

unsafe fn apply_profile_to_presets(app: &mut GuiApp, hwnd: HWND, profile: &ProfilePayload) {
    let minimum = profile.minimum_watts;
    let maximum = app
        .max_target_watts
        .map(|cap| cap.min(profile.maximum_watts))
        .unwrap_or(profile.maximum_watts);
    if minimum > maximum {
        return;
    }
    let changed = app.profile.as_ref().is_none_or(|previous| {
        previous.id != profile.id
            || previous.minimum_watts != profile.minimum_watts
            || previous.maximum_watts != profile.maximum_watts
    });
    app.profile = Some(profile.clone());
    if changed {
        app.preset_watts = clamp_preset_values(app.preset_watts, minimum, maximum);
        if let Some(index) = app.selected_preset {
            app.selected_target = PowerLimitTarget::uniform(app.preset_watts[index]);
        } else if app.selected_target.stapm_watts < minimum
            || app.selected_target.stapm_watts > maximum
        {
            app.selected_target = PowerLimitTarget::uniform(app.preset_watts[0]);
            app.selected_preset = Some(0);
        }
        if !app.target_edit_dirty {
            if let Some(controls) = app.simple_controls {
                set_edit_watts(controls.target_edit, app.selected_target.stapm_watts);
            }
        }
        refresh_preset_controls(app);
    }

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
    let mut icon = SendMessageW(hwnd, WM_GETICON, ICON_SMALL as usize, 0) as HICON;
    if icon.is_null() {
        icon = LoadIconW(std::ptr::null_mut(), IDI_APPLICATION);
    }
    let mut data = NOTIFYICONDATAW {
        cbSize: size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: TRAY_ICON_ID,
        uFlags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
        uCallbackMessage: WM_APP_TRAY,
        hIcon: icon,
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
    let simple_text = wide("简洁模式");
    let advanced_text = wide("高级模式");
    let topmost_text = wide("窗口置顶");
    let write_text = wide(if app.write_enabled {
        "写入已解锁"
    } else {
        "写入解锁…"
    });
    let exit_text = wide("退出");
    AppendMenuW(menu, MF_STRING, MENU_SHOW, show_text.as_ptr());
    AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
    AppendMenuW(menu, MF_STRING, MENU_SIMPLE_MODE, simple_text.as_ptr());
    AppendMenuW(menu, MF_STRING, MENU_ADVANCED_MODE, advanced_text.as_ptr());
    AppendMenuW(menu, MF_STRING, MENU_TOPMOST, topmost_text.as_ptr());
    AppendMenuW(menu, MF_STRING, MENU_WRITE, write_text.as_ptr());
    CheckMenuItem(
        menu,
        MENU_SIMPLE_MODE as u32,
        if app.view_mode == state::UiMode::Simple {
            MF_CHECKED
        } else {
            MF_UNCHECKED
        },
    );
    CheckMenuItem(
        menu,
        MENU_ADVANCED_MODE as u32,
        if app.view_mode == state::UiMode::Advanced {
            MF_CHECKED
        } else {
            MF_UNCHECKED
        },
    );
    CheckMenuItem(
        menu,
        MENU_TOPMOST as u32,
        if app.top_most {
            MF_CHECKED
        } else {
            MF_UNCHECKED
        },
    );
    CheckMenuItem(
        menu,
        MENU_WRITE as u32,
        if app.write_enabled {
            MF_CHECKED
        } else {
            MF_UNCHECKED
        },
    );
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
        WM_PAINT => {
            paint_window(app, hwnd);
            0
        }
        // The double-buffered WM_PAINT covers the whole client, so erasing to
        // the class brush would only flash a white frame between layouts.
        WM_ERASEBKGND => 1,
        WM_DRAWITEM => {
            let draw = lparam as *const DRAWITEMSTRUCT;
            if !draw.is_null() {
                draw_owner_button(app, &*draw);
            }
            1
        }
        WM_NOTIFY => {
            let notification = lparam as *mut NMHDR;
            if !notification.is_null() && (*notification).code == TTN_GETDISPINFOW {
                let text = match (*notification).idFrom {
                    9001 => app
                        .latest_snapshot
                        .as_ref()
                        .map(|snapshot| snapshot.platform.cpu.processor_name.clone())
                        .unwrap_or_else(|| platform_subtitle(app)),
                    9002 => {
                        let (label, message, _, _) = visible_status(app);
                        format!("{label}\n{message}")
                    }
                    9003 => app
                        .latest_snapshot
                        .as_ref()
                        .map(|snapshot| snapshot.platform.cpu.processor_name.clone())
                        .unwrap_or_default(),
                    9004 => app
                        .latest_snapshot
                        .as_ref()
                        .and_then(|snapshot| snapshot.platform.matched_profile.as_ref())
                        .map(|profile| profile.display_name.clone())
                        .unwrap_or_default(),
                    9005 => format_policy_state(app.latest_policy.as_ref()),
                    _ => String::new(),
                };
                app.tooltip_dynamic = wide(&text);
                (*(lparam as *mut NMTTDISPINFOW)).lpszText = app.tooltip_dynamic.as_mut_ptr();
                return 0;
            }
            DefWindowProcW(hwnd, message, wparam, lparam)
        }
        WM_CTLCOLORSTATIC => {
            let hdc = wparam as windows_sys::Win32::Graphics::Gdi::HDC;
            let control_id = GetDlgCtrlID(lparam as HWND);
            SetBkMode(hdc, TRANSPARENT as i32);
            SetTextColor(hdc, static_text_color(control_id));
            GetStockObject(NULL_BRUSH) as LRESULT
        }
        WM_CTLCOLOREDIT => {
            let hdc = wparam as windows_sys::Win32::Graphics::Gdi::HDC;
            SetBkMode(hdc, TRANSPARENT as i32);
            SetBkColor(hdc, palette().surface);
            SetTextColor(hdc, palette().text);
            surface_brush() as LRESULT
        }
        WM_SYSCOLORCHANGE | WM_SETTINGCHANGE => {
            refresh_high_contrast(app.ui_fixture == Some(UiFixture::HighContrast));
            InvalidateRect(hwnd, std::ptr::null(), 0);
            0
        }
        WM_CLOSE => {
            dispatch(app, hwnd, LifecycleEvent::CloseRequested);
            0
        }
        WM_GETMINMAXINFO => {
            let info = &mut *(lparam as *mut MINMAXINFO);
            let percent = app.dpi_percent.max(1);
            let (minimum_width, minimum_height) = minimum_window_client_size(app.view_mode);
            let (mut width, mut height) = outer_window_size(
                scaled(minimum_width, percent),
                scaled(minimum_height, percent),
                window_dpi(hwnd),
            );
            if app.view_mode == state::UiMode::Advanced {
                width += GetSystemMetricsForDpi(SM_CXVSCROLL, window_dpi(hwnd));
                height += GetSystemMetricsForDpi(SM_CYHSCROLL, window_dpi(hwnd));
            }
            if DPI_FIXTURE_PERCENT.load(Ordering::Relaxed) == 0
                || std::env::var_os("AMD_MOBILE_POWER_WORK_AREA_FIXTURE").is_some()
            {
                if let Some(work) = monitor_work_area(hwnd) {
                    width = width.min(work.right - work.left);
                    height = height.min(work.bottom - work.top);
                }
            }
            info.ptMinTrackSize.x = width;
            info.ptMinTrackSize.y = height;
            0
        }
        WM_VSCROLL => {
            let mut client = RECT::default();
            GetClientRect(hwnd, &mut client);
            let page = unscaled(client.bottom, app.dpi_percent);
            let mut scroll = SCROLLINFO {
                cbSize: size_of::<SCROLLINFO>() as u32,
                fMask: SIF_TRACKPOS,
                ..Default::default()
            };
            GetScrollInfo(hwnd, SB_VERT, &mut scroll);
            let position = match (wparam & 0xFFFF) as i32 {
                SB_TOP => 0,
                SB_BOTTOM => content_height(app.view_mode),
                SB_LINEUP => app.scroll_offset - 32,
                SB_LINEDOWN => app.scroll_offset + 32,
                SB_PAGEUP => page_scroll(app.scroll_offset, page, false),
                SB_PAGEDOWN => page_scroll(app.scroll_offset, page, true),
                SB_THUMBTRACK | SB_THUMBPOSITION => scroll.nTrackPos,
                _ => app.scroll_offset,
            };
            set_scroll_offset(app, hwnd, position);
            0
        }
        WM_MOUSEWHEEL => {
            let delta = ((wparam >> 16) as u16 as i16) as i32;
            // 48 logical px per notch with fractional deltas preserved:
            // a precision touchpad reports 30/60 instead of 120 per notch.
            let step = delta * 2 / 5;
            if app.view_mode == state::UiMode::Advanced && GetKeyState(VK_SHIFT as i32) < 0 {
                set_scroll_offsets(app, hwnd, app.scroll_offset_x - step, app.scroll_offset);
            } else {
                set_scroll_offsets(app, hwnd, app.scroll_offset_x, app.scroll_offset - step);
            }
            0
        }
        WM_HSCROLL if app.view_mode == state::UiMode::Advanced => {
            let mut client = RECT::default();
            GetClientRect(hwnd, &mut client);
            let page = unscaled(client.right, app.dpi_percent);
            let mut scroll = SCROLLINFO {
                cbSize: size_of::<SCROLLINFO>() as u32,
                fMask: SIF_TRACKPOS,
                ..Default::default()
            };
            GetScrollInfo(hwnd, SB_HORZ, &mut scroll);
            let position = match (wparam & 0xFFFF) as i32 {
                SB_LEFT => 0,
                SB_RIGHT => ADVANCED_CONTENT_WIDTH,
                SB_LINELEFT => app.scroll_offset_x - 32,
                SB_LINERIGHT => app.scroll_offset_x + 32,
                SB_PAGELEFT => page_scroll(app.scroll_offset_x, page, false),
                SB_PAGERIGHT => page_scroll(app.scroll_offset_x, page, true),
                SB_THUMBTRACK | SB_THUMBPOSITION => scroll.nTrackPos,
                _ => app.scroll_offset_x,
            };
            set_scroll_offsets(app, hwnd, position, app.scroll_offset);
            0
        }
        WM_DPICHANGED => {
            let fixture = DPI_FIXTURE_PERCENT.load(Ordering::Relaxed);
            if fixture > 0 {
                app.dpi_percent = fixture;
                refresh_control_fonts(app);
                layout_mode_controls(app, hwnd);
                return 0;
            }
            let new_dpi = (wparam & 0xFFFF) as u32;
            app.dpi_percent = dpi_percent(if new_dpi == 0 {
                window_dpi(hwnd)
            } else {
                new_dpi
            });
            refresh_control_fonts(app);
            let suggested = lparam as *const RECT;
            if !suggested.is_null() {
                let suggested = &*suggested;
                SetWindowPos(
                    hwnd,
                    std::ptr::null_mut(),
                    suggested.left,
                    suggested.top,
                    suggested.right - suggested.left,
                    suggested.bottom - suggested.top,
                    SWP_NOZORDER | SWP_NOACTIVATE,
                );
            }
            layout_mode_controls(app, hwnd);
            0
        }
        WM_SIZE => {
            match wparam as u32 {
                SIZE_MINIMIZED => {
                    dispatch(app, hwnd, LifecycleEvent::WindowMinimized);
                }
                SIZE_RESTORED => {
                    dispatch(app, hwnd, LifecycleEvent::WindowShown);
                    if app.fonts.is_some() {
                        layout_mode_controls(app, hwnd);
                    }
                }
                // Maximizing or snapping changes the viewport without a
                // SIZE_RESTORED message; re-layout so the scroll offset is
                // clamped to the new content/viewport delta.
                SIZE_MAXIMIZED if app.fonts.is_some() => {
                    layout_mode_controls(app, hwnd);
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
                let display_text = match (&update.snapshot, app.view_mode) {
                    (Some(snapshot), state::UiMode::Simple) => {
                        format_snapshot_simple(snapshot, update.policy.as_ref())
                    }
                    _ => update.text.clone(),
                };
                if !app.status_label.is_null() && Instant::now() >= app.status_hold_until {
                    let text = wide(&display_text);
                    SetWindowTextW(app.status_label, text.as_ptr());
                }
                if let Some(profile) = &update.profile {
                    apply_profile_to_presets(app, hwnd, profile);
                }
                app.latest_snapshot = update.snapshot;
                app.latest_policy = update.policy;
                app.worker_error = update.worker_error;
                // A freshly (re)started worker has no policy settings and no
                // policy ticker; hand it the saved policy once it reports a
                // healthy snapshot so auto switching survives restarts.
                if !app.policy_synced
                    && app.write_enabled
                    && app.worker_error.is_none()
                    && !app.policy_in_flight
                    && app.ui_fixture.is_none()
                {
                    app.policy_synced = true;
                    if let Some(settings) = state::load_power_policy() {
                        if settings.enabled {
                            app.policy_in_flight = true;
                            start_policy_save(hwnd as usize, app.worker_pipe.clone(), settings);
                        }
                    }
                }
                update_simple_view(app);
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            0
        }
        WM_APP_FORCE_RESTART_WORKER => {
            let live_pid = match app.worker_child.as_mut() {
                Some(child) => match child.try_wait() {
                    Ok(None) => Some(child.id()),
                    Ok(Some(_)) | Err(_) => {
                        app.worker_child = None;
                        None
                    }
                },
                None => None,
            };
            if app.ui_fixture.is_none() {
                if live_pid.is_none() {
                    // The worker already exited; replace it now instead of
                    // waiting for the monitor's restart backoff.
                    if try_restart_worker(app) {
                        app.policy_profile_applied = false;
                        app.policy_in_flight = false;
                    }
                } else if !app.force_restart_in_flight.swap(true, Ordering::SeqCst) {
                    // A worker that stopped answering may still be alive, so
                    // the regular restart path would refuse to replace it.
                    // Kill and wait off the UI thread: a driver-bound worker
                    // must not freeze the window while it is replaced.
                    let hwnd_address = hwnd as usize;
                    let pid = live_pid.unwrap_or_default();
                    thread::spawn(move || {
                        terminate_process_bounded(pid, Duration::from_secs(15));
                        unsafe {
                            PostMessageW(hwnd_address as HWND, WM_APP_FORCE_RESTART_READY, 0, 0);
                        }
                    });
                }
            }
            0
        }
        WM_APP_FORCE_RESTART_READY => {
            app.force_restart_in_flight.store(false, Ordering::SeqCst);
            if app.ui_fixture.is_none() && try_restart_worker(app) {
                // A fresh worker starts with an empty policy; force the next
                // refresh to re-push the saved battery/AC targets.
                app.policy_profile_applied = false;
                app.policy_in_flight = false;
            }
            0
        }
        WM_APP_RESTART_WORKER => {
            if try_restart_worker(app) {
                // A fresh worker starts with an empty policy. Force the next
                // profile refresh to push the saved battery/AC policy again,
                // otherwise automatic switching would silently stop after a
                // crash even though the last hardware limits persist.
                app.policy_profile_applied = false;
                app.policy_in_flight = false;
            }
            0
        }
        WM_APP_APPLY_RESULT => {
            app.apply_in_flight = false;
            let pointer = lparam as *mut String;
            if !pointer.is_null() {
                let text = Box::from_raw(pointer);
                hold_status(app);
                // Firmware-clamp fixture: fold the simulated apply back into
                // the displayed telemetry so captures show a consistent
                // apply -> read-back story (STAPM stays clamped at 10 W).
                if app.ui_fixture == Some(UiFixture::FirmwareClamp) {
                    if let Some(snapshot) = app.latest_snapshot.as_mut() {
                        let applied = app.selected_target;
                        let stapm_ceiling = 10.0_f64;
                        let fast = applied.fast_watts as f64;
                        let slow = applied.slow_watts as f64;
                        let stapm = (applied.stapm_watts as f64).min(stapm_ceiling);
                        snapshot.telemetry.target_watts = Some(applied.stapm_watts as f64);
                        snapshot.telemetry.fast_value_watts = Some(fast);
                        snapshot.telemetry.fast_limit_watts = Some(fast);
                        snapshot.telemetry.slow_value_watts = Some(slow);
                        snapshot.telemetry.slow_limit_watts = Some(slow);
                        snapshot.telemetry.stapm_value_watts = Some(stapm + 0.02);
                        snapshot.telemetry.stapm_limit_watts = Some(stapm_ceiling);
                        snapshot.telemetry.has_firmware_clamp =
                            (applied.stapm_watts as f64) > stapm_ceiling;
                    }
                }
                if let Some(controls) = app.simple_controls {
                    let message = text.lines().next().unwrap_or(text.as_str());
                    let message = wide(message);
                    SetWindowTextW(controls.status, message.as_ptr());
                }
                if !app.status_label.is_null() {
                    let wide_text = wide(&text);
                    SetWindowTextW(app.status_label, wide_text.as_ptr());
                }
                update_simple_view(app);
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            0
        }
        WM_APP_POLICY_RESULT => {
            app.policy_in_flight = false;
            let pointer = lparam as *mut String;
            if !pointer.is_null() {
                let text = Box::from_raw(pointer);
                hold_status(app);
                if let Some(controls) = app.simple_controls {
                    let message = text.lines().next().unwrap_or(text.as_str());
                    let message = wide(message);
                    SetWindowTextW(controls.status, message.as_ptr());
                }
                if !app.status_label.is_null() {
                    let wide_text = wide(&text);
                    SetWindowTextW(app.status_label, wide_text.as_ptr());
                }
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            0
        }
        WM_COMMAND => {
            let command = wparam & 0xFFFF;
            let notification = (wparam >> 16) & 0xFFFF;
            if notification == 0x0100 || notification == 0x0006 {
                app.focused_control = Some(command);
                reveal_control(app, hwnd, lparam as HWND);
                InvalidateRect(hwnd, std::ptr::null(), 0);
            } else if (notification == 0x0200 || notification == 0x0007)
                && app.focused_control == Some(command)
            {
                app.focused_control = None;
                InvalidateRect(hwnd, std::ptr::null(), 0);
            }
            if notification == 0x0300 && command == SIMPLE_TARGET_EDIT {
                let expected = app.selected_target.stapm_watts.to_string();
                if get_control_text(lparam as HWND).trim() != expected {
                    app.target_edit_dirty = true;
                    app.selected_preset = None;
                    if let Some(buttons) = app.preset_buttons {
                        for button in buttons {
                            InvalidateRect(button, std::ptr::null(), 0);
                        }
                    }
                }
            }
            // Edit/focus notifications share WM_COMMAND with clicks. Only
            // BN_CLICKED (or a menu command) is allowed to perform an action.
            if notification != 0 {
                return 0;
            }
            match command {
                MENU_SHOW => {
                    dispatch(app, hwnd, LifecycleEvent::TrayShowRequested);
                }
                MENU_EXIT => {
                    dispatch(app, hwnd, LifecycleEvent::TrayExitRequested);
                }
                MENU_SIMPLE_MODE | SIMPLE_MODE => {
                    apply_view_mode(app, hwnd, state::UiMode::Simple);
                }
                MENU_ADVANCED_MODE | ADVANCED_MODE => {
                    apply_view_mode(app, hwnd, state::UiMode::Advanced);
                }
                PRESET_EDIT_OPEN => {
                    apply_view_mode(app, hwnd, state::UiMode::Advanced);
                    let edit = GetDlgItem(hwnd, PRESET_EDIT_START as i32);
                    if !edit.is_null() {
                        SetFocus(edit);
                        SendMessageW(edit, 0x00B1, 0, -1);
                    }
                }
                MENU_TOPMOST | TOPMOST_TOGGLE => {
                    toggle_topmost(app, hwnd);
                }
                MENU_WRITE | WRITE_UNLOCK => {
                    toggle_write_unlock(app, hwnd);
                }
                POLICY_ENABLED if app.write_enabled => {
                    app.policy_enabled = !app.policy_enabled;
                    if let Some(controls) = app.policy_controls {
                        InvalidateRect(controls.enabled, std::ptr::null(), 1);
                    }
                }
                POLICY_BATTERY_ONLY if app.write_enabled => {
                    app.battery_only = !app.battery_only;
                    if let Some(controls) = app.policy_controls {
                        InvalidateRect(controls.battery_only, std::ptr::null(), 1);
                    }
                }
                SIMPLE_APPLY if app.write_enabled && !app.apply_in_flight => {
                    if let Some(controls) = app.simple_controls {
                        let (minimum, maximum) = profile_limits(app);
                        let target = read_edit_watts(
                            controls.target_edit,
                            app.selected_target.stapm_watts,
                            minimum,
                            maximum,
                        );
                        set_edit_watts(controls.target_edit, target);
                        app.target_edit_dirty = false;
                        app.selected_preset =
                            app.preset_watts.iter().position(|value| *value == target);
                        app.selected_target = PowerLimitTarget::uniform(target);
                        app.apply_in_flight = true;
                        let status = wide(&format!("正在应用 {target} W"));
                        SetWindowTextW(controls.status, status.as_ptr());
                        if !app.status_label.is_null() {
                            let text = wide(&format!("正在应用 {target} W…"));
                            SetWindowTextW(app.status_label, text.as_ptr());
                        }
                        update_write_availability(app, hwnd);
                        InvalidateRect(hwnd, std::ptr::null(), 0);
                        start_apply(
                            hwnd as usize,
                            app.worker_pipe.clone(),
                            app.selected_target,
                            app.ui_fixture,
                        );
                    }
                }
                PRESET_12 | PRESET_25 | PRESET_45 if app.write_enabled => {
                    let preset_index = match command {
                        PRESET_12 => 0,
                        PRESET_25 => 1,
                        PRESET_45 => 2,
                        _ => 0,
                    };
                    // Presets are one-click in both modes: apply immediately
                    // like the simple-mode hero row instead of only staging
                    // the target field.
                    start_preset_apply(app, hwnd, preset_index);
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
                    if let Some(controls) = app.simple_controls {
                        let first_line = message.lines().next().unwrap_or("快捷预设");
                        let text = wide(first_line);
                        SetWindowTextW(controls.status, text.as_ptr());
                    }
                    if !app.status_label.is_null() {
                        hold_status(app);
                        let text = wide(&message);
                        SetWindowTextW(app.status_label, text.as_ptr());
                    }
                }
                EXPORT_DIAGNOSTICS => {
                    let message = match export_diagnostics(app) {
                        Ok(path) => format!("诊断已导出：\n{}", path.display()),
                        Err(error) => format!("诊断导出失败。\n{error}"),
                    };
                    if let Some(controls) = app.simple_controls {
                        let first_line = message.lines().next().unwrap_or("诊断导出");
                        let text = wide(first_line);
                        SetWindowTextW(controls.status, text.as_ptr());
                    }
                    if !app.status_label.is_null() {
                        hold_status(app);
                        let text = wide(&message);
                        SetWindowTextW(app.status_label, text.as_ptr());
                    }
                }
                APPLY_TARGET if app.write_enabled && !app.apply_in_flight => {
                    app.apply_in_flight = true;
                    if !app.status_label.is_null() {
                        hold_status(app);
                        let text = wide(&format!(
                            "正在应用 {} W / {} W / {} W…",
                            app.selected_target.stapm_watts,
                            app.selected_target.fast_watts,
                            app.selected_target.slow_watts
                        ));
                        SetWindowTextW(app.status_label, text.as_ptr());
                    }
                    update_write_availability(app, hwnd);
                    start_apply(
                        hwnd as usize,
                        app.worker_pipe.clone(),
                        app.selected_target,
                        app.ui_fixture,
                    );
                }
                POLICY_SAVE if app.write_enabled && !app.policy_in_flight => {
                    if let Some(controls) = app.policy_controls {
                        let (minimum, maximum) = profile_limits(app);
                        let battery_target =
                            read_edit_watts(controls.battery_target, 12, minimum, maximum);
                        let ac_target = read_edit_watts(controls.ac_target, 45, minimum, maximum);
                        set_edit_watts(controls.battery_target, battery_target);
                        set_edit_watts(controls.ac_target, ac_target);
                        let settings = PowerPolicySettings {
                            enabled: app.policy_enabled,
                            battery_enabled: true,
                            ac_enabled: !app.battery_only,
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
                        InvalidateRect(hwnd, std::ptr::null(), 0);
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
    DPI_FIXTURE_PERCENT.store(options.dpi_fixture.unwrap_or(0), Ordering::Relaxed);
    // The manifest declares PerMonitorV2, but setting it explicitly also covers
    // launches whose manifest could not be applied and keeps DPI awareness on.
    unsafe {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }
    refresh_high_contrast(options.ui_fixture == Some(UiFixture::HighContrast));
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
        hbrBackground: std::ptr::null_mut(),
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

    let initial_mode = options
        .mode_override
        .unwrap_or_else(|| state::load_window_preferences().mode);
    let client_size = match initial_mode {
        state::UiMode::Simple => SIMPLE_CLIENT_SIZE,
        state::UiMode::Advanced => ADVANCED_CLIENT_SIZE,
    };
    let system_dpi = unsafe {
        let dpi = GetDpiForSystem();
        if dpi == 0 {
            BASE_DPI as u32
        } else {
            dpi
        }
    };
    let system_percent = options
        .dpi_fixture
        .unwrap_or_else(|| dpi_percent(system_dpi));
    let (outer_width, outer_height) = unsafe {
        outer_window_size(
            scaled(client_size.0, system_percent),
            scaled(client_size.1, system_percent),
            system_dpi,
        )
    };
    let hwnd = unsafe {
        CreateWindowExW(
            WS_EX_APPWINDOW,
            class_name.as_ptr(),
            window_title.as_ptr(),
            APP_WINDOW_STYLE,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            outer_width,
            outer_height,
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
    unsafe {
        let dark_titlebar = 1i32;
        DwmSetWindowAttribute(
            hwnd,
            20,
            &dark_titlebar as *const i32 as *const std::ffi::c_void,
            size_of::<i32>() as u32,
        );
    }

    let app = Box::into_raw(Box::new(GuiApp::new(mutex, options.mode_override)));
    unsafe {
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, app as isize);
        // The launch flag stays authoritative for scripts and fixtures; a
        // persisted unlock from the consent dialog also survives restarts.
        (*app).write_enabled = options.enable_write_controls || state::load_write_unlocked();
        if let Some(cap) = options.max_target_watts {
            (*app).max_target_watts = Some(cap);
            let _ = state::save_max_target_watts(cap);
            if (*app).preset_watts.iter().any(|watts| *watts > cap) {
                let lower = cap.saturating_sub(2).max(1);
                (*app).preset_watts = [lower, cap, cap];
                let _ = state::save_presets((*app).preset_watts);
            }
        }
        if let Some(watts) = options.uniform_target_watts {
            let settings = uniform_power_policy(watts);
            (*app).saved_policy = Some(settings);
            (*app).policy_enabled = true;
            (*app).battery_only = false;
            (*app).preset_watts = [watts; 3];
            (*app).selected_preset = Some(0);
            (*app).selected_target = PowerLimitTarget::uniform(watts);
            let _ = state::save_power_policy(settings);
            let _ = state::save_presets((*app).preset_watts);
        }
        let window_percent = effective_dpi_percent(hwnd);
        (*app).dpi_percent = window_percent;
        let icon_large = create_icon_for_size(scaled(32, window_percent));
        let icon_small = create_icon_for_size(scaled(16, window_percent));
        (*app).icon_large = if icon_large.is_null() {
            LoadIconW(std::ptr::null_mut(), IDI_APPLICATION)
        } else {
            icon_large
        };
        (*app).icon_small = if icon_small.is_null() {
            (*app).icon_large
        } else {
            icon_small
        };
        SendMessageW(
            hwnd,
            WM_SETICON,
            ICON_BIG as usize,
            (*app).icon_large as isize,
        );
        SendMessageW(
            hwnd,
            WM_SETICON,
            ICON_SMALL as usize,
            (*app).icon_small as isize,
        );
        let fonts = create_ui_fonts(window_percent);
        let title = create_title_label(hwnd, instance);
        set_control_font(title, fonts.title);
        (*app).header_controls = Some(create_header_controls(
            hwnd,
            instance,
            (*app).view_mode,
            (*app).top_most,
            (*app).write_enabled,
        ));
        (*app).status_label = create_status_label(hwnd, instance);
        set_control_font((*app).status_label, fonts.body);
        (*app).simple_controls = Some(create_simple_controls(
            hwnd,
            instance,
            &fonts,
            options.enable_write_controls,
        ));
        (*app).preset_buttons = Some(create_action_buttons(hwnd, instance, (*app).preset_watts));
        (*app).preset_edits = Some(create_preset_controls(hwnd, instance, (*app).preset_watts));
        let _ = create_export_button(hwnd, instance, 528, 384, 88);
        (*app).policy_controls = Some(create_policy_controls(hwnd, instance));
        initialize_control_feedback(&mut *app, hwnd, instance);
        if let Some(edits) = (*app).preset_edits {
            for edit in edits {
                set_control_font(edit, fonts.metric);
            }
        }
        if let Some(controls) = (*app).policy_controls {
            set_control_font(controls.battery_target, fonts.metric);
            set_control_font(controls.ac_target, fonts.metric);
        }
        if options.uniform_target_watts.is_none() {
            (*app).saved_policy = state::load_power_policy();
        }
        if let Some(saved) = (*app).saved_policy {
            (*app).policy_enabled = saved.enabled;
            (*app).battery_only = saved.battery_enabled && !saved.ac_enabled;
            if let Some(controls) = (*app).policy_controls {
                set_edit_watts(controls.battery_target, saved.battery_target.stapm_watts);
                set_edit_watts(controls.ac_target, saved.ac_target.stapm_watts);
            }
        }
        if let Some(controls) = (*app).simple_controls {
            set_edit_watts(controls.target_edit, (*app).selected_target.stapm_watts);
        }
        (*app).fonts = Some(fonts);
        apply_topmost_style(hwnd, (*app).top_most);
        apply_view_mode(&mut *app, hwnd, (*app).view_mode);
        let initial_watts = options
            .uniform_target_watts
            .unwrap_or((*app).preset_watts[0]);
        let initial_watts = (*app)
            .max_target_watts
            .map(|cap| initial_watts.min(cap))
            .unwrap_or(initial_watts)
            .max(1);
        (*app).selected_preset = Some(0);
        (*app).selected_target = PowerLimitTarget::uniform(initial_watts);
        set_edit_watts(GetDlgItem(hwnd, SIMPLE_TARGET_EDIT as i32), initial_watts);
    }

    if let Some(fixture) = options.ui_fixture {
        unsafe {
            apply_ui_fixture(&mut *app, hwnd, fixture);
        }
    } else {
        match start_worker(&options) {
            Ok(child) => unsafe {
                (*app).worker_child = child;
                (*app).worker_pipe = options.pipe_name.clone();
                (*app).worker_executable = worker_executable_path(&options);
            },
            Err(error) => unsafe {
                let text = wide(&format!("Worker start failed\n{error}"));
                SetWindowTextW((*app).status_label, text.as_ptr());
                (*app).worker_pipe = options.pipe_name.clone();
                (*app).worker_executable = worker_executable_path(&options);
            },
        }
        let monitor = start_worker_monitor(
            hwnd as usize,
            options.pipe_name.clone(),
            unsafe { (*app).stop_monitor.clone() },
            unsafe { (*app).monitor_heartbeat.clone() },
        );
        let _watchdog = start_worker_watchdog(
            hwnd as usize,
            unsafe { (*app).monitor_heartbeat.clone() },
            unsafe { (*app).stop_monitor.clone() },
        );
        unsafe {
            (*app).monitor_thread = Some(monitor);
        }
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
        if unsafe { IsDialogMessageW(hwnd, &message) } != 0 {
            continue;
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
    use super::{
        clamp_preset_values, clamp_to_ceiling, diagnostics_document, fixture_snapshot,
        fixture_worker_error, format_policy_state, format_snapshot, format_snapshot_simple,
        format_writable_fields, parse_arguments, parse_ui_fixture, preset_menu_label,
        restart_delay, rgb, state, terminate_process_bounded, uniform_power_policy,
        watchdog_should_restart, UiDiagnostics, UiFixture, HIGH_CONTRAST_PALETTE,
    };
    use amd_mobile_power_gui::worker::{
        CpuPayload, LimitsPayload, PlatformPayload, PowerLimitTarget, PowerLineState,
        PowerPolicySettings, PowerPolicyState, ProfilePayload, SnapshotPayload, TelemetryPayload,
    };
    use std::process::{Command, Stdio};
    use std::time::Duration;

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
        assert!(text.contains("支持写入：STAPM / Fast / Slow"), "{text}");
        assert!(!text.contains("Worker: connected"), "{text}");
        assert!(!text.contains("Power source"), "{text}");
    }

    #[test]
    fn writable_field_summary_lists_only_supported_limits() {
        assert_eq!(
            format_writable_fields(true, true, true),
            "STAPM / Fast / Slow"
        );
        assert_eq!(format_writable_fields(true, false, true), "STAPM / Slow");
        assert_eq!(format_writable_fields(false, false, false), "无");
    }

    #[test]
    fn worker_restart_backoff_is_bounded() {
        assert_eq!(restart_delay(0), Duration::from_secs(5));
        assert_eq!(restart_delay(1), Duration::from_secs(10));
        assert_eq!(restart_delay(2), Duration::from_secs(20));
        assert_eq!(restart_delay(3), Duration::from_secs(40));
        assert_eq!(restart_delay(4), Duration::from_secs(60));
        assert_eq!(restart_delay(12), Duration::from_secs(60));
    }

    #[test]
    fn watchdog_restarts_only_after_six_stalled_checks() {
        assert!(!watchdog_should_restart(0));
        assert!(!watchdog_should_restart(5));
        assert!(watchdog_should_restart(6));
        assert!(watchdog_should_restart(60));
    }

    #[test]
    fn bounded_terminate_reaps_a_long_running_child() {
        let mut child = Command::new("cmd")
            .args(["/c", "ping", "-n", "60", "127.0.0.1"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn a long-running child");
        let pid = child.id();

        assert!(terminate_process_bounded(pid, Duration::from_secs(10)));
        let status = child.wait().expect("reap the terminated child");
        assert!(!status.success());
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
                battery_enabled: true,
                ac_enabled: true,
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
            text.contains("自动策略：已启用（电池 10 W / 外接 12 W）"),
            "{text}"
        );
        assert!(text.contains("上次应用：电池 · 成功"), "{text}");
    }

    #[test]
    fn missing_policy_surfaces_chinese_placeholder() {
        assert_eq!(format_policy_state(None), "自动策略：不可用");
    }

    #[test]
    fn battery_only_policy_is_explicit_in_the_dashboard() {
        let state = PowerPolicyState {
            settings: Some(PowerPolicySettings {
                enabled: true,
                battery_enabled: true,
                ac_enabled: false,
                battery_target: PowerLimitTarget::uniform(10),
                ac_target: PowerLimitTarget::uniform(45),
            }),
            last_observed_power_line: Some(PowerLineState::Battery),
            last_applied_target: Some(PowerLimitTarget::uniform(10)),
            last_attempt_at: None,
            last_attempt_succeeded: Some(true),
            last_error: None,
        };

        let text = format_policy_state(Some(&state));

        assert!(
            text.contains("自动策略：已启用（仅电池 10 W（外接不控制））"),
            "{text}"
        );
    }

    #[test]
    fn presets_are_clamped_to_the_active_profile() {
        assert_eq!(clamp_preset_values([2, 25, 80], 5, 60), [5, 25, 60]);
    }

    #[test]
    fn high_contrast_palette_is_polarized() {
        assert_eq!(HIGH_CONTRAST_PALETTE.canvas, rgb(0, 0, 0));
        assert_eq!(HIGH_CONTRAST_PALETTE.text, rgb(255, 255, 255));
        assert_eq!(HIGH_CONTRAST_PALETTE.accent, rgb(255, 255, 0));
        assert_eq!(HIGH_CONTRAST_PALETTE.on_accent, rgb(0, 0, 0));
    }

    #[test]
    fn tray_preset_labels_include_their_editable_value() {
        assert_eq!(preset_menu_label(0, 10), "应用预设 1：10 W");
        assert_eq!(preset_menu_label(2, 43), "应用预设 3：43 W");
    }

    #[test]
    fn diagnostics_export_is_versioned_and_sanitized() {
        let snapshot = sample_snapshot();
        let policy = PowerPolicyState {
            settings: Some(PowerPolicySettings {
                enabled: true,
                battery_enabled: true,
                ac_enabled: true,
                battery_target: PowerLimitTarget::uniform(10),
                ac_target: PowerLimitTarget::uniform(12),
            }),
            last_observed_power_line: Some(PowerLineState::Ac),
            last_applied_target: Some(PowerLimitTarget::uniform(12)),
            last_attempt_at: Some("2026-11-11T00:00:00Z".to_owned()),
            last_attempt_succeeded: Some(true),
            last_error: None,
        };
        let document = diagnostics_document(
            &snapshot,
            Some(&policy),
            false,
            Some("0.6.0-native-test"),
            1_762_819_200_000,
            UiDiagnostics {
                mode: state::UiMode::Advanced,
                top_most: true,
                policy_enabled: true,
                battery_only: false,
                high_contrast: false,
                taskbar_icon_available: true,
                tray_icon_id: 1,
                dpi_percent: 125,
                dpi_fixture_percent: Some(150),
            },
        );
        let text = serde_json::to_string_pretty(&document).unwrap();

        assert_eq!(document["schemaVersion"], 1);
        assert_eq!(document["packageVersion"], "0.6.0-native-test");
        assert_eq!(document["ui"]["mode"], "advanced");
        assert_eq!(document["ui"]["topMost"], true);
        assert_eq!(document["ui"]["policyEnabled"], true);
        assert_eq!(document["ui"]["batteryOnly"], false);
        assert_eq!(document["ui"]["highContrast"], false);
        assert_eq!(document["ui"]["taskbarIconAvailable"], true);
        assert_eq!(document["ui"]["trayIconId"], 1);
        assert_eq!(document["ui"]["dpiPercent"], 125);
        assert_eq!(document["ui"]["dpiFixturePercent"], 150);
        assert_eq!(
            document["snapshot"]["platform"]["cpu"]["processorName"],
            "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics"
        );
        assert_eq!(
            document["powerPolicy"]["settings"]["batteryTarget"]["stapmWatts"],
            10
        );
        assert_eq!(document["privacy"]["containsLocalPaths"], false);
        assert_eq!(document["privacy"]["uploaded"], false);
        assert!(!text.contains(r"\\.\pipe\"));
        assert!(!text.contains(r"C:\"));
    }

    #[test]
    fn ui_fixtures_cover_failure_states_without_hardware() {
        assert_eq!(
            parse_ui_fixture("firmware-clamp"),
            Ok(UiFixture::FirmwareClamp)
        );
        assert_eq!(
            parse_ui_fixture("unsupported-platform"),
            Ok(UiFixture::UnsupportedPlatform)
        );
        assert_eq!(
            parse_ui_fixture("high-contrast"),
            Ok(UiFixture::HighContrast)
        );
        assert!(parse_ui_fixture("unknown").is_err());

        let clamp = fixture_snapshot(UiFixture::FirmwareClamp).unwrap();
        assert!(clamp.platform.is_supported);
        assert!(clamp.telemetry.has_firmware_clamp);
        assert_eq!(clamp.telemetry.stapm_limit_watts, Some(10.0));
        assert_eq!(clamp.telemetry.fast_limit_watts, Some(12.0));

        let unsupported = fixture_snapshot(UiFixture::UnsupportedPlatform).unwrap();
        assert!(!unsupported.platform.is_supported);
        assert!(unsupported.platform.matched_profile.is_none());

        let high_contrast = fixture_snapshot(UiFixture::HighContrast).unwrap();
        assert!(high_contrast.platform.is_supported);
        assert!(!high_contrast.telemetry.has_firmware_clamp);
        assert_eq!(high_contrast.telemetry.stapm_limit_watts, Some(12.0));
        assert!(unsupported.platform.unsupported_reason.is_some());

        let offline = fixture_worker_error(UiFixture::WorkerOffline).unwrap();
        assert!(offline.starts_with("worker 离线："));
        let long_error = fixture_worker_error(UiFixture::LongError).unwrap();
        assert!(long_error.lines().next().unwrap().contains("重启 Windows"));
    }

    #[test]
    fn simple_dashboard_keeps_the_live_values_visible() {
        let text = format_snapshot_simple(&sample_snapshot(), None);

        assert!(text.contains("已连接 worker · 电池"), "{text}");
        assert!(text.contains("10.00 W / 10.00 W / 10.00 W"), "{text}");
        assert!(text.contains("目标功耗：10.00 W"), "{text}");
        assert!(text.contains("CPU：44.9 °C"), "{text}");
        assert!(!text.contains("PM 表"), "{text}");
    }

    fn to_arguments(tokens: &[&str]) -> Vec<String> {
        tokens.iter().map(|token| (*token).to_owned()).collect()
    }

    #[test]
    fn desktop_shortcut_arguments_are_accepted() {
        let options = parse_arguments(to_arguments(&["--enable-write-controls", "--simple-mode"]))
            .expect("桌面快捷方式参数必须被接受");

        assert!(options.enable_write_controls);
        assert_eq!(options.mode_override, Some(state::UiMode::Simple));
        assert!(!options.start_hidden);
    }

    #[test]
    fn advanced_mode_override_is_accepted() {
        let options =
            parse_arguments(to_arguments(&["--advanced-mode"])).expect("高级模式参数必须被接受");
        assert_eq!(options.mode_override, Some(state::UiMode::Advanced));
    }

    #[test]
    fn unknown_arguments_are_rejected() {
        assert!(parse_arguments(to_arguments(&["--no-such-flag"])).is_err());
    }

    #[test]
    fn max_target_watts_argument_is_accepted_and_bounded() {
        let options = parse_arguments(to_arguments(&["--max-target-watts", "12"]))
            .expect("上限参数必须被接受");
        assert_eq!(options.max_target_watts, Some(12));
        assert!(parse_arguments(to_arguments(&["--max-target-watts", "0"])).is_err());
        assert!(parse_arguments(to_arguments(&["--max-target-watts", "abc"])).is_err());
        assert!(parse_arguments(to_arguments(&["--max-target-watts"])).is_err());
    }

    #[test]
    fn uniform_target_watts_sets_both_power_lines_and_respects_the_ceiling() {
        let options = parse_arguments(to_arguments(&[
            "--max-target-watts",
            "10",
            "--uniform-target-watts",
            "10",
        ]))
        .expect("统一目标参数必须被接受");
        let policy = uniform_power_policy(options.uniform_target_watts.unwrap());

        assert!(policy.enabled);
        assert!(policy.battery_enabled);
        assert!(policy.ac_enabled);
        assert_eq!(policy.battery_target, PowerLimitTarget::uniform(10));
        assert_eq!(policy.ac_target, PowerLimitTarget::uniform(10));
        assert!(parse_arguments(to_arguments(&[
            "--max-target-watts",
            "10",
            "--uniform-target-watts",
            "12",
        ]))
        .is_err());
        assert!(parse_arguments(to_arguments(&["--uniform-target-watts", "0"])).is_err());
    }

    #[test]
    fn dpi_fixture_only_accepts_supported_render_scales() {
        for scale in ["100", "125", "150", "200"] {
            let options = parse_arguments(to_arguments(&["--dpi-fixture", scale]))
                .expect("支持的 DPI 夹具必须被接受");
            assert_eq!(options.dpi_fixture, Some(scale.parse().unwrap()));
        }
        assert!(parse_arguments(to_arguments(&["--dpi-fixture", "120"])).is_err());
        assert!(parse_arguments(to_arguments(&["--dpi-fixture"])).is_err());
    }

    #[test]
    fn ceiling_clamps_every_preset_without_raising_values() {
        assert_eq!(clamp_to_ceiling([10, 12, 45], Some(12)), [10, 12, 12]);
        assert_eq!(clamp_to_ceiling([5, 6, 7], Some(12)), [5, 6, 7]);
        assert_eq!(clamp_to_ceiling([10, 12, 45], None), [10, 12, 45]);
    }

    #[test]
    fn cli_contract_matches_parser() {
        let contract_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("native 目录")
            .join("gui-cli-contract.json");
        let contents = std::fs::read_to_string(&contract_path)
            .unwrap_or_else(|error| panic!("读取 {} 失败：{error}", contract_path.display()));
        let contract: serde_json::Value =
            serde_json::from_str(&contents).expect("gui-cli-contract.json 必须是合法 JSON");
        let arguments = contract["arguments"]
            .as_object()
            .expect("契约必须包含 arguments 对象");
        assert!(!arguments.is_empty(), "契约不能为空");

        for (name, spec) in arguments {
            let takes_value = spec["takesValue"]
                .as_bool()
                .unwrap_or_else(|| panic!("{name} 缺少 takesValue 布尔值"));
            let mut argv = vec![name.clone()];
            if takes_value {
                let sample = match name.as_str() {
                    "--ui-fixture" => "high-contrast",
                    "--max-target-watts" => "12",
                    "--uniform-target-watts" => "12",
                    "--dpi-fixture" => "150",
                    _ => "sample-value",
                };
                argv.push(sample.to_owned());
            }
            parse_arguments(argv)
                .unwrap_or_else(|error| panic!("契约参数 {name} 未被解析器接受：{error}"));
        }
    }
}
