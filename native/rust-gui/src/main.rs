#![windows_subsystem = "windows"]

use amd_mobile_power_gui::lifecycle::{
    LifecycleAction, LifecycleEvent, LifecycleState, Transition, WindowVisibility,
};
use std::ffi::c_void;
use std::mem::size_of;
use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, ERROR_ALREADY_EXISTS, HANDLE, HWND, LPARAM, LRESULT, WPARAM,
};
use windows_sys::Win32::Graphics::Gdi::{UpdateWindow, HBRUSH};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Threading::CreateMutexW;
use windows_sys::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NOTIFYICONDATAW,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreatePopupMenu, CreateWindowExW, DefWindowProcW, DestroyMenu, DestroyWindow,
    DispatchMessageW, FindWindowW, GetCursorPos, GetMessageW, GetWindowLongPtrW, LoadCursorW,
    LoadIconW, PostMessageW, PostQuitMessage, RegisterClassExW, SetForegroundWindow,
    SetWindowLongPtrW, ShowWindow, TrackPopupMenu, TranslateMessage, CW_USEDEFAULT,
    CS_HREDRAW, CS_VREDRAW, GWLP_USERDATA, HMENU, IDC_ARROW, IDI_APPLICATION, MF_SEPARATOR,
    MF_STRING, MSG, SIZE_MINIMIZED, SIZE_RESTORED, SW_HIDE, SW_MINIMIZE, SW_RESTORE, SW_SHOWNORMAL,
    TPM_RIGHTBUTTON, WM_APP, WM_CLOSE, WM_COMMAND, WM_CONTEXTMENU, WM_DESTROY, WM_ENDSESSION,
    WM_LBUTTONUP, WM_QUERYENDSESSION, WM_RBUTTONUP, WM_SHOWWINDOW, WM_SIZE, WM_SYSCOMMAND,
    WNDCLASSEXW, WS_EX_APPWINDOW, WS_OVERLAPPEDWINDOW,
};
use windows_sys::Win32::UI::WindowsAndMessaging::SC_MINIMIZE;

const APP_TITLE: &str = "AMD Mobile Power - Rust GUI Preview";
const WINDOW_CLASS: &str = "AmdMobilePower.RustGui.Migration.v1";
const MUTEX_NAME: &str = "Local\\AmdMobilePower.RustGui.Migration.v1";
const TRAY_ICON_ID: u32 = 1;
const WM_APP_WAKE: u32 = WM_APP + 1;
const WM_APP_TRAY: u32 = WM_APP + 2;
const MENU_SHOW: usize = 1;
const MENU_EXIT: usize = 2;

struct GuiApp {
    state: LifecycleState,
    _mutex: HANDLE,
}

impl GuiApp {
    fn new(mutex: HANDLE) -> Self {
        Self {
            state: LifecycleState::default(),
            _mutex: mutex,
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

unsafe fn app_from_window(hwnd: HWND) -> *mut GuiApp {
    GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut GuiApp
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

unsafe fn dispatch(
    app: &mut GuiApp,
    hwnd: HWND,
    event: LifecycleEvent,
) -> Transition {
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
        WM_COMMAND => {
            match wparam & 0xFFFF {
                MENU_SHOW => {
                    dispatch(app, hwnd, LifecycleEvent::TrayShowRequested);
                }
                MENU_EXIT => {
                    dispatch(app, hwnd, LifecycleEvent::TrayExitRequested);
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

    let hwnd = unsafe {
        CreateWindowExW(
            WS_EX_APPWINDOW,
            class_name.as_ptr(),
            window_title.as_ptr(),
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            620,
            360,
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
    }

    let start_hidden = std::env::args().any(|argument| argument == "--tray");
    unsafe {
        dispatch(
            &mut *app,
            hwnd,
            LifecycleEvent::StartupRequested { start_hidden },
        );
        if !start_hidden {
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
