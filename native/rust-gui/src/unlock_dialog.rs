//! Modal "enable write access" consent dialog.
//!
//! The app ships read-only by default. Before writes can be enabled the user
//! must read the liability notice and operating notes and tick the consent
//! checkbox; the confirm button stays disabled until then. The dialog is a
//! plain popup window painted with GDI so it matches the app surface instead
//! of pulling in the comctl32 v6 TaskDialog dependency.

use std::ffi::c_void;
use std::mem::size_of;

use windows_sys::Win32::Foundation::{
    GetLastError, HINSTANCE, HWND, LPARAM, LRESULT, RECT, WPARAM, ERROR_CLASS_ALREADY_EXISTS,
};
use windows_sys::Win32::Graphics::Gdi::{
    BeginPaint, CreateFontW, CreateSolidBrush, DeleteObject, DrawTextW, EndPaint, FillRect,
    RoundRect, SelectObject, SetBkColor, SetBkMode, SetTextColor, HGDIOBJ, HBRUSH, PAINTSTRUCT,
    TRANSPARENT, DT_CENTER, DT_LEFT, DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER, DT_WORDBREAK,
    FW_BOLD, FW_NORMAL,
};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{EnableWindow, SetFocus, VK_ESCAPE, VK_RETURN};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetClientRect,
    GetMessageW, GetWindowLongPtrW, GetWindowRect, LoadCursorW, RegisterClassExW,
    SendMessageW, SetWindowLongPtrW, SetWindowPos, ShowWindow, TranslateMessage,
    GWLP_USERDATA, HMENU, IDC_ARROW, MSG, SWP_NOACTIVATE, SWP_NOZORDER, SW_SHOW,
    WM_CLOSE, WM_COMMAND, WM_CREATE, WM_DESTROY, WM_KEYDOWN, WM_PAINT, WNDCLASSEXW, WS_CAPTION,
    WS_CHILD, WS_POPUP, WS_SYSMENU, WS_TABSTOP, WS_VISIBLE,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    BM_GETCHECK, BS_AUTOCHECKBOX, BS_OWNERDRAW, SWP_NOMOVE, SWP_NOSIZE, WM_CTLCOLORBTN,
    WM_CTLCOLORSTATIC, WM_DRAWITEM,
};
use windows_sys::Win32::UI::Controls::{DRAWITEMSTRUCT, ODS_DISABLED, ODS_SELECTED, ODT_BUTTON};

const DIALOG_CLASS: &str = "AmdMobilePower.UnlockConsent.v1";
const ID_CONSENT_CHECKBOX: usize = 401;
const ID_CONFIRM: usize = 402;
const ID_CANCEL: usize = 403;

const LOGICAL_WIDTH: i32 = 660;
const LOGICAL_HEIGHT: i32 = 640;

const TITLE: &str = "启用写入之前";
const LIABILITY_HEADING: &str = "免责声明";
const LIABILITY_BODY: &str = "本程序开源免费，按「原样」提供，不对任何硬件后果作出担保。\
解锁后，程序会向主板发送功耗限制指令；虽然内置回读校验与保守默认值，\
仍请自行判断风险，并从小数值开始试用。";
const MANUAL_HEADING: &str = "操作须知";
const MANUAL_BODY: &str = "1. 输入 5-60 之间的目标功耗，点「应用」，等待状态变为「已应用」。\n\
2. 三个快捷预设可编辑保存，方便一键切换。\n\
3. 托盘菜单和自动策略可以让插电、电池状态自动切换功耗。\n\
4. 出现「固件限制」提示说明主板限制了下限，属于正常现象。\n\
5. 想恢复只读，点右上角的锁形按钮重新锁定即可。";
const CONSENT_LABEL: &str = "我已阅读并同意以上《免责声明》与操作须知";
const CONFIRM_LABEL: &str = "确认并启用写入";
const CANCEL_LABEL: &str = "取消";

struct DialogShared {
    agreed: bool,
    closed: bool,
    checkbox: HWND,
    confirm: HWND,
    fonts: DialogFonts,
    percent: i32,
    brush: HBRUSH,
}

