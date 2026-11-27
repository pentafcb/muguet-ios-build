// muguet - import.rs
// Constantin Clerc (c22dev) - 0.1

use anyhow::{bail, Context, Result};
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;

use crate::game_data::SKIPPED_DIRS;

pub fn import(zip_path: &Path, dest: &Path, keep_code: bool, mut progress: impl FnMut(u64, u64)) -> Result<()> {
    let file = File::open(zip_path).with_context(|| format!("{}", zip_path.display()))?;
    let mut zip = zip::ZipArchive::new(std::io::BufReader::with_capacity(1 << 20, file))
        .context("Cannot read the ZIP directory. The file may be incomplete, corrupt, or one part of a split archive. Download the complete game.zip to On My iPhone before importing; renaming RAR/7z to .zip does not convert it")?;
    // A zip with millions of entries used to exhaust memory building
    // the name/job lists, and a zip-bomb (small compressed, huge
    // uncompressed) wrote until the disk was full. Cap both up front.
    anyhow::ensure!(zip.len() <= 1_000_000, "Game zip has too many entries");

    let names: Vec<String> = zip.file_names().map(String::from).collect();
    let manifest = names
        .iter()
        .filter(|n| n.ends_with("data/manifest.json") && (n.len() == "data/manifest.json".len() || n.ends_with("/data/manifest.json")))
        .min_by_key(|n| n.len())
        .context("this zip has no game data (data/manifest.json)")?;
    let prefix = manifest[..manifest.len() - "data/manifest.json".len()].to_string();
    if !names.iter().any(|n| n.starts_with(&format!("{prefix}b/")) && n.ends_with("/shaders/index.json")) {
        bail!("this zip has no shaders (b/<build>/shaders)");
    }
    if keep_code && !names.iter().any(|n| n.starts_with(&format!("{prefix}b/")) && n.ends_with("/game.wasm")) {
        bail!("this zip has no game code (b/<build>/game.wasm)");
    }

    let wanted = |rel: &str| -> bool {
        if !(rel.starts_with("data/") || rel.starts_with("b/")) || rel.ends_with('/') {
            return false;
        }
        if rel.split('/').any(|c| SKIPPED_DIRS.contains(&c.to_ascii_lowercase().as_str())) {
            return false;
        }
        if let Some(build) = rel.strip_prefix("b/") {
            let inner = build.split_once('/').map(|(_, r)| r).unwrap_or("");
            return inner.starts_with("shaders/") || (keep_code && inner == "game.wasm");
        }
        true
    };

    let mut jobs = Vec::new();
    let mut total = 0u64;
    for k in 0..zip.len() {
        let entry = zip.by_index_raw(k)?;
        let Some(name) = entry.enclosed_name() else { continue };
        let name = name.to_string_lossy().replace('\\', "/");
        let Some(rel) = name.strip_prefix(&prefix) else { continue };
        if entry.is_dir() || !wanted(rel) {
            continue;
        }
        total = total.checked_add(entry.size()).context("Game zip total size overflows")?;
        jobs.push((k, rel.to_string()));
    }
    anyhow::ensure!(total <= 64 << 30, "Game zip is too large ({} GB uncompressed)", total >> 30);

    let staging = dest.with_extension("importing");
    let _ = std::fs::remove_dir_all(&staging);
    std::fs::create_dir_all(&staging)?;
    // Extract + swap inside a closure so a mid-import failure cleans up
    // staging instead of leaving orphaned gigabytes behind.
    let result = (|| -> Result<()> {
        let mut done = 0u64;
        let mut reported = 0u64;
        progress(0, total);
        let mut buf = vec![0u8; 1 << 20];
        for (k, rel) in &jobs {
            let mut entry = zip.by_index(*k)?;
            let out_path = staging.join(rel);
            if let Some(parent) = out_path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            let mut out = File::create(&out_path).with_context(|| format!("{}", out_path.display()))?;
            loop {
                let n = entry.read(&mut buf).with_context(|| format!("reading {rel} from the zip"))?;
                if n == 0 {
                    break;
                }
                out.write_all(&buf[..n])?;
                done += n as u64;
                if done - reported >= 64 << 20 {
                    reported = done;
                    progress(done, total);
                }
            }
        }

        tidy_lists(&staging.join("data"))?;
        // Rollback-safe swap: the old game used to be deleted BEFORE the
        // rename was known to succeed, so a failed rename left the user
        // with no game at all. Move the old game aside first, rename
        // staging in, and only then delete the backup — restoring it on
        // any failure.
        let backup = dest.with_extension("old");
        let _ = std::fs::remove_dir_all(&backup);
        if dest.exists() {
            std::fs::rename(dest, &backup)?;
        }
        match std::fs::rename(&staging, dest) {
            Ok(()) => {
                let _ = std::fs::remove_dir_all(&backup);
                Ok(())
            }
            Err(e) => {
                let _ = std::fs::rename(&backup, dest);
                Err(e.into())
            }
        }
    })();
    if result.is_err() {
        let _ = std::fs::remove_dir_all(&staging);
    }
    result?;
    progress(total, total);
    Ok(())
}

