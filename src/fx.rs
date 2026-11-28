// fx.rs — Post FX: a ReShade-style post-processing chain for the
// Muguet host. ReShade itself cannot run here (Windows DLL hooking
// DirectX/OpenGL/Vulkan; this port renders through wgpu/Metal and
// there is no graphics API to hook), so this is the same idea built
// the host's way: the game renders to its back buffer, then WGSL
// fullscreen passes in gpu.rs present() run on it before the blit
// to the screen. No depth-buffer effects in this build: the host
// owns the pipeline but the engine's depth layout is unverified,
// so anything needing depth (AO, depth of field) is a follow-up,
// not wired here.
// Live state follows the NO_TRAFFIC pattern: atomics read by
// present() every frame, written by the console command and the
// in-game menu, synced from the MUGUET_FX env var at session start.
// Visual only: it never touches game state, so it is allowed in
// multiplayer too. Default is everything OFF, so the game looks
// identical until the player opts in.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Mutex, MutexGuard};

// Effect value ranges. Kept in one place so the console, the menu
// and the harness all clamp the same way.
fn clamp_value(name: &str, v: f32) -> Option<f32> {
    if !v.is_finite() {
        return None;
    }
    let clamped = match name {
        "sat" | "con" => v.clamp(0.0, 2.0),
        "bri" => v.clamp(-0.5, 0.5),
        "sharp" | "vig" => v.clamp(0.0, 1.0),
        "bloom" => v.clamp(0.0, 2.0),
        "thr" => v.clamp(0.0, 1.0),
        _ => return None,
    };
    Some(clamped)
}

// Human-readable range for the console help / error lines.
fn value_range(name: &str) -> &'static str {
    match name {
        "sat" | "con" => "0.00-2.00",
        "bri" => "-0.50-0.50",
        "sharp" | "vig" => "0.00-1.00",
        "bloom" => "0.00-2.00",
        "thr" => "0.00-1.00",
        _ => "?",
    }
}

// The whole effect set in one Copy struct. This is what presets and
// the state file store, and what the uniform buffer is built from.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct FxParams {
    pub grade: bool,
    pub sat: f32,
    pub con: f32,
    pub bri: f32,
    pub sharpen: bool,
    pub sharp: f32,
    pub fxaa: bool,
    pub vignette: bool,
    pub vig: f32,
    pub bloom: bool,
    pub bloom_strength: f32,
    pub bloom_threshold: f32,
}

impl Default for FxParams {
    fn default() -> Self {
        FxParams {
            grade: false,
            sat: 1.0,
            con: 1.0,
            bri: 0.0,
            sharpen: false,
            sharp: 0.5,
            fxaa: false,
            vignette: false,
            vig: 0.45,
            bloom: false,
            bloom_strength: 0.6,
            bloom_threshold: 0.8,
        }
    }
}

impl FxParams {
    // Clamp every value into its range (a preset or state file may
    // carry anything). Toggles are booleans already.
    fn clamped(mut self) -> Self {
        self.sat = self.sat.clamp(0.0, 2.0);
        self.con = self.con.clamp(0.0, 2.0);
        self.bri = self.bri.clamp(-0.5, 0.5);
        self.sharp = self.sharp.clamp(0.0, 1.0);
        self.vig = self.vig.clamp(0.0, 1.0);
        self.bloom_strength = self.bloom_strength.clamp(0.0, 2.0);
        self.bloom_threshold = self.bloom_threshold.clamp(0.0, 1.0);
        // Non-finite values survive clamp (NaN stays NaN), so scrub
        // them to defaults instead of letting NaN reach the shader.
        if !self.sat.is_finite() {
            self.sat = 1.0;
        }
        if !self.con.is_finite() {
            self.con = 1.0;
        }
        if !self.bri.is_finite() {
            self.bri = 0.0;
        }
        if !self.sharp.is_finite() {
            self.sharp = 0.5;
        }
        if !self.vig.is_finite() {
            self.vig = 0.45;
        }
        if !self.bloom_strength.is_finite() {
            self.bloom_strength = 0.6;
        }
        if !self.bloom_threshold.is_finite() {
            self.bloom_threshold = 0.8;
        }
        self
    }

    pub fn any_on(&self) -> bool {
        self.grade || self.sharpen || self.fxaa || self.vignette || self.bloom
    }
}

