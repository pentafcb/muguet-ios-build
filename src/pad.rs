// muguet - pad.rs
// Constantin Clerc (c22dev) - 0.1

use crate::input;
use objc2_game_controller::{GCController, GCControllerButtonInput, GCExtendedGamepad};
use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub static ACTIVE: AtomicBool = AtomicBool::new(false);

pub static IN_VEHICLE: AtomicBool = AtomicBool::new(false);

pub static HORN_PAD: AtomicBool = AtomicBool::new(false);
pub static HORN_TOUCH: AtomicBool = AtomicBool::new(false);
pub fn horn_held() -> bool {
    HORN_PAD.load(Ordering::Relaxed) || HORN_TOUCH.load(Ordering::Relaxed)
}

struct State {
    held: HashSet<&'static str>,
    buttons: u8,
    last: Instant,
    down_since: Option<Instant>,
}
static STATE: Mutex<Option<State>> = Mutex::new(None);

const SWITCH_HOLD: Duration = Duration::from_millis(300);
const STICK_DEADZONE: f32 = 0.3;
const LOOK_DEADZONE: f32 = 0.12;

// Base look rate in mouse px/s at full stick, before the pad sensitivity
// setting and the shared mouse sensitivity. Raised from 700: at 700 the
// sustained full-stick rate was only ~2200-3000 px/s (and slowest at 120 Hz,
// see below), while one fast touch swipe delivers ~2000+ px in a single
// event, so the pad could never turn as fast as a finger.
const LOOK_SPEED: f64 = 1400.0;
// Response curve exponent. Was 1.8, which crushed mid-stick: 50% deflection
// gave only 22% of max speed. At 1.5, 50% gives 28% and 75% gives 61%.
const LOOK_CURVE: f64 = 1.5;

// Parsed once, not on every poll: the old code ran std::env::var +
// parse on every poll() and every look event. NaN/inf are rejected
// (parse accepts "NaN", and clamp() lets NaN through, which used to
// zero the look rate with no error).
static PAD_SENS: std::sync::LazyLock<f64> = std::sync::LazyLock::new(|| {
    std::env::var("MUGUET_PAD_SENS").ok().and_then(|v| v.parse::<f64>().ok())
        .filter(|v| v.is_finite()).map(|v| v.clamp(0.1, 10.0)).unwrap_or(1.0)
});
static AIM_SENS: std::sync::LazyLock<f64> = std::sync::LazyLock::new(|| {
    std::env::var("MUGUET_AIM_SENS").ok().and_then(|v| v.parse::<f64>().ok())
        .filter(|v| v.is_finite()).map(|v| v.clamp(0.05, 10.0)).unwrap_or(0.4)
});

fn pad_sensitivity() -> f64 {
    *PAD_SENS
}

fn gamepad() -> Option<objc2::rc::Retained<GCExtendedGamepad>> {
    unsafe { GCController::controllers().iter().find_map(|c| c.extendedGamepad()) }
}

fn down(b: &GCControllerButtonInput) -> bool {
    unsafe { b.isPressed() }
}

