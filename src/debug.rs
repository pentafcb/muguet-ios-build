// muguet - debug.rs
// Developer debug tools for the crash-2-3-minutes-into-a-single-session
// investigation. Corrected 2026-11-26: the crash is NOT after 2-3 runs.
// It is every session, 2-3 minutes into one play session, never past 5
// minutes. So the log is built to show within-session growth rate
// (footprint slope in MB/min), not cross-run accumulation.
// All log output is gated behind MUGUET_DEBUG=1 and is off by default in
// release builds. The only file written without the flag is the tiny run
// counter (muguet-debug.json), so heap-refusal lines and panic dumps can
// always name the run number. In-memory counters are always tracked so a
// memory warning or panic can still report live GPU counts.

use std::collections::VecDeque;
use std::sync::{LazyLock, Mutex, MutexGuard};
use std::time::{Duration, Instant};

pub static ENABLED: LazyLock<bool> = LazyLock::new(|| {
    std::env::var("MUGUET_DEBUG").map(|v| v == "1" || v.eq_ignore_ascii_case("true")).unwrap_or(false)
});

pub fn enabled() -> bool {
    *ENABLED
}

#[derive(Clone, Copy, Default)]
pub struct GpuSample {
    pub textures: u64,
    pub buffers: u64,
    pub shaders: u64,
    pub pipelines: u64,
    pub bind_groups: u64,
    pub draws: u64,
    pub presents: u64,
    pub tex_created: u64,
    pub tex_destroyed: u64,
    pub buf_created: u64,
    pub buf_destroyed: u64,
}

struct State {
    run: u64,
    started: Instant,
    last_sample: Option<Instant>,
    last_gpu: Option<GpuSample>,
    peak_tex: u64,
    peak_buf: u64,
    prev_peak_tex: u64,
    prev_peak_buf: u64,
    leak_warned: bool,
    last_persist: Option<Instant>,
    // First sample of this session: (elapsed seconds, footprint MB).
    // The slope is measured from here, so it shows within-session growth
    // rate instead of the level alone.
    first_sample: Option<(f64, u64)>,
    // First available-memory sample of this session: (elapsed seconds,
    // available MB). The available-memory slope (negative = falling)
    // drives the slope-based inflow cut; same 30 s warm-up as the
    // footprint slope.
    first_avail_sample: Option<(f64, u64)>,
    // Latest available-memory slope in MB/min, when at least 30 s of
    // data exists. Read by the GPU thread's memory tick.
    last_avail_slope: Option<f64>,
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(|| {
    Mutex::new(State {
        run: 0,
        started: Instant::now(),
        last_sample: None,
        last_gpu: None,
        peak_tex: 0,
        peak_buf: 0,
        prev_peak_tex: 0,
        prev_peak_buf: 0,
        leak_warned: false,
        last_persist: None,
        first_sample: None,
        first_avail_sample: None,
        last_avail_slope: None,
    })
});

fn lock_state() -> MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(|e| e.into_inner())
}

// RAM tracker: the latest tracker line, written by the GPU thread's
// check_memory and read by the touch overlay on the event-loop thread
// (UIKit must only be touched from the main thread, so the label itself
// is updated in touch::refresh, never from here). The u8 is the memory
// tier: 0 ok, 1 watch, 2 pressure, 3 critical. Empty text means the
// game has not started yet.
static RAM_TRACKER: LazyLock<Mutex<(String, u8)>> = LazyLock::new(|| Mutex::new((String::new(), 0)));

pub fn set_ram_tracker(text: String, tier: u8) {
    if let Ok(mut slot) = RAM_TRACKER.lock() {
        *slot = (text, tier);
    }
}

// Read only from touch.rs, which is iOS-only, so the host build
// sees this as dead code.
#[allow(dead_code)]
pub fn ram_tracker() -> (String, u8) {
    RAM_TRACKER.lock().map(|slot| slot.clone()).unwrap_or_else(|e| e.into_inner().clone())
}

// In-game console ring buffer: always on, never gated by
// MUGUET_DEBUG. The user needs to see why a spawn failed or why the
// game black-screened without a debug flag or a log export. Cap 300
// lines; Swift polls the last 200 through muguet_console_tail.
static CONSOLE_LINES: LazyLock<Mutex<VecDeque<String>>> = LazyLock::new(|| Mutex::new(VecDeque::new()));
const CONSOLE_CAP: usize = 300;

pub fn console_line(msg: &str) {
    if let Ok(mut buf) = CONSOLE_LINES.lock() {
        for line in msg.split('\n') {
            if buf.len() >= CONSOLE_CAP { buf.pop_front(); }
            buf.push_back(line.to_string());
        }
    }
    eprintln!("{msg}");
}

pub fn clear_console() {
    if let Ok(mut buf) = CONSOLE_LINES.lock() { buf.clear(); }
}