// Live state: one atomic per field, so present() (GPU thread) can
// read without locking and the console/menu (main thread) can write
// without locking. f32 values are stored as raw bits.
static GRADE_ON: AtomicBool = AtomicBool::new(false);
static SAT: AtomicU32 = AtomicU32::new(0x3f800000);
static CON: AtomicU32 = AtomicU32::new(0x3f800000);
static BRI: AtomicU32 = AtomicU32::new(0);
static SHARPEN_ON: AtomicBool = AtomicBool::new(false);
static SHARP: AtomicU32 = AtomicU32::new(0x3f000000);
static FXAA_ON: AtomicBool = AtomicBool::new(false);
static VIGNETTE_ON: AtomicBool = AtomicBool::new(false);
static VIG: AtomicU32 = AtomicU32::new(0x3ee66666);
static BLOOM_ON: AtomicBool = AtomicBool::new(false);
static BLOOM_STRENGTH: AtomicU32 = AtomicU32::new(0x3f19999a);
static BLOOM_THRESHOLD: AtomicU32 = AtomicU32::new(0x3f4ccccd);
// Set on any live change; present() consumes it to rewrite the
// uniform buffer, so a steady frame costs no uniform upload.
static FX_DIRTY: AtomicBool = AtomicBool::new(true);

fn load_f32(a: &AtomicU32) -> f32 {
    f32::from_bits(a.load(Ordering::Relaxed))
}

fn store_f32(a: &AtomicU32, v: f32) {
    a.store(v.to_bits(), Ordering::Relaxed);
}

pub fn fx_snapshot() -> FxParams {
    FxParams {
        grade: GRADE_ON.load(Ordering::Relaxed),
        sat: load_f32(&SAT),
        con: load_f32(&CON),
        bri: load_f32(&BRI),
        sharpen: SHARPEN_ON.load(Ordering::Relaxed),
        sharp: load_f32(&SHARP),
        fxaa: FXAA_ON.load(Ordering::Relaxed),
        vignette: VIGNETTE_ON.load(Ordering::Relaxed),
        vig: load_f32(&VIG),
        bloom: BLOOM_ON.load(Ordering::Relaxed),
        bloom_strength: load_f32(&BLOOM_STRENGTH),
        bloom_threshold: load_f32(&BLOOM_THRESHOLD),
    }
}

pub fn fx_apply(p: &FxParams) {
    let p = p.clamped();
    GRADE_ON.store(p.grade, Ordering::Relaxed);
    store_f32(&SAT, p.sat);
    store_f32(&CON, p.con);
    store_f32(&BRI, p.bri);
    SHARPEN_ON.store(p.sharpen, Ordering::Relaxed);
    store_f32(&SHARP, p.sharp);
    FXAA_ON.store(p.fxaa, Ordering::Relaxed);
    VIGNETTE_ON.store(p.vignette, Ordering::Relaxed);
    store_f32(&VIG, p.vig);
    BLOOM_ON.store(p.bloom, Ordering::Relaxed);
    store_f32(&BLOOM_STRENGTH, p.bloom_strength);
    store_f32(&BLOOM_THRESHOLD, p.bloom_threshold);
    FX_DIRTY.store(true, Ordering::Relaxed);
}

pub fn fx_any_on() -> bool {
    fx_snapshot().any_on()
}

pub fn fx_take_dirty() -> bool {
    FX_DIRTY.swap(false, Ordering::Relaxed)
}

pub fn fx_reset() {
    fx_apply(&FxParams::default());
    fx_save_state();
}

// Uniform flag bits, matching the WGSL FxParams struct in gpu.rs.
const FLAG_GRADE: u32 = 1;
const FLAG_SHARPEN: u32 = 2;
const FLAG_FXAA: u32 = 4;
const FLAG_VIGNETTE: u32 = 8;
const FLAG_BLOOM: u32 = 16;

pub fn fx_flags(p: &FxParams) -> u32 {
    let mut f = 0;
    if p.grade {
        f |= FLAG_GRADE;
    }
    if p.sharpen {
        f |= FLAG_SHARPEN;
    }
    if p.fxaa {
        f |= FLAG_FXAA;
    }
    if p.vignette {
        f |= FLAG_VIGNETTE;
    }
    if p.bloom {
        f |= FLAG_BLOOM;
    }
    f
}