pub fn poll() -> bool {
    let Some(gp) = gamepad() else {
        if ACTIVE.swap(false, Ordering::Relaxed) {
            if let Some(st) = STATE.lock().unwrap_or_else(|e| e.into_inner()).take() { release(st); }
            eprintln!("[pad] controller disconnected");
        }
        return false;
    };
    if !ACTIVE.swap(true, Ordering::Relaxed) {
        eprintln!("[pad] controller connected (look base {LOOK_SPEED} px/s, pad sens {}, mouse sens {})", pad_sensitivity(), crate::input::mouse_sensitivity());
        crate::debug::log_line(&format!("pad connected: look base {LOOK_SPEED} px/s, pad sens {}, mouse sens {}, effective full-stick {} px/s",
            pad_sensitivity(), crate::input::mouse_sensitivity(), LOOK_SPEED * pad_sensitivity() * crate::input::mouse_sensitivity()));
    }
    let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    let st = guard.get_or_insert_with(|| State { held: HashSet::new(), buttons: 0, last: Instant::now(), down_since: None });
    let dt = st.last.elapsed().as_secs_f64().min(0.05);
    st.last = Instant::now();

    let in_car = IN_VEHICLE.load(Ordering::Relaxed);
    let mut keys: HashSet<&'static str> = HashSet::new();
    let mut buttons = 0u8;
    unsafe {
        let ls = gp.leftThumbstick();
        let (lx, ly) = (ls.xAxis().value(), ls.yAxis().value());
        if lx < -STICK_DEADZONE { keys.insert("KeyA"); }
        if lx > STICK_DEADZONE { keys.insert("KeyD"); }
        if in_car {
            if ly > STICK_DEADZONE { keys.insert("Numpad8"); }
            if ly < -STICK_DEADZONE { keys.insert("Numpad2"); }
            if gp.rightTrigger().value() > 0.2 { keys.insert("KeyW"); }
            if gp.leftTrigger().value() > 0.2 { keys.insert("KeyS"); }
            if down(&gp.rightShoulder()) { keys.insert("Space"); }
            HORN_PAD.store(gp.leftThumbstickButton().is_some_and(|b| down(&b)), Ordering::Relaxed);
            if down(&gp.buttonX()) { keys.insert("Space"); }
        } else {
            if ly > STICK_DEADZONE { keys.insert("KeyW"); }
            if ly < -STICK_DEADZONE { keys.insert("KeyS"); }
            if gp.rightTrigger().value() > 0.2 { buttons |= 1; }
            if gp.leftTrigger().value() > 0.2 { buttons |= 2; }
            if down(&gp.buttonA()) { keys.insert("ShiftLeft"); }
            if down(&gp.buttonX()) { keys.insert("Space"); }
            if down(&gp.rightShoulder()) { keys.insert("KeyQ"); }
            if gp.leftThumbstickButton().is_some_and(|b| down(&b)) { keys.insert("ControlLeft"); }
        }
        if down(&gp.buttonA()) { keys.insert("Enter"); }
        if down(&gp.buttonB()) { keys.insert("KeyR"); keys.insert("Backspace"); }
        if down(&gp.buttonY()) { keys.insert("KeyF"); }
        if down(&gp.leftShoulder()) { keys.insert("Tab"); }
        if gp.rightThumbstickButton().is_some_and(|b| down(&b)) { keys.insert("KeyC"); }
        let dp = gp.dpad();
        if down(&dp.up()) { keys.insert("ArrowUp"); }
        if down(&dp.down()) {
            let since = *st.down_since.get_or_insert_with(Instant::now);
            if since.elapsed() >= SWITCH_HOLD { keys.insert("AltLeft"); } else { keys.insert("ArrowDown"); }
        } else {
            st.down_since = None;
        }
        if down(&dp.left()) { keys.insert("ArrowLeft"); }
        if down(&dp.right()) { keys.insert("ArrowRight"); }
        if down(&gp.buttonMenu()) { keys.insert("Escape"); }
        if gp.buttonOptions().is_some_and(|b| down(&b)) { keys.insert("KeyV"); }

        let rs = gp.rightThumbstick();
        let curve = |v: f32| -> f64 {
            let a = v.abs();
            if a < LOOK_DEADZONE { 0.0 } else { (((a - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE)) as f64).powf(LOOK_CURVE).copysign(v as f64) }
        };
        let (raw_x, raw_y) = (rs.xAxis().value(), rs.yAxis().value());
        let (cx, cy) = (curve(raw_x), -curve(raw_y));
        if cx != 0.0 || cy != 0.0 {
            let aimed = buttons & 2 != 0 && !in_car;
            let aim_scale = *AIM_SENS;
            // Flat rate on purpose. The old path ran through
            // aim::scale_delta, whose per-event acceleration depended on the
            // per-poll delta size, so full-stick speed changed with the poll
            // rate: ~3500 px/s at 30 Hz, ~3000 at 60 Hz, ~2200 at 120 Hz.
            // Rate is now LOOK_SPEED * pad_sens px/s before the shared
            // mouse sensitivity, at any frame rate. The aim multiplier stays
            // separate and is not touched by the pad sensitivity setting.
            let speed = LOOK_SPEED * pad_sensitivity();
            let aim = if aimed { aim_scale.clamp(0.05, 10.0) } else { 1.0 };
            let (dx, dy) = (cx * speed * dt * aim, cy * speed * dt * aim * 0.85);
            crate::debug::note_pad((raw_x, raw_y), (cx, cy), dt, (dx, dy), speed * crate::input::mouse_sensitivity(), aimed);
            input::mouse_delta_f(dx, dy);
        }
    }

    if cfg!(target_os = "ios") { input::set_locked(true); }

    for k in st.held.difference(&keys) { input::key(k, false, false, None, false); }
    for k in keys.difference(&st.held) {
        crate::mp::key_pressed(k);
        input::key(k, true, false, None, false);
    }
    st.held = keys;
    for (bit, dom) in [(1u8, 0usize), (2, 2)] {
        if (buttons ^ st.buttons) & bit != 0 { input::button(dom, buttons & bit != 0); }
    }
    st.buttons = buttons;
    true
}

fn release(st: State) {
    for k in st.held { input::key(k, false, false, None, false); }
    if st.buttons & 1 != 0 { input::button(0, false); }
    if st.buttons & 2 != 0 { input::button(2, false); }
}
