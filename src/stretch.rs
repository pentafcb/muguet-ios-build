// Stretched Resolution built-in option: render the game at a narrower
// aspect (4:3 or 5:4) at the same height and let the display stretch it
// to fill the wide screen — the FiveM PvP trick from the "+120 FPS"
// videos. On PC the stretch is done by the GPU driver (full-panel
// scaling): the game just renders at the 4:3 resolution. This port has
// no GPU control panel, but the same stretch already happens here: the
// surface is configured at the back-buffer size and the iOS compositor
// displays it stretched to the fullscreen window — a 0.5 render scale
// fills the screen today instead of showing a small centred image. So
// the host only has to render narrow: the engine gets the narrow size
// via -width/-height, its camera and HUD lay out in the narrow aspect,
// and the image stretches horizontally, exactly like on PC.
// Pure logic lives here so the harness can check it; app.rs applies it
// in backbuffer_size(), config.rs reads the launcher picker.

pub fn parse_stretch(s: &str) -> Option<&'static str> {
    match s.trim().to_ascii_lowercase().as_str() {
        "off" => Some("off"),
        "4:3" | "4x3" | "4/3" => Some("4:3"),
        "5:4" | "5x4" | "5/4" => Some("5:4"),
        _ => None,
    }
}

pub fn stretch_ratio(look: &str) -> Option<f64> {
    match parse_stretch(look)? {
        "4:3" => Some(4.0 / 3.0),
        "5:4" => Some(5.0 / 4.0),
        _ => None,
    }
}

pub fn stretch_active(look: &str) -> bool {
    stretch_ratio(look).is_some()
}

pub fn env_stretch() -> Option<String> {
    std::env::var("MUGUET_STRETCH").ok()
}

// Narrow width for a given height at the chosen aspect. Even-rounded
// like backbuffer_size, clamped to the same 320..2560 range. Off (or
// an unknown value) returns None and the caller keeps the full width.
pub fn stretch_width(height: i32, look: &str) -> Option<i32> {
    let ratio = stretch_ratio(look)?;
    let w = ((height as f64 * ratio) as i32) & !1;
    Some(w.clamp(320, 2560))
}

// Apply the launcher's stretch choice to a computed back-buffer size:
// keep the height, narrow the width to the chosen aspect. Called from
// backbuffer_size() in app.rs on both paths (MUGUET_RES override and
// window x scale), so a custom resolution composes with the stretch.
pub fn apply_stretch(w: i32, h: i32) -> (i32, i32) {
    let Some(look) = env_stretch() else {
        return (w, h);
    };
    match stretch_width(h, &look) {
        Some(sw) => (sw, h),
        None => (w, h),
    }
}