pub fn console_tail() -> String {
    let buf = CONSOLE_LINES.lock().unwrap_or_else(|e| e.into_inner());
    let skip = buf.len().saturating_sub(200);
    buf.iter().skip(skip).cloned().collect::<Vec<_>>().join("\n")
}

// The latest tail as a C string for Swift. The pointer stays valid
// until the next call replaces the stored string; Swift copies it
// immediately.
static CONSOLE_TAIL_C: LazyLock<Mutex<std::ffi::CString>> = LazyLock::new(|| Mutex::new(std::ffi::CString::new("").unwrap()));
#[no_mangle]
pub extern "C" fn muguet_console_tail() -> *const std::ffi::c_char {
    let tail = console_tail();
    if let Ok(mut slot) = CONSOLE_TAIL_C.lock() {
        if let Ok(c) = std::ffi::CString::new(tail) { *slot = c; }
        slot.as_ptr()
    } else {
        std::ptr::null()
    }
}

// The live RAM tracker line as a C string for Swift, same
// static-slot pattern. The tracker never logs to the console, so
// Swift cannot grep the tail for it — the home RAM card did exactly
// that and always showed "—". Empty when the game has not started
// yet; Swift shows "—" for that.
static RAM_TRACKER_C: LazyLock<Mutex<std::ffi::CString>> = LazyLock::new(|| Mutex::new(std::ffi::CString::new("").unwrap()));
#[no_mangle]
pub extern "C" fn muguet_ram_tracker_text() -> *const std::ffi::c_char {
    let (text, _) = ram_tracker();
    if let Ok(mut slot) = RAM_TRACKER_C.lock() {
        if let Ok(c) = std::ffi::CString::new(text) { *slot = c; }
        slot.as_ptr()
    } else {
        std::ptr::null()
    }
}

// Slope in MB/min between a first sample (elapsed seconds, MB) and
// the current reading. None before 30 s of data — a slope from a few
// seconds is noise, not a trend. Positive = growing, negative =
// falling. Used for the footprint slope and the available-memory
// slope alike.
pub(crate) fn slope_mb_min(first_elapsed: f64, first_value: u64, elapsed: f64, current: u64) -> Option<f64> {
    let dt = elapsed - first_elapsed;
    if dt < 30.0 {
        return None;
    }
    Some((current as f64 - first_value as f64) / dt * 60.0)
}

// Inflow cut: available memory below 3 GB and falling faster than
// ~300 MB/min. The level is deliberately above the tier-1 line
// (2048 MB): a slope trigger only earns its keep if it fires BEFORE
// the level tier does. At the measured touring slope (~1150 MB/min)
// a 3 GB trigger buys ~50 s of lead; at the 300 MB/min threshold
// slope it buys ~3 min.
pub(crate) fn inflow_cut_needed(avail_mb: u64, slope_mb_min: f64) -> bool {
    avail_mb < 3072 && slope_mb_min < -300.0
}

// Latest available-memory slope in MB/min, if at least 30 s of
// samples exist. Read by the GPU thread's memory tick.
pub fn avail_slope_mb_min() -> Option<f64> {
    lock_state().last_avail_slope
}

// Marker the launcher reads on next launch: the last session ran
// low on memory, so the next launch starts on Ultra Low. Written
// the moment the session is classified low-memory, not at session
// end — jetsam and quit have no reliable session-end hook on this
// side, so waiting for one would lose the signal exactly when it
// matters. Same Documents location as muguet-debug.json; the
// launcher deletes the file after applying it.
pub(crate) fn write_low_memory_hint(reason: &str) {
    let Some(dir) = documents_dir() else {
        return;
    };
    let _ = std::fs::create_dir_all(&dir);
    let text = serde_json::json!({"preset": "ultra_low", "reason": reason}).to_string();
    let _ = std::fs::write(dir.join("muguet-low-memory-hint.json"), text);
}

fn documents_dir() -> Option<std::path::PathBuf> {
    let home = std::env::var_os("HOME")?;
    let base = std::path::PathBuf::from(home);
    if cfg!(target_os = "ios") {
        Some(base.join("Documents"))
    } else {
        Some(base.join("Library/Application Support/Muguet"))
    }
}

fn persist_json(run: u64, peak_tex: u64, peak_buf: u64) {
    let Some(dir) = documents_dir() else { return };
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("muguet-debug.json");
    let text = serde_json::json!({"runs": run, "prev_peak_tex": peak_tex, "prev_peak_buf": peak_buf}).to_string();
    let _ = std::fs::write(path, text);
}