// The 64-byte uniform the WGSL shaders read. Layout, in order:
// resolution (vec2f), bloom_size (vec2f), saturation, contrast,
// brightness, sharpen, fxaa_span, vignette, bloom_strength,
// bloom_threshold (8x f32), flags (u32), 3x pad (u32). Built by
// explicit offsets, never by casting a struct, so a Rust layout
// change cannot silently desync the shader.
pub fn fx_uniform_bytes(p: &FxParams, w: u32, h: u32) -> [u8; 64] {
    let mut b = [0u8; 64];
    let put_f = |b: &mut [u8; 64], off: usize, v: f32| b[off..off + 4].copy_from_slice(&v.to_le_bytes());
    let put_u = |b: &mut [u8; 64], off: usize, v: u32| b[off..off + 4].copy_from_slice(&v.to_le_bytes());
    put_f(&mut b, 0, w as f32);
    put_f(&mut b, 4, h as f32);
    put_f(&mut b, 8, (w / 4).max(1) as f32);
    put_f(&mut b, 12, (h / 4).max(1) as f32);
    put_f(&mut b, 16, p.sat);
    put_f(&mut b, 20, p.con);
    put_f(&mut b, 24, p.bri);
    put_f(&mut b, 28, p.sharp);
    put_f(&mut b, 32, if p.fxaa { 2.0 } else { 0.0 });
    put_f(&mut b, 36, p.vig);
    put_f(&mut b, 40, p.bloom_strength);
    put_f(&mut b, 44, p.bloom_threshold);
    put_u(&mut b, 48, fx_flags(p));
    b
}

