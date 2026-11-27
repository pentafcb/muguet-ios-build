// muguet - touch.rs
// Constantin Clerc (c22dev) - 0.1

use crate::input;
use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::{class, msg_send};
use objc2_core_foundation::{CGPoint, CGRect, CGSize};
use objc2_foundation::NSString;
use std::collections::{HashMap, HashSet};
use winit::event::{Touch, TouchPhase};
use winit::window::Window;

#[derive(Clone, Copy, PartialEq)]
enum Act {
    Key(&'static str),

    Mouse(u8),

    AimToggle,

    KeyNav(&'static str),
    NavToggle,

    Horn,
    Home,
    FirstPerson,
    SpawnCar,
    Console,
}

#[derive(Clone, Copy)]
enum Anchor {
    BottomRight(f64, f64),
    TopLeft(f64, f64),
    TopRight(f64, f64),

    Nav(f64, f64),
}

struct Spec {
    anchor: Anchor,
    radius: f64,
    on_foot: Option<(&'static str, Act)>,
    in_car: Option<(&'static str, Act)>,
    nav: bool,
}

const fn b(anchor: Anchor, radius: f64, on_foot: Option<(&'static str, Act)>, in_car: Option<(&'static str, Act)>) -> Spec {
    Spec { anchor, radius, on_foot, in_car, nav: false }
}
const fn n(x: f64, label: &'static str, key: &'static str) -> Spec {
    Spec { anchor: Anchor::Nav(x, 0.0), radius: 21.0, on_foot: Some((label, Act::Key(key))), in_car: Some((label, Act::Key(key))), nav: true }
}

use Act::*;
use Anchor::*;
// MENU and CONSOLE live on the window view, not the overlay root, so
// they stay visible (and tappable) while a controller is connected.
// Their indices are load-bearing: install() reparents these views,
// relabel() exempts them, and touch_always_visible() hit-tests them.
const MENU_IDX: usize = 9;
const CONSOLE_IDX: usize = 25;
const BUTTONS: &[Spec] = &[
    b(BottomRight(62.0, 68.0), 44.0, Some(("FIRE", Mouse(1))), Some(("GAS", Key("KeyW")))),
    b(BottomRight(158.0, 46.0), 31.0, Some(("AIM", AimToggle)), Some(("BRAKE", Key("KeyS")))),
    b(BottomRight(58.0, 168.0), 28.0, Some(("JUMP", Key("Space"))), Some(("H.BRAKE", Key("Space")))),
    b(BottomRight(140.0, 132.0), 26.0, Some(("ENTER", Key("KeyF"))), Some(("EXIT", Key("KeyF")))),
    b(BottomRight(222.0, 98.0), 24.0, Some(("RELOAD", Key("KeyR"))), Some(("HORN", Horn))),
    b(TopRight(30.0, 30.0), 22.0, Some(("WEAPON", Key("Tab"))), Some(("WEAPON", Key("Tab")))),
    b(TopRight(84.0, 30.0), 22.0, Some(("COVER", Key("KeyQ"))), Some(("RADIO", Key("KeyQ")))),
    b(TopRight(138.0, 30.0), 22.0, Some(("CROUCH", Key("ControlLeft"))), Some(("LOOK\nBACK", Key("KeyC")))),
    b(TopRight(192.0, 30.0), 22.0, Some(("CAM", Key("KeyV"))), Some(("CAM", Key("KeyV")))),
    b(TopRight(246.0, 30.0), 22.0, Some(("MENU", Home)), Some(("MENU", Home))),
    b(TopLeft(30.0, 30.0), 22.0, Some(("PAUSE", KeyNav("Escape"))), Some(("PAUSE", KeyNav("Escape")))),
    b(TopLeft(84.0, 30.0), 22.0, Some(("PHONE", Key("ArrowUp"))), Some(("PHONE", Key("ArrowUp")))),
    b(TopLeft(138.0, 30.0), 22.0, Some(("MENU\nKEYS", NavToggle)), Some(("MENU\nKEYS", NavToggle))),
    b(TopLeft(192.0, 30.0), 22.0, Some(("SWITCH", Key("AltLeft"))), Some(("SWITCH", Key("AltLeft")))),
    b(TopLeft(246.0, 30.0), 22.0, Some(("1ST\nPOV", FirstPerson)), Some(("1ST\nPOV", FirstPerson))),
    b(TopLeft(300.0, 30.0), 22.0, Some(("CAR", SpawnCar)), Some(("CAR", SpawnCar))),
    b(TopLeft(45.0, 112.0), 29.0, Some(("FIRE", Mouse(1))), None),
    n(-182.0, "TAB ◀", "KeyQ"),
    n(-130.0, "◀", "ArrowLeft"),
    n(-78.0, "▲", "ArrowUp"),
    n(-26.0, "▼", "ArrowDown"),
    n(26.0, "▶", "ArrowRight"),
    n(78.0, "OK", "Enter"),
    n(130.0, "BACK", "Backspace"),
    n(182.0, "TAB ▶", "KeyE"),
    // CONSOLE is last on purpose: it sits outside the 17 custom-layout
    // slots (like CAR) and its index is CONSOLE_IDX above. Top-left
    // row, right of CAR: on a 390 pt screen x 332-376, y 8-52 — clear
    // of the RAM label (x 136.5-253.5) and CAR (x 278-322).
    b(TopLeft(354.0, 30.0), 22.0, Some(("CONSOLE", Console)), Some(("CONSOLE", Console))),
];

const STICK_RADIUS: f64 = 58.0;
const KNOB_RADIUS: f64 = 26.0;
const SPRINT_REACH: f64 = 1.35;

const LOOK_GAIN: f64 = 3.0;
const WHEEL_DEADZONE: f64 = 10.0;
const WHEEL_FULL: f64 = 45.0;
const WHEEL_PUSH: f64 = 40.0;

fn nav_scale(width: f64) -> f64 {
    button_scale().min(((width - 32.0) / 406.0).max(0.1))
}

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
static TOUCH_SENS_BITS: AtomicU64 = AtomicU64::new(1.0f64.to_bits());
static AIM_SENS_BITS: AtomicU64 = AtomicU64::new(0.8f64.to_bits());
static HOLD_AIM_FLAG: AtomicBool = AtomicBool::new(false);
static FIRE_AIM_FLAG: AtomicBool = AtomicBool::new(true);

static BUTTON_SCALE_BITS: AtomicU64 = AtomicU64::new(1.0f64.to_bits());
static BUTTON_OFFSET_X_BITS: AtomicU64 = AtomicU64::new(0.0f64.to_bits());
static BUTTON_OFFSET_Y_BITS: AtomicU64 = AtomicU64::new(0.0f64.to_bits());
static BUTTON_OPACITY_BITS: AtomicU64 = AtomicU64::new(0.22f64.to_bits());
static STICK_OFFSET_X_BITS: AtomicU64 = AtomicU64::new(0.0f64.to_bits());
static STICK_OFFSET_Y_BITS: AtomicU64 = AtomicU64::new(0.0f64.to_bits());

use std::sync::atomic::{AtomicI32, AtomicU32};
static CUSTOM_X: [AtomicI32; 17] = [
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0),
];
static CUSTOM_Y: [AtomicI32; 17] = [
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0),
    AtomicI32::new(0),
];
static CUSTOM_SCALE: [AtomicU32; 17] = [
    AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100),
    AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100),
    AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100),
    AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100), AtomicU32::new(100),
    AtomicU32::new(100),
];