struct DialogFonts {
    title: HGDIOBJ,
    heading: HGDIOBJ,
    body: HGDIOBJ,
    control: HGDIOBJ,
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn scale(value: i32, percent: i32) -> i32 {
    ((value as f64) * (percent as f64) / 100.0).round() as i32
}

unsafe fn create_font(face: &str, pixel_height: i32, weight: i32) -> HGDIOBJ {
    let face = wide(face);
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

unsafe fn shared(hwnd: HWND) -> *mut DialogShared {
    GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut DialogShared
}

unsafe extern "system" fn dialog_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match message {
        WM_CREATE => {
            let create = lparam as *const windows_sys::Win32::UI::WindowsAndMessaging::CREATESTRUCTW;
            let state = if create.is_null() {
                std::ptr::null_mut()
            } else {
                (*create).lpCreateParams as *mut DialogShared
            };
            if state.is_null() {
                return -1;
            }
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, state as isize);
            let s = &(*state);
            let instance = GetModuleHandleW(std::ptr::null());
            let checkbox_text = wide(CONSENT_LABEL);
            let checkbox = CreateWindowExW(
                0,
                wide("BUTTON").as_ptr(),
                checkbox_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX as u32,
                scale(36, s.percent),
                scale(494, s.percent),
                scale(588, s.percent),
                scale(28, s.percent),
                hwnd,
                ID_CONSENT_CHECKBOX as HMENU,
                instance,
                std::ptr::null(),
            );
            (*state).checkbox = checkbox;
            let cancel_text = wide(CANCEL_LABEL);
            let cancel = CreateWindowExW(
                0,
                wide("BUTTON").as_ptr(),
                cancel_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
                scale(356, s.percent),
                scale(548, s.percent),
                scale(120, s.percent),
                scale(40, s.percent),
                hwnd,
                ID_CANCEL as HMENU,
                instance,
                std::ptr::null(),
            );
            let confirm_text = wide(CONFIRM_LABEL);
            let confirm = CreateWindowExW(
                0,
                wide("BUTTON").as_ptr(),
                confirm_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW as u32,
                scale(492, s.percent),
                scale(548, s.percent),
                scale(132, s.percent),
                scale(40, s.percent),
                hwnd,
                ID_CONFIRM as HMENU,
                instance,
                std::ptr::null(),
            );
            (*state).confirm = confirm;
            EnableWindow(confirm, 0);
            for control in [checkbox, cancel, confirm] {
                if !control.is_null() {
                    SendMessageW(control, 0x0030, s.fonts.control as usize, 1);
                }
            }
            SetFocus(checkbox);
            0
        }
        WM_PAINT => {
            let state = shared(hwnd);
            if state.is_null() {
                return DefWindowProcW(hwnd, message, wparam, lparam);
            }
            let s = &(*state);
            let mut paint = PAINTSTRUCT::default();
            let hdc = BeginPaint(hwnd, &mut paint);
            if hdc.is_null() {
                return 0;
            }
            let mut client = RECT::default();
            GetClientRect(hwnd, &mut client);
            FillRect(hdc, &client, s.brush);
            SetBkMode(hdc, TRANSPARENT as i32);
            let mut draw = |text: &str, font: HGDIOBJ, color: u32, x: i32, y: i32, w: i32, h: i32| {
                let value = wide(text);
                let old = windows_sys::Win32::Graphics::Gdi::SelectObject(hdc, font);
                SetTextColor(hdc, color);
                SetBkColor(hdc, rgb(14, 21, 24));
                let mut rect = RECT {
                    left: scale(x, s.percent),
                    top: scale(y, s.percent),
                    right: scale(x + w, s.percent),
                    bottom: scale(y + h, s.percent),
                };
                DrawTextW(
                    hdc,
                    value.as_ptr(),
                    -1,
                    &mut rect,
                    DT_LEFT | DT_WORDBREAK | DT_NOPREFIX,
                );
                windows_sys::Win32::Graphics::Gdi::SelectObject(hdc, old);
            };
            draw(TITLE, s.fonts.title, rgb(241, 247, 244), 36, 26, 588, 46);
            draw(LIABILITY_HEADING, s.fonts.heading, rgb(69, 214, 168), 36, 86, 588, 30);
            draw(LIABILITY_BODY, s.fonts.body, rgb(200, 214, 208), 36, 122, 588, 140);
            draw(MANUAL_HEADING, s.fonts.heading, rgb(69, 214, 168), 36, 268, 588, 30);
            draw(MANUAL_BODY, s.fonts.body, rgb(200, 214, 208), 36, 304, 588, 176);
            EndPaint(hwnd, &paint);
            0
        }
        WM_COMMAND => {
            let id = wparam & 0xFFFF;
            let state = shared(hwnd);
            if state.is_null() {
                return 0;
            }
            let s = &mut (*state);
            match id {
                ID_CONSENT_CHECKBOX => {
                    let checked = SendMessageW(s.checkbox, BM_GETCHECK, 0, 0) == 1;
                    EnableWindow(s.confirm, i32::from(checked));
                    0
                }
                ID_CONFIRM => {
                    let checked = SendMessageW(s.checkbox, BM_GETCHECK, 0, 0) == 1;
                    if checked {
                        s.agreed = true;
                        DestroyWindow(hwnd);
                    }
                    0
                }
                ID_CANCEL => {
                    DestroyWindow(hwnd);
                    0
                }
                _ => DefWindowProcW(hwnd, message, wparam, lparam),
            }
        }
        WM_KEYDOWN => {
            match wparam as u16 {
                VK_ESCAPE => {
                    DestroyWindow(hwnd);
                    0
                }
                VK_RETURN => {
                    let state = shared(hwnd);
                    if !state.is_null() {
                        let s = &(*state);
                        let checked = SendMessageW(s.checkbox, BM_GETCHECK, 0, 0) == 1;
                        if checked {
                            (*state).agreed = true;
                            DestroyWindow(hwnd);
                        }
                    }
                    0
                }
                _ => DefWindowProcW(hwnd, message, wparam, lparam),
            }
        }
        WM_CLOSE => {
            DestroyWindow(hwnd);
            0
        }
        WM_DESTROY => {
            let state = shared(hwnd);
            if !state.is_null() {
                (*state).closed = true;
            }
            0
        }
        WM_CTLCOLORBTN => {
            let hdc = wparam as windows_sys::Win32::Graphics::Gdi::HDC;
            SetBkColor(hdc, rgb(14, 21, 24));
            SetTextColor(hdc, rgb(230, 238, 234));
            let state = shared(hwnd);
            if state.is_null() {
                0
            } else {
                (*state).brush as LRESULT
            }
        }
        WM_CTLCOLORSTATIC => {
            let hdc = wparam as windows_sys::Win32::Graphics::Gdi::HDC;
            SetBkMode(hdc, TRANSPARENT as i32);
            SetTextColor(hdc, rgb(214, 226, 220));
            let state = shared(hwnd);
            if state.is_null() {
                0
            } else {
                (*state).brush as LRESULT
            }
        }
        WM_DRAWITEM => {
            let draw = lparam as *const DRAWITEMSTRUCT;
            let state = shared(hwnd);
            if draw.is_null() || state.is_null() || (*draw).CtlType != ODT_BUTTON {
                return 0;
            }
            let s = &(*state);
            let draw = &*draw;
            let disabled = draw.itemState & ODS_DISABLED != 0;
            let pressed = draw.itemState & ODS_SELECTED != 0;
            let (fill, text_color) = if draw.CtlID as usize == ID_CONFIRM {
                if disabled {
                    (rgb(38, 50, 54), rgb(110, 124, 119))
                } else if pressed {
                    (rgb(14, 92, 78), rgb(255, 255, 255))
                } else {
                    (rgb(20, 118, 101), rgb(255, 255, 255))
                }
            } else {
                if pressed {
                    (rgb(50, 64, 68), rgb(240, 246, 243))
                } else {
                    (rgb(36, 47, 51), rgb(230, 238, 234))
                }
            };
            let brush = CreateSolidBrush(fill);
            let pen = windows_sys::Win32::Graphics::Gdi::CreatePen(0, 1, fill);
            let old_brush = SelectObject(draw.hDC, brush);
            let old_pen = SelectObject(draw.hDC, pen);
            RoundRect(
                draw.hDC,
                draw.rcItem.left,
                draw.rcItem.top,
                draw.rcItem.right,
                draw.rcItem.bottom,
                10,
                10,
            );
            SelectObject(draw.hDC, old_brush);
            SelectObject(draw.hDC, old_pen);
            DeleteObject(brush);
            DeleteObject(pen);
            SetBkMode(draw.hDC, TRANSPARENT as i32);
            SetTextColor(draw.hDC, text_color);
            let label = if draw.CtlID as usize == ID_CONFIRM {
                CONFIRM_LABEL
            } else {
                CANCEL_LABEL
            };
            let mut text = wide(label);
            let mut rect = draw.rcItem;
            let old_font = SelectObject(draw.hDC, s.fonts.control);
            DrawTextW(
                draw.hDC,
                text.as_mut_ptr(),
                -1,
                &mut rect,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX,
            );
            SelectObject(draw.hDC, old_font);
            1
        }
        _ => DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

fn rgb(red: u8, green: u8, blue: u8) -> u32 {
    (red as u32) | ((green as u32) << 8) | ((blue as u32) << 16)
}

unsafe fn ensure_class(instance: HINSTANCE) -> bool {
    let class_name = wide(DIALOG_CLASS);
    let mut class: WNDCLASSEXW = std::mem::zeroed();
    class.cbSize = size_of::<WNDCLASSEXW>() as u32;
    class.lpfnWndProc = Some(dialog_proc);
    class.hInstance = instance;
    class.hCursor = LoadCursorW(std::ptr::null_mut(), IDC_ARROW);
    class.hbrBackground = std::ptr::null_mut();
    class.lpszClassName = class_name.as_ptr();
    let atom = RegisterClassExW(&class);
    if atom != 0 {
        return true;
    }
    GetLastError() == ERROR_CLASS_ALREADY_EXISTS
}

/// Shows the consent dialog modally over `parent`. Returns true only when the
/// user ticked the checkbox and clicked the confirm button.
pub unsafe fn show_unlock_dialog(parent: HWND, percent: i32) -> bool {
    let instance = GetModuleHandleW(std::ptr::null());
    if instance.is_null() || !ensure_class(instance) {
        return false;
    }
    let percent = percent.max(100);
    let fonts = DialogFonts {
        title: create_font("Microsoft YaHei UI", scale(28, percent), FW_BOLD as i32),
        heading: create_font("Microsoft YaHei UI", scale(18, percent), FW_BOLD as i32),
        body: create_font("Microsoft YaHei UI", scale(15, percent), FW_NORMAL as i32),
        control: create_font("Microsoft YaHei UI", scale(15, percent), FW_NORMAL as i32),
    };
    let mut state = Box::new(DialogShared {
        agreed: false,
        closed: false,
        checkbox: std::ptr::null_mut(),
        confirm: std::ptr::null_mut(),
        fonts,
        percent,
        brush: CreateSolidBrush(rgb(14, 21, 24)),
    });
    let mut parent_rect = RECT::default();
    GetWindowRect(parent, &mut parent_rect);
    let width = scale(LOGICAL_WIDTH, percent);
    let height = scale(LOGICAL_HEIGHT, percent);
    let x = parent_rect.left + (parent_rect.right - parent_rect.left - width) / 2;
    let y = parent_rect.top + (parent_rect.bottom - parent_rect.top - height) / 2;
    let dialog = CreateWindowExW(
        0,
        wide(DIALOG_CLASS).as_ptr(),
        wide(TITLE).as_ptr(),
        WS_POPUP | WS_CAPTION | WS_SYSMENU,
        x.max(0),
        y.max(0),
        width,
        height,
        parent,
        std::ptr::null_mut(),
        instance,
        &mut *state as *mut DialogShared as *const c_void,
    );
    if dialog.is_null() {
        return false;
    }
    EnableWindow(parent, 0);
    ShowWindow(dialog, SW_SHOW);
    SetWindowPos(
        dialog,
        std::ptr::null_mut(),
        0,
        0,
        0,
        0,
        SWP_NOZORDER | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
    );
    let mut message = MSG::default();
    loop {
        if state.closed {
            break;
        }
        let result = GetMessageW(&mut message, std::ptr::null_mut(), 0, 0);
        if result == 0 || result == -1 {
            break;
        }
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    if !dialog.is_null() && windows_sys::Win32::UI::WindowsAndMessaging::IsWindow(dialog) != 0 {
        DestroyWindow(dialog);
        while GetMessageW(&mut message, std::ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    EnableWindow(parent, 1);
    let agreed = state.agreed;
    let fonts = [state.fonts.title, state.fonts.heading, state.fonts.body, state.fonts.control];
    let brush = state.brush;
    drop(state);
    for font in fonts {
        if !font.is_null() {
            DeleteObject(font);
        }
    }
    if !brush.is_null() {
        DeleteObject(brush);
    }
    agreed
}