// One console argument, resolved without touching live state, so
// the harness can check the routing. Toggle names take on/off,
// value names take a number; bloom/sharpen/vignette take both
// (on/off flips the effect, a number sets its strength).
pub enum FxChange {
    Toggle(&'static str, bool),
    Value(&'static str, f32),
    Query(&'static str),
}

fn canonical_name(name: &str) -> Option<&'static str> {
    match name {
        "grade" => Some("grade"),
        "sat" | "saturation" => Some("sat"),
        "con" | "contrast" => Some("con"),
        "bri" | "brightness" => Some("bri"),
        "sharpen" => Some("sharpen"),
        "sharp" | "sharpness" => Some("sharp"),
        "fxaa" => Some("fxaa"),
        "vignette" => Some("vignette"),
        "vig" => Some("vig"),
        "bloom" => Some("bloom"),
        "thr" | "threshold" => Some("thr"),
        _ => None,
    }
}

fn is_toggle(name: &str) -> bool {
    matches!(name, "grade" | "sharpen" | "fxaa" | "vignette" | "bloom")
}

fn is_value(name: &str) -> bool {
    matches!(name, "sat" | "con" | "bri" | "sharp" | "vig" | "bloom" | "thr")
}

pub fn resolve_fx_arg(name: &str, arg: Option<&str>) -> Result<FxChange, String> {
    let Some(name) = canonical_name(&name.to_lowercase()) else {
        return Err(format!("unknown effect: {name} (try: fx help)"));
    };
    let Some(arg) = arg else {
        return Ok(FxChange::Query(name));
    };
    let low = arg.to_lowercase();
    if low == "on" || low == "off" {
        if !is_toggle(name) {
            return Err(format!("{name} is a value, not a toggle (try: fx {name} <number> { })", value_range(name)));
        }
        return Ok(FxChange::Toggle(name, low == "on"));
    }
    let Ok(v) = arg.parse::<f32>() else {
        return Err(format!("bad value: {arg} (try: fx {name} on|off, or fx {name} <number>)"));
    };
    if !is_value(name) {
        return Err(format!("{name} is a toggle, not a value (try: fx {name} on|off)"));
    };
    let Some(v) = clamp_value(name, v) else {
        return Err(format!("bad value: {arg} (not a finite number)"));
    };
    Ok(FxChange::Value(name, v))
}

// Apply a resolved change to the live state, persist it, and return
// the console line. A value set while its effect is off is stored
// but invisible — the line says so, so the player is not left
// wondering why nothing changed.
pub fn fx_apply_change(change: FxChange) -> String {
    match change {
        FxChange::Toggle(name, on) => {
            match name {
                "grade" => GRADE_ON.store(on, Ordering::Relaxed),
                "sharpen" => SHARPEN_ON.store(on, Ordering::Relaxed),
                "fxaa" => FXAA_ON.store(on, Ordering::Relaxed),
                "vignette" => VIGNETTE_ON.store(on, Ordering::Relaxed),
                "bloom" => BLOOM_ON.store(on, Ordering::Relaxed),
                _ => {}
            }
            FX_DIRTY.store(true, Ordering::Relaxed);
            fx_save_state();
            format!("[fx] {name} {}", if on { "ON" } else { "OFF" })
        }
        FxChange::Value(name, v) => {
            match name {
                "sat" => store_f32(&SAT, v),
                "con" => store_f32(&CON, v),
                "bri" => store_f32(&BRI, v),
                "sharp" => store_f32(&SHARP, v),
                "vig" => store_f32(&VIG, v),
                "bloom" => store_f32(&BLOOM_STRENGTH, v),
                "thr" => store_f32(&BLOOM_THRESHOLD, v),
                _ => {}
            }
            FX_DIRTY.store(true, Ordering::Relaxed);
            fx_save_state();
            let on = match name {
                "sat" | "con" | "bri" => GRADE_ON.load(Ordering::Relaxed),
                "sharp" => SHARPEN_ON.load(Ordering::Relaxed),
                "vig" => VIGNETTE_ON.load(Ordering::Relaxed),
                "bloom" | "thr" => BLOOM_ON.load(Ordering::Relaxed),
                _ => true,
            };
            let off_note = if on {
                String::new()
            } else {
                let toggle = match name {
                    "sat" | "con" | "bri" => "grade",
                    "sharp" => "sharpen",
                    "vig" => "vignette",
                    "bloom" | "thr" => "bloom",
                    _ => "",
                };
                format!(" ({} is off — turn it on with: fx {toggle} on)", toggle)
            };
            format!("[fx] {name} {v:.2}{off_note}")
        }
        FxChange::Query(name) => fx_effect_line(name),
    }
}

fn fx_effect_line(name: &str) -> String {
    let p = fx_snapshot();
    match name {
        "grade" => format!("[fx] grade {} (sat {:.2} con {:.2} bri {:.2})", on_off(p.grade), p.sat, p.con, p.bri),
        "sat" => format!("[fx] sat {:.2} (grade {})", p.sat, on_off(p.grade)),
        "con" => format!("[fx] con {:.2} (grade {})", p.con, on_off(p.grade)),
        "bri" => format!("[fx] bri {:.2} (grade {})", p.bri, on_off(p.grade)),
        "sharpen" => format!("[fx] sharpen {} (amount {:.2})", on_off(p.sharpen), p.sharp),
        "sharp" => format!("[fx] sharp {:.2} (sharpen {})", p.sharp, on_off(p.sharpen)),
        "fxaa" => format!("[fx] fxaa {}", on_off(p.fxaa)),
        "vignette" => format!("[fx] vignette {} (amount {:.2})", on_off(p.vignette), p.vig),
        "vig" => format!("[fx] vig {:.2} (vignette {})", p.vig, on_off(p.vignette)),
        "bloom" => format!("[fx] bloom {} (strength {:.2} threshold {:.2})", on_off(p.bloom), p.bloom_strength, p.bloom_threshold),
        "thr" => format!("[fx] thr {:.2} (bloom {})", p.bloom_threshold, on_off(p.bloom)),
        _ => "[fx] ?".to_string(),
    }
}

fn on_off(b: bool) -> &'static str {
    if b {
        "ON"
    } else {
        "OFF"
    }
}

pub fn fx_status_line() -> String {
    let p = fx_snapshot();
    if !p.any_on() {
        return "[fx] all off — fx help lists the effects".to_string();
    }
    let mut parts: Vec<String> = Vec::new();
    if p.grade {
        parts.push(format!("grade sat {:.2} con {:.2} bri {:.2}", p.sat, p.con, p.bri));
    }
    if p.sharpen {
        parts.push(format!("sharpen {:.2}", p.sharp));
    }
    if p.fxaa {
        parts.push("fxaa".to_string());
    }
    if p.vignette {
        parts.push(format!("vignette {:.2}", p.vig));
    }
    if p.bloom {
        parts.push(format!("bloom {:.2}/{:.2}", p.bloom_strength, p.bloom_threshold));
    }
    format!("[fx] {}", parts.join(" · "))
}

// Env sync (MUGUET_FX, set by config.rs from the "fx" JSON flag):
// a compact "grade=1,sat=1.1,con=1.05,bri=0,sharp=0.5,fxaa=1,
// vig=0.4,bloom=1,bloom_str=0.6,bloom_thr=0.8" list. Unknown keys
// and bad values are ignored, never fatal. Precedence: the state
// file (the player's last live change) wins over env; env only
// applies when there is no state file yet.
pub fn parse_fx_env(s: &str) -> FxParams {
    let mut p = FxParams::default();
    for pair in s.split(',') {
        let Some((k, v)) = pair.split_once('=') else {
            continue;
        };
        let (k, v) = (k.trim().to_lowercase(), v.trim());
        match k.as_str() {
            "grade" | "sharpen" | "fxaa" | "vignette" | "bloom" => {
                let on = v == "1" || v.eq_ignore_ascii_case("on") || v.eq_ignore_ascii_case("true");
                match k.as_str() {
                    "grade" => p.grade = on,
                    "sharpen" => p.sharpen = on,
                    "fxaa" => p.fxaa = on,
                    "vignette" => p.vignette = on,
                    "bloom" => p.bloom = on,
                    _ => {}
                }
            }
            "sat" | "con" | "bri" | "sharp" | "vig" | "bloom_str" | "bloom_thr" => {
                let Ok(v) = v.parse::<f32>() else {
                    continue;
                };
                let key = if k == "bloom_str" {
                    "bloom"
                } else if k == "bloom_thr" {
                    "thr"
                } else {
                    k.as_str()
                };
                if let Some(v) = clamp_value(key, v) {
                    match key {
                        "sat" => p.sat = v,
                        "con" => p.con = v,
                        "bri" => p.bri = v,
                        "sharp" => p.sharp = v,
                        "vig" => p.vig = v,
                        "bloom" => p.bloom_strength = v,
                        "thr" => p.bloom_threshold = v,
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    p.clamped()
}

// Session start: restore the last live state (state file first,
// MUGUET_FX env second, all-off default otherwise), then save it
// back so the file exists for the in-game menu to read. Returns the
// console line for the session-start log.
pub fn fx_sync_from_env() -> String {
    if fx_load_state() {
        return format!("{} (restored)", fx_status_line());
    }
    if let Ok(env) = std::env::var("MUGUET_FX") {
        if !env.trim().is_empty() {
            let p = parse_fx_env(&env);
            fx_apply(&p);
            fx_save_state();
            return format!("{} (from launcher setting)", fx_status_line());
        }
    }
    fx_save_state();
    fx_status_line()
}

// Presets + state files. Same Documents location as
// muguet-low-memory-hint.json. Both files are versioned
// ({"version": 1, ...}) and parsed tolerantly: missing fields fall
// back to defaults, unknown fields are ignored, a preset whose
// values fail to parse is skipped with a console line instead of
// dropping the whole file.
pub const FX_PRESETS_VERSION: u32 = 1;
pub const FX_MAX_PRESETS: usize = 32;
pub const FX_PRESETS_FILE: &str = "muguet-fx-presets.json";
pub const FX_STATE_FILE: &str = "muguet-fx-state.json";

fn documents_dir() -> Option<std::path::PathBuf> {
    let home = std::env::var_os("HOME")?;
    let base = std::path::PathBuf::from(home);
    if cfg!(target_os = "ios") {
        Some(base.join("Documents"))
    } else {
        Some(base.join("Library/Application Support/Muguet"))
    }
}

// One lock for all preset/state file read-modify-write cycles: the
// console handler (main thread) and the session-start sync (script
// thread) can both touch these files, and a torn read-modify-write
// would silently drop a preset.
static FX_FILE_LOCK: Mutex<()> = Mutex::new(());

fn lock_files() -> MutexGuard<'static, ()> {
    FX_FILE_LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

// Preset names are file-safe by construction: no separators, no
// dots (so ".." is impossible), no control characters, 1-48 chars
// after trimming. They are JSON keys, never path segments, but the
// rule also stops a name from ever becoming a path elsewhere.
pub fn valid_preset_name(name: &str) -> bool {
    let name = name.trim();
    if name.is_empty() || name.len() > 48 {
        return false;
    }
    name.chars().all(|c| c.is_ascii_alphanumeric() || c == ' ' || c == '-' || c == '_')
}

#[derive(Serialize, Deserialize, Default)]
struct PresetFile {
    #[serde(default)]
    version: u32,
    #[serde(default)]
    presets: BTreeMap<String, FxParams>,
}

#[derive(Serialize, Deserialize)]
struct StateFile {
    #[serde(default)]
    version: u32,
    #[serde(default)]
    state: FxParams,
}

fn read_preset_file() -> PresetFile {
    let Some(dir) = documents_dir() else {
        return PresetFile::default();
    };
    let path = dir.join(FX_PRESETS_FILE);
    let Ok(text) = std::fs::read_to_string(&path) else {
        return PresetFile::default();
    };
    // Parse as a generic value first, so one bad preset does not
    // drop the rest: each preset is deserialized on its own and a
    // failure skips just that preset, with a console line.
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) else {
        // Corrupt file: quarantine it (one .corrupt copy, not a
        // silent delete) and start empty. The next save rewrites a
        // clean file.
        let _ = std::fs::rename(&path, dir.join(format!("{FX_PRESETS_FILE}.corrupt")));
        crate::debug::console_line("^1[fx] presets file was corrupt — moved to muguet-fx-presets.json.corrupt, starting empty");
        return PresetFile::default();
    };
    let mut out = PresetFile::default();
    out.version = value.get("version").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
    if let Some(map) = value.get("presets").and_then(|v| v.as_object()) {
        for (name, pv) in map {
            if !valid_preset_name(name) {
                continue;
            }
            match serde_json::from_value::<FxParams>(pv.clone()) {
                Ok(p) => {
                    out.presets.insert(name.clone(), p.clamped());
                }
                Err(_) => {
                    crate::debug::console_line(&format!("[fx] preset '{name}' has bad values — skipped"));
                }
            }
        }
    }
    out
}

fn write_preset_file(f: &PresetFile) -> Result<(), String> {
    let Some(dir) = documents_dir() else {
        return Err("no Documents directory".to_string());
    };
    let _ = std::fs::create_dir_all(&dir);
    let text = serde_json::to_string(f).map_err(|e| e.to_string())?;
    // Write-temp-then-rename, so a crash mid-write never leaves a
    // half-written presets file behind.
    let tmp = dir.join(format!("{FX_PRESETS_FILE}.tmp"));
    std::fs::write(&tmp, text).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, dir.join(FX_PRESETS_FILE)).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn fx_preset_names() -> Vec<String> {
    let _g = lock_files();
    read_preset_file().presets.keys().cloned().collect()
}

pub fn fx_save_preset(name: &str) -> Result<String, String> {
    let name = name.trim();
    if !valid_preset_name(name) {
        return Err("bad preset name (letters, numbers, spaces, - and _ only, 1-48 chars)".to_string());
    }
    let _g = lock_files();
    let mut f = read_preset_file();
    if !f.presets.contains_key(name) && f.presets.len() >= FX_MAX_PRESETS {
        return Err(format!("preset limit reached ({FX_MAX_PRESETS}) — delete one first (fx delete <name>)"));
    }
    f.presets.insert(name.to_string(), fx_snapshot());
    f.version = FX_PRESETS_VERSION;
    write_preset_file(&f)?;
    Ok(format!("[fx] preset '{name}' saved ({} stored)", f.presets.len()))
}

pub fn fx_load_preset(name: &str) -> Result<String, String> {
    let name = name.trim();
    if !valid_preset_name(name) {
        return Err("bad preset name (letters, numbers, spaces, - and _ only, 1-48 chars)".to_string());
    }
    let _g = lock_files();
    let mut f = read_preset_file();
    let Some(p) = f.presets.get(name).copied() else {
        return Err(format!("no preset '{name}' (fx presets lists them)"));
    };
    f.version = FX_PRESETS_VERSION;
    write_preset_file(&f)?;
    drop(_g);
    // Apply after the file lock is released: fx_apply only touches
    // atomics, but fx_save_state re-locks the file mutex, and a
    // nested lock here would deadlock on the non-reentrant Mutex.
    fx_apply(&p);
    fx_save_state();
    Ok(format!("{} (preset '{name}')", fx_status_line()))
}

pub fn fx_delete_preset(name: &str) -> Result<String, String> {
    let name = name.trim();
    if !valid_preset_name(name) {
        return Err("bad preset name (letters, numbers, spaces, - and _ only, 1-48 chars)".to_string());
    }
    let _g = lock_files();
    let mut f = read_preset_file();
    if f.presets.remove(name).is_none() {
        return Err(format!("no preset '{name}' (fx presets lists them)"));
    }
    write_preset_file(&f)?;
    Ok(format!("[fx] preset '{name}' deleted ({} left)", f.presets.len()))
}

// Current live state, persisted on every change so a force-quit
// cannot lose it (there is no reliable session-end hook). The
// in-game menu reads this file to show the current values.
pub fn fx_save_state() {
    let _g = lock_files();
    let Some(dir) = documents_dir() else {
        return;
    };
    let _ = std::fs::create_dir_all(&dir);
    let f = StateFile { version: FX_PRESETS_VERSION, state: fx_snapshot() };
    let Ok(text) = serde_json::to_string(&f) else {
        return;
    };
    let tmp = dir.join(format!("{FX_STATE_FILE}.tmp"));
    if std::fs::write(&tmp, text).is_ok() {
        let _ = std::fs::rename(&tmp, dir.join(FX_STATE_FILE));
    }
}

fn fx_load_state() -> bool {
    let _g = lock_files();
    let Some(dir) = documents_dir() else {
        return false;
    };
    let Ok(text) = std::fs::read_to_string(dir.join(FX_STATE_FILE)) else {
        return false;
    };
    let Ok(f) = serde_json::from_str::<StateFile>(&text) else {
        return false;
    };
    let p = f.state.clamped();
    drop(_g);
    // Same lock order as fx_load_preset: apply (which saves state)
    // only after the file lock is released.
    fx_apply(&p);
    true
}

// Console entry point: the rest of the line after "fx", split on
// whitespace by the caller. Returns the lines to print.
pub fn fx_console(rest: &[&str]) -> Vec<String> {
    match rest.first().copied() {
        None => vec![fx_status_line()],
        Some("help") => vec![
            "[fx] post FX (live — applies next frame, no restart):".to_string(),
            "  fx — show current state".to_string(),
            "  fx <effect> on|off — grade, sharpen, fxaa, vignette, bloom".to_string(),
            "  fx <value> <number> — sat 0-2, con 0-2, bri -0.5-0.5, sharp 0-1, vig 0-1, bloom 0-2, thr 0-1".to_string(),
            "  fx <name> — show one effect (e.g. fx bloom)".to_string(),
            "  fx save <name> — save the current set as a preset".to_string(),
            "  fx load <name> — load a preset (applies live)".to_string(),
            "  fx delete <name> — delete a preset".to_string(),
            "  fx presets — list saved presets".to_string(),
            "  fx reset — everything off, values back to default".to_string(),
            "  fx off — all effects off (keeps the values)".to_string(),
            "  presets live in Documents/muguet-fx-presets.json".to_string(),
        ],
        // Preset names may contain spaces, so save/load/delete take
        // every remaining word, not just the next one.
        Some("save") => {
            let name = rest[1..].join(" ");
            if name.trim().is_empty() {
                vec!["usage: fx save <name>  (letters, numbers, spaces, - and _ only)".to_string()]
            } else {
                vec![fx_save_preset(&name).unwrap_or_else(|e| format!("[fx] save failed: {e}"))]
            }
        }
        Some("load") => {
            let name = rest[1..].join(" ");
            if name.trim().is_empty() {
                vec!["usage: fx load <name>".to_string()]
            } else {
                vec![fx_load_preset(&name).unwrap_or_else(|e| format!("[fx] load failed: {e}"))]
            }
        }
        Some("delete") => {
            let name = rest[1..].join(" ");
            if name.trim().is_empty() {
                vec!["usage: fx delete <name>".to_string()]
            } else {
                vec![fx_delete_preset(&name).unwrap_or_else(|e| format!("[fx] delete failed: {e}"))]
            }
        }
        Some("presets") => {
            let names = fx_preset_names();
            if names.is_empty() {
                vec!["[fx] no presets saved yet (fx save <name>)".to_string()]
            } else {
                vec![format!("[fx] presets: {}", names.join(", "))]
            }
        }
        Some("reset") => {
            fx_reset();
            vec![fx_status_line()]
        }
        Some("off") => {
            let mut p = fx_snapshot();
            p.grade = false;
            p.sharpen = false;
            p.fxaa = false;
            p.vignette = false;
            p.bloom = false;
            fx_apply(&p);
            fx_save_state();
            vec![fx_status_line()]
        }
        Some(name) => {
            let arg = rest.get(1).copied();
            match resolve_fx_arg(name, arg) {
                Ok(change) => vec![fx_apply_change(change)],
                Err(e) => vec![format!("[fx] {e}")],
            }
        }
    }
}
