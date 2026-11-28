use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::{Duration, Instant};

pub const MIB: u64 = 1 << 20;
pub const HEAP_CEILING: u64 = 16 << 30;
// 5 GB, not 4: with the increased-memory-limit entitlement the
// phone has the headroom (8 GB physical, ~6 GB available at
// startup), and the 4 GB cap starved the streamer on a full-city
// tour — the heap hit 4,041 MB and the game's own virtual allocator
// failed (Largest Free Block 0, 16 MB available), so the streamer
// got NULL destinations and the game aborted. The safety rails
// still apply below (device_budget 65%, the 1,250 MB stream reserve,
// the avail tiers), so this is a ceiling, not a target.
pub const IOS_HEAP_MAX: u64 = 5120 * MIB;
pub static MEMORY_PRESSURE: AtomicBool = AtomicBool::new(false);
static FRAME_LIMIT: AtomicU32 = AtomicU32::new(60);
static PROMOTION_SYNC: AtomicBool = AtomicBool::new(false);

pub fn set_promotion_sync(enabled: bool) {
    PROMOTION_SYNC.store(enabled, Ordering::Relaxed);
}

// Called only from a cfg(ios) site in gpu.rs, so the host build
// sees this as dead code.
#[allow(dead_code)]
pub fn promotion_sync_enabled() -> bool {
    PROMOTION_SYNC.load(Ordering::Relaxed)
}

pub fn set_frame_limit(fps: f64) {
    let fps = if !fps.is_finite() { 60 } else if fps <= 0.0 { 0 }
        else if fps <= 30.0 { 30 } else if fps <= 60.0 { 60 } else { 120 };
    FRAME_LIMIT.store(fps, Ordering::Relaxed);
}

pub fn frame_limit() -> u32 { FRAME_LIMIT.load(Ordering::Relaxed) }

pub fn engine_frame_limit(_fps: f64) -> u8 {
    // Always 0 (engine limiter off). The host FramePacer already
    // paces presents to the configured FPS, so the engine limiter is
    // redundant — and it wedges the game. With -frameLimit=2 (the 30
    // FPS presets) the engine deadlocked: main 100% "Wait for render
    // [semaphore]" while the render thread waited for the next queued
    // frame, draws/presents frozen, host idle, memory fine. The
    // limiter's own wait is the prime suspect for consuming the
    // render-completion signal the frame-boundary wait needs, leaving
    // both threads waiting on each other. 120 FPS already ran with
    // -frameLimit=0 and never wedged, so every preset uses 0 now and
    // the host does all the pacing.
    0
}

pub fn available_memory() -> Option<u64> {
    #[cfg(target_os = "ios")]
    {
        extern "C" { fn os_proc_available_memory() -> usize; }
        Some(unsafe { os_proc_available_memory() } as u64)
    }
    #[cfg(not(target_os = "ios"))]
    { None }
}

pub fn physical_memory() -> u64 {
    #[cfg(target_os = "ios")]
    {
        extern "C" { fn muguet_physical_memory() -> u64; }
        unsafe { muguet_physical_memory() }
    }
    #[cfg(not(target_os = "ios"))]
    { HEAP_CEILING * 2 }
}

// Leave room for Metal, native code, audio and the operating system. This is
// a limit on the game heap, not a request to allocate this many physical pages.
pub fn heap_budget(physical: u64, available: Option<u64>, current_heap: u64) -> u64 {
    let device_budget = physical.saturating_mul(65) / 100;
    let process_budget = available.map(|a| current_heap.saturating_add(a.saturating_sub(768 * MIB)))
        .unwrap_or(device_budget);
    device_budget.min(process_budget).min(HEAP_CEILING).max(current_heap)
}