pub(crate) fn write_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    // fs::write truncates then writes: a crash or disk-full mid-write
    // used to leave a truncated dlcList.xml/manifest.json that the game
    // then failed validation on. Write to a temp file and rename.
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

fn tidy_lists(data: &Path) -> Result<()> {
    let dlc = data.join("common/data/dlcList.xml");
    if let Ok(text) = std::fs::read_to_string(&dlc) {
        let kept: Vec<&str> = text.lines().filter(|l| !SKIPPED_DIRS.iter().any(|d| l.to_ascii_lowercase().contains(d))).collect();
        write_atomic(&dlc, (kept.join("\n") + "\n").as_bytes())?;
    }
    let manifest_path = data.join("manifest.json");
    let manifest = crate::game_data::load_manifest(data)?;
    write_atomic(&manifest_path, &serde_json::to_vec(&manifest)?)?;
    Ok(())
}

#[cfg(target_os = "ios")]
mod ffi {
    use std::ffi::{c_char, CStr, CString};
    use std::sync::Mutex;

    static ERROR: Mutex<Option<CString>> = Mutex::new(None);

    #[no_mangle]
    pub extern "C" fn muguet_import(zip: *const c_char, progress: extern "C" fn(u64, u64)) -> bool {
        // A null zip pointer from Swift used to be passed straight to
        // CStr::from_ptr — immediate UB at the FFI boundary.
        if zip.is_null() {
            *ERROR.lock().unwrap_or_else(|e| e.into_inner()) = CString::new("Import failed: no zip path").ok();
            return false;
        }
        let path = unsafe { CStr::from_ptr(zip) }.to_string_lossy().into_owned();
        match super::import(std::path::Path::new(&path), &crate::config::game_dir(), false, |d, t| progress(d, t)) {
            Ok(()) => true,
            Err(e) => {
                *ERROR.lock().unwrap_or_else(|e| e.into_inner()) = CString::new(format!("{e:#}")).ok();
                false
            }
        }
    }

    // The returned pointer is only valid until the next muguet_import
    // call, which replaces the string behind it. Swift must copy it
    // out before importing again.
    #[no_mangle]
    pub extern "C" fn muguet_import_error() -> *const c_char {
        ERROR.lock().unwrap_or_else(|e| e.into_inner()).as_ref().map(|s| s.as_ptr()).unwrap_or(std::ptr::null())
    }

    #[no_mangle]
    pub extern "C" fn muguet_game_ready() -> bool {
        crate::config::game_ready()
    }

    #[no_mangle]
    pub extern "C" fn muguet_has_game_code() -> bool {
        crate::has_game_code()
    }
}
