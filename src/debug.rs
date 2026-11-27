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

pub fn ram_tracker() -> (String, u8) {
    RAM_TRACKER.lock().map(|slot| slot.clone()).unwrap_or_else(|e| e.into_inner().clone())
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

pub fn run_number() -> u64 {
    lock_state().run
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
    if !enabled() {
        return;
    }
    eprintln!("[debug] {msg}");
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
    eprintln!("[debug] {s}");
    write_debug_log(&s);
}

fn sample_inner(footprint_mb: u64, available_mb: u64, heap_mb: u64, gpu: Option<GpuSample>, forced: bool) {
    let mut warn: Option<String> = None;
    let mut line: Option<String> = None;
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
            Some((t0, fp0)) if elapsed - t0 >= 30.0 => {
                format!("{:.0} MB/min", (footprint_mb as f64 - fp0 as f64) / (elapsed - t0) * 60.0)
            }
            Some(_) => "n/a (<30s)".to_string(),
            None => {
                st.first_sample = Some((elapsed, footprint_mb));
                "n/a (first)".to_string()
            }
        };
        let gpu_text = match st.last_gpu {
            Some(g) => format!(
                "tex live {} (created {} destroyed {}) | buf live {} (created {} destroyed {}) | shaders {} pipes {} bg {} draws {} presents {}",
                g.textures, g.tex_created, g.tex_destroyed, g.buffers, g.buf_created, g.buf_destroyed,
                g.shaders, g.pipelines, g.bind_groups, g.draws, g.presents
            ),
            None => "gpu n/a".to_string(),
        };
        line = Some(format!("sample run {} t {elapsed:.0}s footprint {footprint_mb} MB avail {available_mb} MB heap {heap_mb} MB slope {slope} | {gpu_text}", st.run));
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