pub fn ios_heap_budget(physical: u64, available: Option<u64>, current_heap: u64) -> u64 {
    let budget = heap_budget(physical, available, current_heap).min(IOS_HEAP_MAX);
    // The old make-ios.sh HEAP_GB / MUGUET_IOS_HEAP_GB knob was never
    // read by any code, so "8 GB paid vs 5 GB free" did nothing. This
    // is the knob that actually works: a runtime env override, validated
    // and clamped to 512 MB..5 GB (non-finite/garbage values ignored).
    // On a sideloaded IPA there is no launch env, so the compiled-in
    // IOS_HEAP_MAX above is what the phone uses — and a free build with
    // no increased-memory-limit entitlement jetsams well below it.
    // The 768 MB reserve inside heap_budget is for Metal, audio and the
    // OS — but the game's streamed textures live OUTSIDE the heap and
    // keep growing as the world streams (they were ~320 MB and climbing
    // when a 2,701 MB footprint jetsammed the process). Cap the heap
    // against a bigger reserve so heap + streamed textures stay under
    // the jetsam line: with 3,374 MB available at startup and a 466 MB
    // minimum heap, this caps the heap at 2,590 MB instead of 5,120 MB.
    let stream_cap = available.map(|a| current_heap.saturating_add(a.saturating_sub(1250 * MIB))).unwrap_or(u64::MAX);
    let budget = budget.min(stream_cap);
    match std::env::var("MUGUET_HEAP_GB_MB").ok().and_then(|v| v.parse::<u64>().ok()) {
        Some(mb) if (512..=5120).contains(&mb) => budget.min(mb * MIB).max(current_heap),
        _ => budget,
    }
}

pub fn growth_fits(old: u64, requested: u64, maximum: u64, available: Option<u64>) -> bool {
    if requested <= old { return true; }
    requested <= maximum && available.map(|a| requested - old <= a.saturating_sub(256 * MIB)).unwrap_or(true)
}

#[derive(Default)]
pub struct FramePacer { next: Option<Instant>, fps: u32 }

impl FramePacer {
    pub fn delay(&mut self, now: Instant, fps: u32) -> Duration {
        if fps == 0 { self.next = None; self.fps = 0; return Duration::ZERO; }
        let interval = Duration::from_secs_f64(1.0 / fps as f64);
        let deadline = if self.fps != fps { now } else { self.next.unwrap_or(now).max(now) };
        self.fps = fps;
        self.next = Some(deadline + interval);
        deadline.saturating_duration_since(now)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn low_ram_never_receives_the_sixteen_gib_budget() {
        assert_eq!(heap_budget(4 << 30, Some(2 << 30), 0), 1280 * MIB);
        assert!(heap_budget(8 << 30, Some(6 << 30), 0) < 6 << 30);
        assert_eq!(heap_budget(32 << 30, Some(24 << 30), 0), HEAP_CEILING);
        assert_eq!(heap_budget(4 << 30, Some(128 * MIB), 1 << 30), 1 << 30);
        assert_eq!(ios_heap_budget(8 << 30, Some(6 << 30), 1 << 30), 5 << 30);
        assert!(ios_heap_budget(4 << 30, Some(2 << 30), 0) < 3 << 30);
        // The streamed-texture reserve: 3,374 MB available at startup
        // with a 466 MB minimum heap caps the heap at 2,590 MB, not
        // 3,072 MB, leaving room for textures outside the heap.
        assert_eq!(ios_heap_budget(8 << 30, Some(3374 * MIB), 466 * MIB), 2590 * MIB);
    }
    #[test]
    fn refuses_growth_that_consumes_native_headroom() {
        assert!(!growth_fits(1 << 30, 2 << 30, 4 << 30, Some(1100 * MIB)));
        assert!(growth_fits(1 << 30, 1 << 30, 4 << 30, Some(0)));
        assert!(!growth_fits(1 << 30, 5 << 30, 4 << 30, None));
    }
    #[test]
    fn frame_pacing_does_not_burst_after_stalls_or_rate_changes() {
        let now = Instant::now();
        let mut pacer = FramePacer::default();
        assert_eq!(pacer.delay(now, 120), Duration::ZERO);
        assert!(pacer.delay(now, 120).as_secs_f64() < 0.00834);
        assert_eq!(pacer.delay(now + Duration::from_secs(3), 120), Duration::ZERO);
        assert_eq!(pacer.delay(now + Duration::from_secs(3), 30), Duration::ZERO);
        assert_eq!(engine_frame_limit(120.0), 0);
        assert_eq!(engine_frame_limit(60.0), 0);
        assert_eq!(engine_frame_limit(30.0), 0);
    }
}