pub fn init() {
    let mut runs = 0u64;
    let mut prev_tex = 0u64;
    let mut prev_buf = 0u64;
    if let Some(dir) = documents_dir() {
        let path = dir.join("muguet-debug.json");
        if let Ok(text) = std::fs::read_to_string(&path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                runs = v.get("runs").and_then(|v| v.as_u64()).unwrap_or(0);
                prev_tex = v.get("prev_peak_tex").and_then(|v| v.as_u64()).unwrap_or(0);
                prev_buf = v.get("prev_peak_buf").and_then(|v| v.as_u64()).unwrap_or(0);
            }
        }
    }
    {
        let mut st = lock_state();
        // A corrupt muguet-debug.json with runs near u64::MAX used to
        // wrap the counter back to 0 on the next launch.
        st.run = runs.saturating_add(1);
        st.prev_peak_tex = prev_tex;
        st.prev_peak_buf = prev_buf;
        st.peak_tex = prev_tex;
        st.peak_buf = prev_buf;
    }
    persist_json(runs.saturating_add(1), prev_tex, prev_buf);
    if enabled() {
        log_line(&format!("debug run {} started (previous runs: {runs}, previous peak tex {prev_tex} buf {prev_buf})", runs + 1));
    }
}

fn write_debug_log(msg: &str) {
    if !enabled() {
        return;
    }
    let Some(dir) = documents_dir() else { return };
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("muguet-debug.log");
    // Rotate at 1 MiB: with 2 s samples + 1 s pad logs the debug log
    // used to grow without bound on a nearly-full device.
    if std::fs::metadata(&path).map(|m| m.len() > 1 << 20).unwrap_or(false) {
        let _ = std::fs::rename(&path, dir.join("muguet-debug-prev.log"));
    }
    let elapsed = lock_state().started.elapsed().as_secs_f64();
    let line = format!("[{elapsed:.1}s] {msg}\n");
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        use std::io::Write;
        let _ = f.write_all(line.as_bytes());
    }
}

pub fn log_line(msg: &str) {
    // The in-game console shows debug lines too, even when
    // MUGUET_DEBUG is unset (the file log stays gated). console_line
    // already echoes to stderr, so there is no second eprintln here.
    console_line(&format!("[debug] {msg}"));
    if !enabled() {
        return;
    }
    write_debug_log(msg);
}

// Called from Swift (Launcher.swift) for picker cancel / error reporting.
// Always echoes to stderr (muguet-runtime.log); the debug file stays gated.
#[no_mangle]
pub extern "C" fn muguet_debug_log(msg: *const std::ffi::c_char) {
    if msg.is_null() {
        return;
    }
    let s = unsafe { std::ffi::CStr::from_ptr(msg) }.to_string_lossy();
    // Same as log_line: the console shows it, the file stays gated.
    console_line(&format!("[debug] {s}"));
    write_debug_log(&s);
}