fn custom_button_layout(idx: usize) -> (f64, f64, f64) {
    if idx < 17 {
        let dx = CUSTOM_X[idx].load(Ordering::Relaxed) as f64;
        let dy = CUSTOM_Y[idx].load(Ordering::Relaxed) as f64;
        let scale = CUSTOM_SCALE[idx].load(Ordering::Relaxed) as f64 / 100.0;
        (dx, dy, scale.clamp(0.4, 2.5))
    } else {
        (0.0, 0.0, 1.0)
    }
}

#[no_mangle]
pub extern "C" fn muguet_set_button_layout(idx: u32, dx: f64, dy: f64, scale: f64) {
    if (idx as usize) < 17 {
        CUSTOM_X[idx as usize].store(dx.round() as i32, Ordering::Relaxed);
        CUSTOM_Y[idx as usize].store(dy.round() as i32, Ordering::Relaxed);
        CUSTOM_SCALE[idx as usize].store((scale.clamp(0.4, 2.5) * 100.0).round() as u32, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn muguet_reset_button_layout() {
    for i in 0..17 {
        CUSTOM_X[i].store(0, Ordering::Relaxed);
        CUSTOM_Y[i].store(0, Ordering::Relaxed);
        CUSTOM_SCALE[i].store(100, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn muguet_apply_button_layout() {
    OVERLAY.with(|cell| if let Ok(mut guard) = cell.try_borrow_mut() { if let Some(o) = guard.as_mut() { o.apply_layout(); } });
}

pub fn touch_sensitivity() -> f64 { f64::from_bits(TOUCH_SENS_BITS.load(Ordering::Relaxed)) }
pub fn aim_sensitivity() -> f64 { f64::from_bits(AIM_SENS_BITS.load(Ordering::Relaxed)) }
pub fn hold_aim() -> bool { HOLD_AIM_FLAG.load(Ordering::Relaxed) }
pub fn fire_aim() -> bool { FIRE_AIM_FLAG.load(Ordering::Relaxed) }

pub fn button_scale() -> f64 { f64::from_bits(BUTTON_SCALE_BITS.load(Ordering::Relaxed)) }
pub fn button_offset_x() -> f64 { f64::from_bits(BUTTON_OFFSET_X_BITS.load(Ordering::Relaxed)) }
pub fn button_offset_y() -> f64 { f64::from_bits(BUTTON_OFFSET_Y_BITS.load(Ordering::Relaxed)) }
pub fn button_opacity() -> f64 { f64::from_bits(BUTTON_OPACITY_BITS.load(Ordering::Relaxed)) }
pub fn stick_offset_x() -> f64 { f64::from_bits(STICK_OFFSET_X_BITS.load(Ordering::Relaxed)) }
pub fn stick_offset_y() -> f64 { f64::from_bits(STICK_OFFSET_Y_BITS.load(Ordering::Relaxed)) }

// Parse + validate one float env var: non-finite values (NaN/inf)
// used to be stored verbatim — NaN button scale made overlay buttons
// invisible (NaN CGRect), NaN touch sens zeroed look input. Rejects
// them and clamps to the given range instead.
fn env_f64(name: &str, min: f64, max: f64) -> Option<f64> {
    std::env::var(name).ok().and_then(|v| v.parse::<f64>().ok())
        .filter(|v| v.is_finite()).map(|v| v.clamp(min, max))
}

pub fn update_settings_from_env() {
    if let Some(v) = env_f64("MUGUET_TOUCH_SENS", 0.25, 6.0) {
        TOUCH_SENS_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_AIM_SENS", 0.1, 3.0) {
        AIM_SENS_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Ok(v) = std::env::var("MUGUET_AIM_MODE") {
        HOLD_AIM_FLAG.store(v == "hold", Ordering::Relaxed);
    }
    if let Ok(v) = std::env::var("MUGUET_FIRE_AIM") {
        FIRE_AIM_FLAG.store(v != "0", Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_BUTTON_SCALE", 0.6, 2.0) {
        BUTTON_SCALE_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_BUTTON_OFFSET_X", -150.0, 150.0) {
        BUTTON_OFFSET_X_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_BUTTON_OFFSET_Y", -150.0, 150.0) {
        BUTTON_OFFSET_Y_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_BUTTON_OPACITY", 0.1, 0.9) {
        BUTTON_OPACITY_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_STICK_OFFSET_X", -100.0, 150.0) {
        STICK_OFFSET_X_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    if let Some(v) = env_f64("MUGUET_STICK_OFFSET_Y", -100.0, 150.0) {
        STICK_OFFSET_Y_BITS.store(v.to_bits(), Ordering::Relaxed);
    }
    OVERLAY.with(|cell| if let Ok(mut guard) = cell.try_borrow_mut() { if let Some(o) = guard.as_mut() { o.apply_layout(); } });
}

const MIN_HOLD: std::time::Duration = std::time::Duration::from_millis(120);
const MOUSE_HOLD: std::time::Duration = std::time::Duration::from_millis(25);

enum Grip {
    Pointer { at: (f64, f64) },
    Stick { origin: (f64, f64), at: (f64, f64) },
    Look { motion: crate::aim::DragLook },
    Button { idx: usize, act: Act, start: (f64, f64), last: (f64, f64), motion: crate::aim::DragLook },
}

struct Btn {
    view: Retained<AnyObject>,
    label: Retained<AnyObject>,
    center: (f64, f64),
    radius: f64,
}

struct Overlay {
    root: Retained<AnyObject>,
    buttons: Vec<Btn>,
    stick_base: Retained<AnyObject>,
    stick_knob: Retained<AnyObject>,
    stick_home: (f64, f64),
    loading_label: Retained<AnyObject>,
    network_label: Retained<AnyObject>,
    // RAM tracker label: added to the window's view, NOT to the overlay
    // root, because the root is hidden while a controller is connected
    // and the tracker must stay visible during controller play. The
    // last text applied, so refresh() skips redundant UIKit updates.
    ram_label: Retained<AnyObject>,
    ram_text: String,
    loading: bool,

    safe: (f64, f64, f64, f64),
    screen: (f64, f64),
    scale: f64,
    grips: HashMap<u64, Grip>,
    held: HashSet<&'static str>,

    since: HashMap<&'static str, std::time::Instant>,
    mouse_since: [std::time::Instant; 2],

    lingering: bool,
    mouse: u8,
    aim_latched: bool,
    menu: crate::touch_gestures::MenuState,
    pinch: crate::touch_gestures::Pinch,
    pinching: bool,
    in_car: bool,
    hidden: bool,
}

thread_local! {
    static OVERLAY: std::cell::RefCell<Option<Overlay>> = const { std::cell::RefCell::new(None) };
}

fn rect(x: f64, y: f64, w: f64, h: f64) -> CGRect {
    CGRect { origin: CGPoint { x, y }, size: CGSize { width: w, height: h } }
}

fn color(white: f64, alpha: f64) -> Retained<AnyObject> {
    unsafe { msg_send![class!(UIColor), colorWithWhite: white, alpha: alpha] }
}

fn rgb(r: f64, g: f64, b: f64, alpha: f64) -> Retained<AnyObject> {
    unsafe { msg_send![class!(UIColor), colorWithRed: r, green: g, blue: b, alpha: alpha] }
}

fn circle(parent: &AnyObject, center: (f64, f64), r: f64, white: f64, alpha: f64) -> Retained<AnyObject> {
    unsafe {
        let v: Retained<AnyObject> = msg_send![class!(UIView), new];
        let _: () = msg_send![&*v, setFrame: rect(center.0 - r, center.1 - r, 2.0 * r, 2.0 * r)];
        let _: () = msg_send![&*v, setUserInteractionEnabled: false];
        let _: () = msg_send![&*v, setBackgroundColor: &*color(white, alpha)];
        let layer: *mut AnyObject = msg_send![&*v, layer];
        let _: () = msg_send![layer, setCornerRadius: r];
        let _: () = msg_send![parent, addSubview: &*v];
        v
    }
}

fn label(parent: &AnyObject, r: f64) -> Retained<AnyObject> {
    unsafe {
        let l: Retained<AnyObject> = msg_send![class!(UILabel), new];
        let _: () = msg_send![&*l, setFrame: rect(2.0, 0.0, 2.0 * r - 4.0, 2.0 * r)];
        let _: () = msg_send![&*l, setUserInteractionEnabled: false];
        let _: () = msg_send![&*l, setTextColor: &*color(1.0, 0.9)];
        let font: Retained<AnyObject> = msg_send![class!(UIFont), boldSystemFontOfSize: (r * 0.42).clamp(9.0, 15.0)];
        let _: () = msg_send![&*l, setFont: &*font];
        let _: () = msg_send![&*l, setTextAlignment: 1isize];
        let _: () = msg_send![&*l, setNumberOfLines: 2isize];
        let _: () = msg_send![&*l, setAdjustsFontSizeToFitWidth: true];
        let _: () = msg_send![parent, addSubview: &*l];
        l
    }
}

fn set_text(l: &AnyObject, text: &str) {
    unsafe { let _: () = msg_send![l, setText: &*NSString::from_str(text)]; }
}
fn set_hidden(v: &AnyObject, hidden: bool) {
    unsafe { let _: () = msg_send![v, setHidden: hidden]; }
}
fn set_alpha_bg(v: &AnyObject, alpha: f64) {
    unsafe { let _: () = msg_send![v, setBackgroundColor: &*color(1.0, alpha)]; }
}
fn move_to(v: &AnyObject, c: (f64, f64)) {
    unsafe { let _: () = msg_send![v, setCenter: CGPoint { x: c.0, y: c.1 }]; }
}

pub fn install(window: &Window) {
    update_settings_from_env();
    use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};
    let Ok(handle) = window.window_handle() else { return };
    let RawWindowHandle::UiKit(h) = handle.as_raw() else { return };
    let view = unsafe { &*(h.ui_view.as_ptr() as *const AnyObject) };

    let scale = window.scale_factor();
    let full = window.outer_size().to_logical::<f64>(scale);
    let pos = window.inner_position().map(|p| p.to_logical::<f64>(scale)).unwrap_or_default();
    let inner = window.inner_size().to_logical::<f64>(scale);
    let safe = (pos.x, pos.y, inner.width, inner.height);

    // A second install() (window recreation) used to orphan the old
    // overlay's UIView: the thread-local was replaced while the old
    // root and all its buttons stayed attached to the window — leaked
    // views and duplicated visible buttons. Remove it first.
    OVERLAY.with(|cell| {
        if let Ok(mut guard) = cell.try_borrow_mut() {
            if let Some(old) = guard.take() {
                unsafe {
                    let _: () = msg_send![&*old.root, removeFromSuperview];
                    let _: () = msg_send![&*old.ram_label, removeFromSuperview];
                    // MENU/CONSOLE live on the window view, not the
                    // root, so removing the root would orphan them.
                    for &idx in &[MENU_IDX, CONSOLE_IDX] {
                        if let Some(btn) = old.buttons.get(idx) {
                            let _: () = msg_send![&*btn.view, removeFromSuperview];
                        }
                    }
                }
            }
        }
    });
    let root = unsafe {
        let v: Retained<AnyObject> = msg_send![class!(UIView), new];
        let _: () = msg_send![&*v, setFrame: rect(0.0, 0.0, full.width, full.height)];
        let _: () = msg_send![&*v, setUserInteractionEnabled: false];
        let _: () = msg_send![view, addSubview: &*v];
        v
    };
    let (sx, sy, sw, sh) = safe;
    let b_scale = button_scale();
    let (b_ox, b_oy) = (button_offset_x(), button_offset_y());
    let (s_ox, s_oy) = (stick_offset_x(), stick_offset_y());
    let place = |a: Anchor| match a {
        BottomRight(dx, dy) => (sx + sw - dx * b_scale - b_ox, sy + sh - dy * b_scale - b_oy),
        TopLeft(dx, dy) => (sx + dx * b_scale, sy + dy * b_scale),
        TopRight(dx, dy) => (sx + sw - dx * b_scale, sy + dy * b_scale),
        Nav(dx, dy) => (sx + sw / 2.0 + dx * nav_scale(sw), sy + 90.0 * b_scale + dy),
    };
    let buttons = BUTTONS
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let (c_dx, c_dy, c_scale) = if i < 16 { custom_button_layout(i) } else { (0.0, 0.0, 1.0) };
            let r = s.radius * if s.nav { nav_scale(sw) } else { b_scale * c_scale };
            let mut center = place(s.anchor);
            center.0 += c_dx;
            center.1 += c_dy;
            let view = circle(&root, center, r, 1.0, button_opacity());
            let label = label(&view, r);
            Btn { view, label, center, radius: r }
        })
        .collect();
    // MENU and CONSOLE stay visible while a controller is connected:
    // the overlay root hides then, so their views live on the window
    // view instead (same coordinate space — the root frame is
    // (0,0,full)), exactly like the RAM label below. apply_layout
    // keeps working: setCenter/setFrame use the superview's space.
    for &idx in &[MENU_IDX, CONSOLE_IDX] {
        if let Some(btn) = buttons.get(idx) {
            unsafe {
                let _: () = msg_send![&*btn.view, removeFromSuperview];
                let _: () = msg_send![view, addSubview: &*btn.view];
            }
        }
    }
    let (j_dx, j_dy, j_scale) = custom_button_layout(16);
    let stick_radius = STICK_RADIUS * b_scale * j_scale;
    let knob_radius = KNOB_RADIUS * b_scale * j_scale;
    let stick_home = (sx + 40.0 + stick_radius + s_ox + j_dx, sy + sh - 30.0 - stick_radius - s_oy + j_dy);
    let stick_base = circle(&root, stick_home, stick_radius, 1.0, 0.12);
    let stick_knob = circle(&root, stick_home, knob_radius, 1.0, 0.3);
    let loading_label = label(&root, 150.0);
    let network_label = label(&root, 150.0);
    // RAM tracker: top-center, just below the network label slot, in
    // the gap between the top-left and top-right button clusters. It
    // lives on the window view, not the overlay root, so it stays
    // visible while a controller is connected (the root hides then).
    let ram_label = label(view, 150.0);
    unsafe {
        let _: () = msg_send![&*loading_label, setFrame: rect(sx + sw * 0.15, sy + sh * 0.32, sw * 0.7, sh * 0.36)];
        let _: () = msg_send![&*loading_label, setNumberOfLines: 0isize];
        let _: () = msg_send![&*loading_label, setBackgroundColor: &*color(0.05, 0.94)];
        let font: Retained<AnyObject> = msg_send![class!(UIFont), systemFontOfSize: 18.0];
        let _: () = msg_send![&*loading_label, setFont: &*font];
        let _: () = msg_send![&*network_label, setFrame: rect(sx + sw * 0.35, sy + 12.0, sw * 0.3, 34.0)];
        let _: () = msg_send![&*network_label, setBackgroundColor: &*color(0.05, 0.65)];
        let _: () = msg_send![&*ram_label, setFrame: rect(sx + sw * 0.35, sy + 48.0, sw * 0.3, 20.0)];
        let _: () = msg_send![&*ram_label, setNumberOfLines: 1isize];
        let _: () = msg_send![&*ram_label, setBackgroundColor: &*color(0.05, 0.65)];
        let ram_font: Retained<AnyObject> = msg_send![class!(UIFont), systemFontOfSize: 11.0];
        let _: () = msg_send![&*ram_label, setFont: &*ram_font];
    }
    set_hidden(&loading_label, true);
    set_hidden(&network_label, true);
    set_hidden(&ram_label, true);
    let mut o = Overlay {
        root, buttons, stick_base, stick_knob, stick_home, loading_label, network_label, ram_label, ram_text: String::new(), loading: false, safe, scale,
        screen: (full.width, full.height),
        grips: HashMap::new(), held: HashSet::new(), since: HashMap::new(),
        mouse_since: [std::time::Instant::now(); 2], lingering: false, mouse: 0, aim_latched: false,
        menu: Default::default(), pinch: Default::default(), pinching: false, in_car: false, hidden: false,
    };
    o.relabel();
    eprintln!("[touch] overlay ready ({:.0}x{:.0} pt, safe area {:.0},{:.0} {:.0}x{:.0})", full.width, full.height, sx, sy, sw, sh);
    OVERLAY.with(|cell| if let Ok(mut guard) = cell.try_borrow_mut() { *guard = Some(o); });
}

impl Overlay {
    fn direct_touch(&self) -> bool { self.menu.nav || self.menu.pause_requested }

    fn pointer_at(&self, p: (f64, f64)) {
        let (x, y) = crate::touch_gestures::pointer_position(p, self.screen, input::size());
        input::mouse_pos(x, y);
    }

    fn pointer_distance(&self) -> Option<f64> {
        let mut points = self.grips.values().filter_map(|g| match g {
            Grip::Pointer { at } => Some(*at),
            _ => None,
        });
        let a = points.next()?;
        let b = points.next()?;
        Some((a.0 - b.0).hypot(a.1 - b.1))
    }

    fn pointer_center(&self) -> Option<(f64, f64)> {
        let mut points = self.grips.values().filter_map(|g| match g {
            Grip::Pointer { at } => Some(*at),
            _ => None,
        });
        let a = points.next()?;
        let b = points.next().unwrap_or(a);
        Some(((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0))
    }

    fn menu_changed(&mut self) {
        self.release_all();
        input::set_menu_touch(self.direct_touch());
        self.relabel();
    }

    fn is_wheel(&self, idx: usize) -> bool {
        let Some(s) = BUTTONS.get(idx) else { return false };
        if s.nav { return false; }
        match self.spec_act(idx).map(|(_, a)| a) {
            Some(Key("Tab")) | Some(Key("AltLeft")) => true,
            Some(Key("KeyQ")) => self.in_car,
            _ => false,
        }
    }

    fn spec_act(&self, idx: usize) -> Option<(&'static str, Act)> {
        let s = BUTTONS.get(idx)?;
        if self.menu.keys_visible() {
            if s.nav {
                return if self.in_car { s.in_car } else { s.on_foot };
            }
            match s.on_foot.map(|(_, a)| a) {
                Some(Act::KeyNav("Escape")) | Some(Act::NavToggle) => return s.on_foot,
                Some(Act::Key("ArrowUp")) if !self.menu.pause_requested => return s.on_foot,
                _ => return None,
            }
        }
        if self.menu.pause_requested {
            return match s.on_foot.map(|(_, a)| a) {
                Some(KeyNav("Escape")) | Some(NavToggle) => s.on_foot,
                _ => None,
            };
        }
        if s.nav { return None; }
        if self.in_car { s.in_car } else { s.on_foot }
    }

    fn relabel(&mut self) {
        for i in 0..self.buttons.len() {
            let act = self.spec_act(i);
            let b = &self.buttons[i];
            // MENU and CONSOLE are exempt: they live on the window view
            // and must stay visible even when the nav-keys menu is open
            // or pause is requested (their labels never change, so
            // there is nothing to re-text when the act is None).
            let hide = act.is_none() && i != MENU_IDX && i != CONSOLE_IDX;
            set_hidden(&b.view, hide);
            if let Some((text, _)) = act { set_text(&b.label, text); }
        }
        set_hidden(&self.stick_base, self.direct_touch());
        set_hidden(&self.stick_knob, self.direct_touch());
        self.restyle();
    }

    fn apply_layout(&mut self) {
        let (sx, sy, sw, sh) = self.safe;
        let b_scale = button_scale();
        let (b_ox, b_oy) = (button_offset_x(), button_offset_y());
        let (s_ox, s_oy) = (stick_offset_x(), stick_offset_y());

        let place = |a: Anchor| match a {
            BottomRight(dx, dy) => (sx + sw - dx * b_scale - b_ox, sy + sh - dy * b_scale - b_oy),
            TopLeft(dx, dy) => (sx + dx * b_scale, sy + dy * b_scale),
            TopRight(dx, dy) => (sx + sw - dx * b_scale, sy + dy * b_scale),
            Nav(dx, dy) => (sx + sw / 2.0 + dx * nav_scale(sw), sy + 90.0 * b_scale + dy),
        };

        for (i, b) in self.buttons.iter_mut().enumerate() {
            let Some(s) = BUTTONS.get(i) else { continue };
            let (c_dx, c_dy, c_scale) = if i < 16 { custom_button_layout(i) } else { (0.0, 0.0, 1.0) };
            b.radius = s.radius * if s.nav { nav_scale(sw) } else { b_scale * c_scale };
            let mut center = place(s.anchor);
            center.0 += c_dx;
            center.1 += c_dy;
            b.center = center;
            unsafe {
                let _: () = msg_send![&*b.view, setFrame: rect(b.center.0 - b.radius, b.center.1 - b.radius, b.radius * 2.0, b.radius * 2.0)];
                let layer: Retained<AnyObject> = msg_send![&*b.view, layer];
                let _: () = msg_send![&*layer, setCornerRadius: b.radius];
                let _: () = msg_send![&*b.label, setFrame: rect(0.0, 0.0, b.radius * 2.0, b.radius * 2.0)];
            }
        }

        let (j_dx, j_dy, j_scale) = custom_button_layout(16);
        let stick_radius = STICK_RADIUS * b_scale * j_scale;
        let knob_radius = KNOB_RADIUS * b_scale * j_scale;
        self.stick_home = (sx + 40.0 + stick_radius + s_ox + j_dx, sy + sh - 30.0 - stick_radius - s_oy + j_dy);
        unsafe {
            let _: () = msg_send![&*self.stick_base, setFrame: rect(self.stick_home.0 - stick_radius, self.stick_home.1 - stick_radius, stick_radius * 2.0, stick_radius * 2.0)];
            let layer: Retained<AnyObject> = msg_send![&*self.stick_base, layer];
            let _: () = msg_send![&*layer, setCornerRadius: stick_radius];

            let _: () = msg_send![&*self.stick_knob, setFrame: rect(self.stick_home.0 - knob_radius, self.stick_home.1 - knob_radius, knob_radius * 2.0, knob_radius * 2.0)];
            let layer_k: Retained<AnyObject> = msg_send![&*self.stick_knob, layer];
            let _: () = msg_send![&*layer_k, setCornerRadius: knob_radius];
        }
        self.restyle();
    }

    fn restyle(&self) {
        let base_alpha = button_opacity();
        let pressed: HashSet<usize> = self.grips.values().filter_map(|g| if let Grip::Button { idx, .. } = g { Some(*idx) } else { None }).collect();
        for (i, b) in self.buttons.iter().enumerate() {
            let latched = self.aim_latched && matches!(self.spec_act(i), Some((_, AimToggle)))
                || self.menu.keys_visible() && matches!(self.spec_act(i), Some((_, NavToggle)));
            set_alpha_bg(&b.view, if pressed.contains(&i) { (base_alpha + 0.25).min(0.95) } else if latched { (base_alpha + 0.15).min(0.9) } else { base_alpha });
        }
    }

    fn button_at(&self, p: (f64, f64)) -> Option<usize> {
        (0..self.buttons.len()).filter(|&i| self.spec_act(i).is_some()).filter(|&i| {
            let b = &self.buttons[i];
            let r = b.radius + if BUTTONS.get(i).map(|s| s.nav).unwrap_or(false) { 0.0 } else { 8.0 };
            (p.0 - b.center.0).powi(2) + (p.1 - b.center.1).powi(2) <= r * r
        }).min_by(|&a, &b| {
            let distance = |i: usize| (p.0 - self.buttons[i].center.0).hypot(p.1 - self.buttons[i].center.1);
            distance(a).total_cmp(&distance(b))
        })
    }

    fn in_stick_zone(&self, p: (f64, f64)) -> bool {
        let (sx, sy, sw, _) = self.safe;
        let s_ox = stick_offset_x();
        let s_oy = stick_offset_y();
        let (j_dx, j_dy, _) = custom_button_layout(16);
        let dx = p.0 - self.stick_home.0;
        let dy = p.1 - self.stick_home.1;
        let reach = STICK_RADIUS * 2.2;
        (dx * dx + dy * dy <= reach * reach) || (p.0 < sx + sw * 0.45 + s_ox + j_dx && p.1 > sy + 60.0 - s_oy + j_dy)
    }

    fn touch(&mut self, t: &Touch) {
        // scale_factor() is never 0 in practice, but a 0/NaN scale
        // used to turn every touch coordinate into Inf/NaN, which
        // pointer_position then had to clamp back.
        let scale = if self.scale.is_finite() && self.scale > 0.0 { self.scale } else { 1.0 };
        let p = (t.location.x / scale, t.location.y / scale);
        match t.phase {
            TouchPhase::Started => {
                if let Some(idx) = self.button_at(p) {
                    // button_at only returns an index whose spec_act
                    // is Some, but the two calls can disagree after a
                    // menu-state change in between; skip instead of
                    // panicking on the touch hot path.
                    let Some(act) = self.spec_act(idx).map(|(_, a)| a) else { return };
                    match Some(act) {
                        Some(AimToggle) if !hold_aim() => self.aim_latched = !self.aim_latched,
                        Some(NavToggle) => { self.menu.toggle_keys(); self.menu_changed(); }
                        Some(KeyNav("Escape")) => {
                            // Do not merge two Escape presses from rapid taps or two fingers.
                            if self.held.contains("Escape") { return; }
                            self.menu.pause();
                            self.menu_changed();
                        }
                        Some(Home) => {
                            #[cfg(target_os = "ios")]
                            {
                                extern "C" { fn muguet_open_menu(); }
                                unsafe { muguet_open_menu(); }
                            }
                        }
                        Some(FirstPerson) => {
                            crate::mp::request_toggle_first_person();
                            input::key("KeyV", true, false, None, false);
                        }
                        Some(SpawnCar) => {
                            crate::mp::request_spawn_first_vehicle();
                        }
                        Some(Console) => {
                            #[cfg(target_os = "ios")]
                            {
                                extern "C" { fn muguet_show_console(); }
                                unsafe { muguet_show_console(); }
                            }
                        }
                        _ => {}
                    }
                    self.grips.insert(t.id, Grip::Button { idx, act, start: p, last: p, motion: crate::aim::DragLook::new(p) });
                } else if self.direct_touch() {
                    let count = self.grips.values().filter(|g| matches!(g, Grip::Pointer { .. })).count();
                    if count < 2 {
                        self.grips.insert(t.id, Grip::Pointer { at: p });
                        if count == 0 && !self.pinching {
                            self.pointer_at(p);
                            eprintln!("[touch] menu finger down at {:.0},{:.0}", p.0, p.1);
                        }
                        if count == 1 {
                            self.pinching = true;
                            self.pinch.reset();
                            // Release dragging before moving to the pinch pivot.
                            self.apply();
                            if let Some(center) = self.pointer_center() { self.pointer_at(center); }
                            eprintln!("[touch] menu pinch started");
                        }
                    }
                } else if self.in_stick_zone(p) && !self.grips.values().any(|g| matches!(g, Grip::Stick { .. })) {
                    self.grips.insert(t.id, Grip::Stick { origin: p, at: p });
                } else {
                    self.grips.insert(t.id, Grip::Look { motion: crate::aim::DragLook::new(p) });
                }
            }
            TouchPhase::Moved => {
                let before = self.pointer_distance();
                if let Some(Grip::Pointer { at }) = self.grips.get_mut(&t.id) {
                    *at = p;
                    if let (Some(before), Some(after)) = (before, self.pointer_distance()) {
                        if let Some(center) = self.pointer_center() { self.pointer_at(center); }
                        input::wheel(self.pinch.update(before, after));
                    } else if !self.pinching {
                        self.pointer_at(p);
                    }
                    self.apply();
                    return;
                }
                let wheel = matches!(self.grips.get(&t.id), Some(Grip::Button { idx, .. }) if self.is_wheel(*idx));
                let aimed = self.mouse & 2 != 0;
                let camera_button = matches!(self.grips.get(&t.id), Some(Grip::Button { idx, .. })
                    if *idx == 0 && !self.in_car || matches!(self.spec_act(*idx), Some((_, AimToggle))));
                match self.grips.get_mut(&t.id) {
                    Some(Grip::Stick { at, .. }) => *at = p,
                    Some(Grip::Button { last, .. }) if wheel => *last = p,
                    Some(Grip::Look { motion }) => {
                        let delta = motion.move_to(p);
                        if !self.menu.nav {
                            let (dx, dy) = crate::aim::scale_delta(delta, LOOK_GAIN * touch_sensitivity(), aimed, aim_sensitivity());
                            input::mouse_delta_f(dx, dy);
                        }
                    }
                    Some(Grip::Button { last, motion, .. }) => {
                        *last = p;
                        if camera_button {
                            let (dx, dy) = crate::aim::scale_delta(motion.move_to(p), LOOK_GAIN * touch_sensitivity(), aimed, aim_sensitivity());
                            input::mouse_delta_f(dx, dy);
                        }
                    }
                    Some(Grip::Pointer { .. }) | None => {}
                }
            }
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if matches!(self.grips.get(&t.id), Some(Grip::Pointer { .. })) && !self.pinching {
                    self.pointer_at(p);
                }
                self.grips.remove(&t.id);
                if !self.grips.values().any(|g| matches!(g, Grip::Pointer { .. })) {
                    self.pinching = false;
                    self.pinch.reset();
                }
                if t.phase == TouchPhase::Cancelled { self.mouse_since = [std::time::Instant::now() - MIN_HOLD; 2]; }
            }
        }
        self.apply();
    }

    // Restricted hit-test for the hidden state: only MENU and CONSOLE
    // (the two buttons reparented to the window view). Geometry only —
    // spec_act can be None in nav/pause states, but these buttons stay
    // visible there, so a tap on them must fire. One-shot actions only;
    // no grip is recorded, because later phases of the same touch are
    // still dropped while hidden.
    fn touch_always_visible(&self, t: &Touch) {
        let scale = if self.scale.is_finite() && self.scale > 0.0 { self.scale } else { 1.0 };
        let p = (t.location.x / scale, t.location.y / scale);
        for &idx in &[MENU_IDX, CONSOLE_IDX] {
            let Some(b) = self.buttons.get(idx) else { continue };
            let r = b.radius + 8.0;
            if (p.0 - b.center.0).powi(2) + (p.1 - b.center.1).powi(2) > r * r { continue; }
            match idx {
                MENU_IDX => {
                    #[cfg(target_os = "ios")]
                    {
                        extern "C" { fn muguet_open_menu(); }
                        unsafe { muguet_open_menu(); }
                    }
                }
                CONSOLE_IDX => {
                    #[cfg(target_os = "ios")]
                    {
                        extern "C" { fn muguet_show_console(); }
                        unsafe { muguet_show_console(); }
                    }
                }
                _ => {}
            }
            return;
        }
    }

    fn apply(&mut self) {
        let mut keys: HashSet<&'static str> = HashSet::new();
        let mut mouse = if self.aim_latched && !self.in_car { 2u8 } else { 0 };
        let mut stick = None;
        let mut horn = false;
        for g in self.grips.values() {
            match g {
                Grip::Stick { origin, at } => stick = Some((*origin, *at)),
                Grip::Button { act, .. } => match Some(*act) {
                    Some(Key(k)) | Some(KeyNav(k)) => { keys.insert(k); }
                    Some(Mouse(bit)) => {
                        mouse |= bit;
                        if bit == 1 && fire_aim() && !self.in_car { mouse |= 2; }
                    }
                    Some(AimToggle) if hold_aim() => mouse |= 2,
                    Some(Horn) => horn = true,
                    _ => {}
                },
                Grip::Look { .. } => {}
                Grip::Pointer { .. } if !self.pinching => mouse |= 1,
                Grip::Pointer { .. } => {}
            }
        }
        if let Some((o, at)) = stick {
            let sr = STICK_RADIUS * button_scale();
            let (mut dx, mut dy) = (at.0 - o.0, at.1 - o.1);
            let len = (dx * dx + dy * dy).sqrt();
            let k = if len > sr { sr / len } else { 1.0 };
            dx *= k;
            dy *= k;
            let (nx, ny) = (dx / sr, dy / sr);
            if nx < -0.35 { keys.insert("KeyA"); }
            if nx > 0.35 { keys.insert("KeyD"); }
            if self.in_car {
                if ny < -0.6 { keys.insert("Numpad8"); }
                if ny > 0.6 { keys.insert("Numpad2"); }
            } else {
                if ny < -0.35 { keys.insert("KeyW"); }
                if ny > 0.35 { keys.insert("KeyS"); }
            }
            let sprint = !self.in_car && len > sr * SPRINT_REACH;
            if sprint { keys.insert("ShiftLeft"); }
            set_alpha_bg(&self.stick_knob, if sprint { 0.65 } else { 0.3 });
            move_to(&self.stick_base, o);
            move_to(&self.stick_knob, (o.0 + dx, o.1 + dy));
        } else {
            set_alpha_bg(&self.stick_knob, 0.3);
            move_to(&self.stick_base, self.stick_home);
            move_to(&self.stick_knob, self.stick_home);
        }
        crate::pad::HORN_TOUCH.store(horn, std::sync::atomic::Ordering::Relaxed);
        let now = std::time::Instant::now();
        let young = |t: Option<&std::time::Instant>| t.is_some_and(|t| now - *t < MIN_HOLD);
        self.lingering = false;
        for k in self.held.clone() {
            if keys.contains(k) { continue; }
            if young(self.since.get(k)) { keys.insert(k); self.lingering = true; continue; }
            input::key(k, false, false, None, false);
            self.since.remove(k);
        }
        for k in keys.difference(&self.held) {
            crate::mp::key_pressed(k);
            input::key(k, true, false, None, false);
            self.since.insert(k, now);
        }
        self.held = keys;
        for (i, (bit, dom)) in [(1u8, 0usize), (2, 2)].into_iter().enumerate() {
            let hold = if self.direct_touch() { std::time::Duration::from_millis(80) } else { MOUSE_HOLD };
            if !self.pinching && self.mouse & bit != 0 && mouse & bit == 0 && now - self.mouse_since[i] < hold {
                mouse |= bit;
                self.lingering = true;
            }
            if (mouse ^ self.mouse) & bit != 0 {
                input::button(dom, mouse & bit != 0);
                if mouse & bit != 0 { self.mouse_since[i] = now; }
            }
        }
        self.mouse = mouse;
        // Keep the final position valid after release and throughout a pinch.
        // The engine can consume button-up / wheel on a later frame.
        self.restyle();
    }

    fn release_all(&mut self) {
        self.grips.clear();
        self.pinching = false;
        self.pinch.reset();
        self.aim_latched = false;
        self.since.clear();
        self.mouse_since = [std::time::Instant::now() - MIN_HOLD; 2];
        self.apply();
    }
}

pub fn touch(t: &Touch) {
    // try_borrow_mut: a callback inside a borrow that re-enters touch()
    // used to panic the RefCell on the event thread. Drop the
    // re-entrant event instead.
    OVERLAY.with(|cell| {
        if let Ok(mut guard) = cell.try_borrow_mut() {
            if let Some(o) = guard.as_mut() {
                if !o.hidden && !o.loading {
                    o.touch(t);
                } else if o.hidden && t.phase == TouchPhase::Started {
                    // The overlay root is hidden while a controller is
                    // connected, so the normal entry drops everything.
                    // MENU and CONSOLE live on the window view and stay
                    // visible: still let those two fire.
                    o.touch_always_visible(t);
                }
            }
        }
    });
}

pub fn refresh() -> bool {
    OVERLAY.with(|cell| {
        let Ok(mut guard) = cell.try_borrow_mut() else { return false };
        let Some(o) = guard.as_mut() else { return false };
        if o.lingering { o.apply(); }
        let mut wheeling = false;
        for g in o.grips.values() {
            if let Grip::Button { idx, start, last, .. } = g {
                if !o.is_wheel(*idx) {
                    continue;
                }
                wheeling = true;
                let (dx, dy) = (last.0 - start.0, last.1 - start.1);
                let len = (dx * dx + dy * dy).sqrt();
                if len > WHEEL_DEADZONE {
                    let push = WHEEL_PUSH * ((len - WHEEL_DEADZONE) / WHEEL_FULL).min(1.0);
                    input::mouse_delta_f(dx / len * push, dy / len * push);
                }
            }
        }
        let hide = crate::pad::ACTIVE.load(std::sync::atomic::Ordering::Relaxed) && !o.loading;
        if let Some(status) = crate::mp::network_status() {
            set_text(&o.network_label, &status);
            set_hidden(&o.network_label, false);
        } else { set_hidden(&o.network_label, true); }
        // RAM tracker: the GPU thread writes the latest line into
        // debug state once a second; this main-thread tick applies it
        // to the label. Shown only once the game has started, and kept
        // visible while a controller is connected (the label is not
        // part of the overlay root, which hides then).
        if crate::gpu::STARTED.load(std::sync::atomic::Ordering::Relaxed) {
            let (text, tier) = crate::debug::ram_tracker();
            if !text.is_empty() {
                if text != o.ram_text {
                    o.ram_text = text.clone();
                    set_text(&o.ram_label, &text);
                    let (r, g, b) = match tier {
                        3 => (1.0, 0.3, 0.3),
                        2 => (1.0, 0.65, 0.2),
                        1 => (1.0, 0.85, 0.3),
                        _ => (0.45, 0.95, 0.45),
                    };
                    unsafe { let _: () = msg_send![&*o.ram_label, setTextColor: &*rgb(r, g, b, 0.95)]; }
                }
                set_hidden(&o.ram_label, false);
            }
        } else {
            set_hidden(&o.ram_label, true);
        }

        input::set_menu_touch(!hide && o.direct_touch());
        if !hide { input::set_locked(!o.direct_touch()); }
        if !crate::gpu::SUSPENDED.load(std::sync::atomic::Ordering::Relaxed) { input::set_focus(true); }
        if hide != o.hidden {
            o.hidden = hide;
            if hide { o.release_all(); }
            set_hidden(&o.root, hide);
        }
        let in_car = crate::pad::IN_VEHICLE.load(std::sync::atomic::Ordering::Relaxed);
        if in_car != o.in_car && !o.hidden {
            o.grips.retain(|_, g| !matches!(g, Grip::Button { .. }));
            o.in_car = in_car;
            if in_car { o.aim_latched = false; }
            o.apply();
            o.relabel();
        }
        o.lingering || wheeling
    })
}

pub fn loading(message: Option<&str>) {
    OVERLAY.with(|cell| {
        if let Ok(mut guard) = cell.try_borrow_mut() {
            if let Some(o) = guard.as_mut() {
                if message.is_some() && !o.loading { o.release_all(); }
                o.loading = message.is_some();
                if let Some(message) = message { set_text(&o.loading_label, message); }
                set_hidden(&o.loading_label, message.is_none());
            }
        }
    });
}

pub fn release() {
    OVERLAY.with(|cell| { if let Ok(mut guard) = cell.try_borrow_mut() { if let Some(o) = guard.as_mut() { o.release_all(); } } });
}
