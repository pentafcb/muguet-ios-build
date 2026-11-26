#[cfg(target_os = "ios")]
pub fn install() {
    use std::os::fd::AsRawFd;
    // Trim at startup, not only from gpu.rs check_memory: a session that
    // never presents a frame never ran check_memory, so the runtime log
    // used to grow without bound within that launch.
    trim();
    let Some(home) = std::env::var_os("HOME") else { return };
    let dir = std::path::PathBuf::from(home).join("Documents");
    let path = dir.join("muguet-runtime.log");
    if path.exists() { let _ = std::fs::rename(&path, dir.join("muguet-previous.log")); }
    if let Ok(file) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        extern "C" { fn dup2(from: i32, to: i32) -> i32; }
        // dup2's result used to be unchecked; a failure silently left
        // stderr pointing nowhere and all diagnostics vanished. The
        // File is dropped (closed) at the end of this block — dup2 has
        // already duplicated the fd onto 2 by then.
        if unsafe { dup2(file.as_raw_fd(), 2) } < 0 {
            eprintln!("[diagnostics] dup2 to stderr failed; log output may be lost");
        }
        eprintln!("[diagnostics] build {} | device RAM {} MB | available {} MB", env!("CARGO_PKG_VERSION"),
            crate::performance::physical_memory() >> 20, crate::performance::available_memory().unwrap_or(0) >> 20);
    }

    std::panic::set_hook(Box::new(|info| {
        eprintln!("[CRASH/PANIC] {info}");
        // A jetsam kill is not a Rust panic and leaves no crash log, but a
        // panic does: record the run number and the last sampled memory and
        // GPU counts so the crash file can be matched to muguet-debug.log.
        // Guard the snapshot: if the panic happened inside snapshot_text
        // itself, the hook re-panicking would abort the process.
        let snap = std::panic::catch_unwind(std::panic::AssertUnwindSafe(crate::debug::snapshot_text))
            .unwrap_or_else(|_| "snapshot unavailable (panicked while sampling)".to_string());
        eprintln!("[CRASH] {snap}");
        if let Some(home) = std::env::var_os("HOME") {
            let crash_log = std::path::PathBuf::from(home).join("Documents/muguet-crash.log");
            // Append instead of truncating: a second panic used to
            // overwrite the first crash log. Rotate at 1 MiB.
            if std::fs::metadata(&crash_log).map(|m| m.len() > 1 << 20).unwrap_or(false) {
                let _ = std::fs::remove_file(&crash_log);
            }
            use std::io::Write;
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(crash_log) {
                let _ = writeln!(f, "[CRASH] {info}\n[CRASH] {snap}");
            }
        }
    }));
}

#[cfg(not(target_os = "ios"))]
pub fn install() {}

pub fn trim() {
    #[cfg(target_os = "ios")]
    if let Some(home) = std::env::var_os("HOME") {
        let path = std::path::PathBuf::from(home).join("Documents/muguet-runtime.log");
        if std::fs::metadata(&path).map(|m| m.len() > 4 << 20).unwrap_or(false) {
            // stderr is opened O_APPEND, so it stays usable after truncation.
            if let Ok(file) = std::fs::OpenOptions::new().write(true).open(path) { let _ = file.set_len(0); }
        }
    }
}