fn sample_inner(footprint_mb: u64, available_mb: u64, heap_mb: u64, gpu: Option<GpuSample>, forced: bool) {
    let mut warn: Option<String> = None;
    // No initializer: the value is assigned on every path that reaches
    // the log below (the only other path returns early), so an initial
    // None would be overwritten before ever being read.
    let line: Option<String>;
    // persist_json does file I/O (write + create_dir_all) and used to
    // run while holding STATE, stalling snapshot_text() (panic hook,
    // memory warning) on every new texture peak while streaming.
    // Record the need here and flush after the lock is dropped.
    let mut persist = false;
    {
        let mut st = lock_state();
        if let Some(g) = gpu {
            if g.textures > st.peak_tex {
                st.peak_tex = g.textures;
                persist = true;
            }
            if g.buffers > st.peak_buf {
                st.peak_buf = g.buffers;
                persist = true;
            }
            if !st.leak_warned {
                if st.prev_peak_tex > 0 && g.textures > st.prev_peak_tex {
                    warn = Some(format!("LEAK WATCH: textures live {} exceed previous run peak {}", g.textures, st.prev_peak_tex));
                    st.leak_warned = true;
                } else if st.prev_peak_buf > 0 && g.buffers > st.prev_peak_buf {
                    warn = Some(format!("LEAK WATCH: buffers live {} exceed previous run peak {}", g.buffers, st.prev_peak_buf));
                    st.leak_warned = true;
                }
            }
            st.last_gpu = Some(g);
        }
        let now = Instant::now();
        // 2 s cadence, not 5 s: the session dies at ~150 s, so 5 s samples
        // would give only ~30 points and could miss the final climb.
        let due = forced || st.last_sample.map(|t| now.duration_since(t) >= Duration::from_secs(2)).unwrap_or(true);
        if !due {
            return;
        }
        st.last_sample = Some(now);
        let elapsed = st.started.elapsed().as_secs_f64();
        // Footprint slope in MB/min, measured from the first sample of
        // this session. Meaningless before 30 s of data, so it reads n/a
        // until then. A steady ~900 MB/min slope is what a 150 s jetsam
        // kill looks like; a flat slope with a sudden jump points at a
        // single burst (streaming / shader compile) instead. A negative
        // slope after a purge means the purge actually freed memory.
        let slope = match st.first_sample {
            Some((t0, fp0)) => match slope_mb_min(t0, fp0, elapsed, footprint_mb) {
                Some(s) => format!("{s:.0} MB/min"),
                None => "n/a (<30s)".to_string(),
            },
            None => {
                st.first_sample = Some((elapsed, footprint_mb));
                "n/a (first)".to_string()
            }
        };
        // Available-memory slope, same measurement. Negative = falling
        // toward the 1250 MB heap growth floor; the GPU thread reads
        // the numeric value through avail_slope_mb_min() for the
        // slope-based inflow cut.
        let avail_slope = match st.first_avail_sample {
            Some((t0, av0)) => slope_mb_min(t0, av0, elapsed, available_mb),
            None => {
                st.first_avail_sample = Some((elapsed, available_mb));
                None
            }
        };
        st.last_avail_slope = avail_slope;
        let avail_slope_text = avail_slope
            .map(|s| format!("{s:.0} MB/min"))
            .unwrap_or_else(|| "n/a".to_string());
        let gpu_text = match st.last_gpu {
            Some(g) => format!(
                "tex live {} (created {} destroyed {}) | buf live {} (created {} destroyed {}) | shaders {} pipes {} bg {} draws {} presents {}",
                g.textures, g.tex_created, g.tex_destroyed, g.buffers, g.buf_created, g.buf_destroyed,
                g.shaders, g.pipelines, g.bind_groups, g.draws, g.presents
            ),
            None => "gpu n/a".to_string(),
        };
        line = Some(format!("sample run {} t {elapsed:.0}s footprint {footprint_mb} MB avail {available_mb} MB heap {heap_mb} MB slope {slope} avail-slope {avail_slope_text} | {gpu_text}", st.run));
    }
    if let Some(w) = warn {
        log_line(&w);
    }
    if let Some(l) = line {
        log_line(&l);
    }
    if persist {
        // Throttled to at most once per 2 s, outside the STATE lock.
        let due = {
            let mut st = lock_state();
            let now = Instant::now();
            let due = st.last_persist.map(|t| now.duration_since(t) >= Duration::from_secs(2)).unwrap_or(true);
            if due { st.last_persist = Some(now); }
            due
        };
        if due {
            let (run, peak_tex, peak_buf) = {
                let st = lock_state();
                (st.run, st.peak_tex, st.peak_buf)
            };
            persist_json(run, peak_tex, peak_buf);
        }
    }
}

pub fn sample(footprint_mb: u64, available_mb: u64, heap_mb: u64, gpu: Option<GpuSample>) {
    sample_inner(footprint_mb, available_mb, heap_mb, gpu, false);
}

pub fn sample_forced(footprint_mb: u64, available_mb: u64, heap_mb: u64, gpu: Option<GpuSample>) {
    sample_inner(footprint_mb, available_mb, heap_mb, gpu, true);
}

pub fn snapshot_text() -> String {
    let fp = crate::footprint_mb();
    let av = crate::performance::available_memory().unwrap_or(0) >> 20;
    let heap = crate::RT.get().map(|r| r.mem.data_size() >> 20).unwrap_or(0);
    let (run, gpu, elapsed) = match STATE.try_lock() {
        Ok(st) => (st.run, st.last_gpu, st.started.elapsed().as_secs_f64()),
        Err(_) => (0, None, 0.0),
    };
    match gpu {
        Some(g) => format!(
            "run {run} t {elapsed:.0}s | footprint {fp} MB | avail {av} MB | heap {heap} MB | tex {} buf {} shaders {} pipes {} bg {} draws {} presents {}",
            g.textures, g.buffers, g.shaders, g.pipelines, g.bind_groups, g.draws, g.presents
        ),
        None => format!("run {run} t {elapsed:.0}s | footprint {fp} MB | avail {av} MB | heap {heap} MB | gpu n/a"),
    }
}

pub fn note_heap_refusal(requested_mb: u64, max_mb: u64, available_mb: u64) {
    log_line(&format!(
        "heap growth refused: requested {requested_mb} MB, maximum {max_mb} MB, available {available_mb} MB | {}",
        snapshot_text()
    ));
}

pub fn note_pad(_raw: (f32, f32), _curved: (f64, f64), _dt: f64, _final_delta: (f64, f64), _rate_px_s: f64, _aimed: bool) {
    // Was a 1/s pad log; it filled half of muguet-debug.log and the
    // gamepad sensitivity question it served is closed (look base 1400
    // px/s, pad sens 2, verified live). The debug log keeps only run
    // samples, warnings and crash info now. Signature kept so callers
    // in pad.rs need no change.
}
