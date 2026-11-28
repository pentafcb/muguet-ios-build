// Built-in Sky Pack mod: the FiveM PvP community looks (Pink Sky With
// Stars, All Black Sky With Stars, Cyan Sky, Purple Sky No Sun), all
// NO CLOUDS, NO RAIN, NO SHADOWS — built into the app, not a player mod.
//
// What a FiveM sky pack actually is: files copied into the FiveM
// citizen folder that replace the stock timecycle weather files
// (w_<weather>.xml), visualsettings.dat, and the sky/cloud textures
// (skydome.ytd / clouds.ytd). The sky colour comes from the timecycle
// file, not from a texture: each weather file holds one <cycle> with
// GLOBAL and URBAN regions, and each variable is one element per
// channel holding one float per time slot, e.g.
//   <light_dir_col_r> 0.7393 1.0000 ... </light_dir_col_r>
// (GTAForums North Yankton thread; fivemad timecycle docs).
//
// What this port can do, and what it cannot:
// - It CAN edit the stock timecycle text files on disk, the same way
//   the Mods manager merges metas: backup-once .bak, surgical
//   replacement, restore on Off, manifest size tolerance in
//   src/game_data.rs. The engine reads the files at load, so the sky
//   colour applies on Play (next launch), not live mid-session. The
//   look is painted into EVERY weather file (w_extrasunny, w_clouds,
//   w_rain, ...), so the colour shows in any weather — the first
//   version only painted EXTRASUNNY, and the sky stayed stock
//   whenever the weather was anything else.
// - It CANNOT author a .ytd (Rockstar texture dictionary), so the
//   packs' starfield image (the "stars" in the screenshots, painted
//   into skydome.ytd) cannot be reproduced. The engine's own stars
//   still show at night when the sky is dark (Black look).
// - It CANNOT set arbitrary timecycle variables at runtime:
//   SET_TIMECYCLE_MODIFIER_VAR is FiveM-only, not a stock native.
//   No stock modifier paints a sky pink/black/cyan/purple, so no
//   modifier natives are wired — a tint would be the wrong look.
// - No rain is the weather: the look forces EXTRASUNNY persist —
//   live, no restart, but ONLY if this build wires the weather
//   native (SetWeatherTypeNowPersist). The console probes it once
//   and says so honestly; if it is missing, rain can still fall
//   under a pink sky. The colour does not depend on it.
// - No shadows is settings.xml ShadowQuality 0, forced in
//   config.rs fix_settings while a look is active — live on Play.
// - No clouds is the file edit: cloud_opacity 0 where the file has
//   that variable, and the cloud base colour set to the sky colour so
//   any remaining cloud blends into the sky.
//
// Safety: the replacement only touches an element whose inner content
// is entirely whitespace-separated floats, and only rewrites it with
// the SAME count of numbers (12 or 13 slots — the file decides, never
// assumed). An element that is missing, or shaped differently, is
// skipped and reported, never written. A file where nothing matched
// is left untouched. The .bak is the pristine stock file, written
// once, never overwritten.

use std::path::{Path, PathBuf};

// Sky colours, 0..1 floats (timecycle colours are 0..1, not 0..255).
// Chosen to match the pack screenshots; the packs' exact values are
// inside their .ytd/timecycle files, which we do not have.
pub fn look_rgb(look: &str) -> Option<(f32, f32, f32)> {
    match look {
        "pink" => Some((1.0, 0.4157, 0.7804)),
        "black" => Some((0.0, 0.0, 0.0)),
        "cyan" => Some((0.0, 0.85, 1.0)),
        "purple" => Some((0.58, 0.25, 0.95)),
        _ => None,
    }
}

pub fn parse_look(s: &str) -> Option<&'static str> {
    match s.trim().to_ascii_lowercase().as_str() {
        "off" => Some("off"),
        "pink" => Some("pink"),
        "black" => Some("black"),
        "cyan" => Some("cyan"),
        "purple" => Some("purple"),
        _ => None,
    }
}

pub fn sky_active(look: &str) -> bool {
    parse_look(look).map(|l| l != "off").unwrap_or(false)
}

pub fn env_look() -> Option<String> {
    std::env::var("MUGUET_SKY").ok()
}

// Manifest tolerance predicate (called from game_data.rs): the sky
// edit changes the weather file's size, so its manifest record must
// be corrected in memory like the merged metas. Matches every weather
// file in the timecycle dir, whatever its extension.
pub fn is_sky_timecycle_file(name: &str) -> bool {
    name.to_ascii_lowercase()
        .starts_with("common/data/timecycle/w_")
}

// Replace every occurrence of one timecycle element with the same
// count of a single value, formatted to 4 decimals like the stock
// files. The element must hold only whitespace-separated floats;
// anything else (a missing element, a non-numeric body) is skipped
// untouched. Returns the new text and how many elements changed.
pub fn replace_channel_values(text: &str, element: &str, value: f32) -> (String, usize) {
    let open = format!("<{element}>");
    let close = format!("</{element}>");
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    let mut replaced = 0;
    while let Some(start) = rest.find(&open) {
        let body_start = start + open.len();
        let Some(end_rel) = rest[body_start..].find(&close) else {
            break;
        };
        let body = &rest[body_start..body_start + end_rel];
        let tokens: Vec<&str> = body.split_whitespace().collect();
        let all_numbers = !tokens.is_empty() && tokens.iter().all(|t| t.parse::<f32>().is_ok());
        out.push_str(&rest[..start]);
        if all_numbers {
            // Preserve the body's leading/trailing whitespace, so
            // the replacement is a minimal diff to the stock file.
            let lead = body.len() - body.trim_start().len();
            let trail = body.len() - body.trim_end().len();
            out.push_str(&open);
            out.push_str(&body[..lead]);
            for i in 0..tokens.len() {
                if i > 0 {
                    out.push(' ');
                }
                out.push_str(&format!("{value:.4}"));
            }
            out.push_str(&body[body.len() - trail..]);
            out.push_str(&close);
            replaced += 1;
        } else {
            out.push_str(&rest[start..body_start + end_rel + close.len()]);
        }
        rest = &rest[body_start + end_rel + close.len()..];
    }
    out.push_str(rest);
    (out, replaced)
}

// Apply one look to a whole timecycle file's text: the sky zenith,
// the sky horizon (east), and the cloud base colour all become the
// look colour, and cloud opacity goes to zero where the file has
// that variable. Every element is replaced in every region (GLOBAL
// and URBAN both carry the same elements). Returns the new text, the
// total elements replaced, and the variable names that were not found
// at all (missing, not an error — a different file shape).
pub fn apply_look_to_text(text: &str, look: &str) -> (String, usize, Vec<String>) {
    let Some((r, g, b)) = look_rgb(look) else {
        return (text.to_string(), 0, Vec::new());
    };
    let channels: [(&str, f32); 9] = [
        ("sky_zenith_col_r", r),
        ("sky_zenith_col_g", g),
        ("sky_zenith_col_b", b),
        ("sky_east_col_r", r),
        ("sky_east_col_g", g),
        ("sky_east_col_b", b),
        ("sky_cloud_base_col_r", r),
        ("sky_cloud_base_col_g", g),
        ("sky_cloud_base_col_b", b),
    ];
    let mut current = text.to_string();
    let mut total = 0;
    let mut missing: Vec<String> = Vec::new();
    for (element, value) in channels {
        let (next, n) = replace_channel_values(&current, element, value);
        current = next;
        total += n;
        if n == 0 {
            missing.push(element.to_string());
        }
    }
    // cloud_opacity is a scalar, attempted only if the file has it:
    // a missing element is skipped and reported, never invented.
    let (next, n) = replace_channel_values(&current, "cloud_opacity", 0.0);
    current = next;
    total += n;
    if n == 0 {
        missing.push("cloud_opacity".to_string());
    }
    (current, total, missing)
}

// Find every weather file in the timecycle dir: any file whose name
// starts with w_ (w_extrasunny, w_clouds, w_rain, ...), whatever its
// extension. The .bak backups this feature writes start with w_
// too, so they are excluded — and so are .tmp leftovers from an
// interrupted atomic write — or a restore would try to paint the
// backup itself. timecycle_mods_*.xml files are modifiers, not
// weather files, and do not start with w_. Deterministic: sorted
// file-name order.
pub fn find_timecycle_files(dir: &Path) -> Vec<PathBuf> {
    let mut names: Vec<PathBuf> = Vec::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return names;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let is_file = entry.file_type().map(|t| t.is_file()).unwrap_or(false);
        let name = entry.file_name().to_string_lossy().to_ascii_lowercase();
        if is_file && name.starts_with("w_") && !name.ends_with(".bak") && !name.ends_with(".tmp") {
            names.push(path);
        }
    }
    names.sort();
    names
}

// One weather file's verdict. The console prints only the aggregate
// message (SkyReport::line()), and the harness asserts on these fields.
#[allow(dead_code)]
pub struct FileSkyReport {
    pub file_name: String,
    pub replaced: usize,
    pub missing: Vec<String>,
    pub restored: bool,
    pub already_applied: bool,
    pub skipped: bool,
    pub error: Option<String>,
}

// The fields are the structured verdict; the console prints only
// the message today (line()), and the harness asserts on the fields.
#[allow(dead_code)]
pub struct SkyReport {
    pub look: String,
    pub found: bool,
    pub files: Vec<FileSkyReport>,
    pub replaced: usize,
    pub restored: bool,
    pub already_applied: bool,
    pub message: String,
}

impl SkyReport {
    pub fn line(&self) -> String {
        format!("[sky] {}", self.message)
    }
}

// Apply one look to one weather file: backup-once, idempotent, and
// a file where nothing matches is left untouched (skipped). The .bak
// is the pristine stock file and is never overwritten — including a
// file the old single-file version already painted: it compares
// equal to the new text and reports already-applied, no clobber.
fn apply_look_to_file(look: &str, file: &Path) -> FileSkyReport {
    let file_name = file
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let bak = file.with_extension("bak");
    let Ok(current) = std::fs::read_to_string(file) else {
        return FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: false,
            already_applied: false,
            skipped: false,
            error: Some("unreadable — sky colour not applied".to_string()),
        };
    };
    let (next, replaced, missing) = apply_look_to_text(&current, look);
    if replaced == 0 {
        return FileSkyReport {
            file_name,
            replaced: 0,
            missing,
            restored: false,
            already_applied: false,
            skipped: true,
            error: None,
        };
    }
    if next == current {
        return FileSkyReport {
            file_name,
            replaced,
            missing,
            restored: false,
            already_applied: true,
            skipped: false,
            error: None,
        };
    }
    // Only now, when a real write is coming, take the backup —
    // and only once, so the .bak stays the pristine stock file.
    if !bak.exists() {
        let _ = std::fs::copy(file, &bak);
    }
    match crate::import::write_atomic(file, next.as_bytes()) {
        Ok(()) => FileSkyReport {
            file_name,
            replaced,
            missing,
            restored: false,
            already_applied: false,
            skipped: false,
            error: None,
        },
        Err(e) => FileSkyReport {
            file_name,
            replaced,
            missing,
            restored: false,
            already_applied: false,
            skipped: false,
            error: Some(format!("write failed: {e}")),
        },
    }
}

// Restore one weather file from its .bak. No .bak means the file
// was never edited, so it is already stock.
fn restore_file(file: &Path) -> FileSkyReport {
    let file_name = file
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let bak = file.with_extension("bak");
    let Ok(current) = std::fs::read_to_string(file) else {
        return FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: false,
            already_applied: false,
            skipped: false,
            error: Some("unreadable — stock file NOT restored".to_string()),
        };
    };
    if !bak.exists() {
        return FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: false,
            already_applied: true,
            skipped: false,
            error: None,
        };
    }
    let Ok(stock) = std::fs::read(&bak) else {
        return FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: false,
            already_applied: false,
            skipped: false,
            error: Some("backup unreadable — stock file NOT restored".to_string()),
        };
    };
    if stock == current.as_bytes() {
        return FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: false,
            already_applied: true,
            skipped: false,
            error: None,
        };
    }
    match crate::import::write_atomic(file, &stock) {
        Ok(()) => FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: true,
            already_applied: false,
            skipped: false,
            error: None,
        },
        Err(e) => FileSkyReport {
            file_name,
            replaced: 0,
            missing: Vec::new(),
            restored: false,
            already_applied: false,
            skipped: false,
            error: Some(format!("restore failed: {e}")),
        },
    }
}

// Full apply/restore against a timecycle dir, across EVERY weather
// file in it. Backup-once per file: each .bak is the pristine stock
// file and is never overwritten. Applying a look that is already in
// a file writes nothing to that file. Off restores every file that
// has a .bak; files without one are already stock. One file failing
// (unreadable, write error) never aborts the others — each failure
// is reported in its own FileSkyReport and in the message.
pub fn apply_sky_in_dir(look: &str, dir: &Path) -> SkyReport {
    let Some(look) = parse_look(look) else {
        return SkyReport {
            look: look.to_string(),
            found: false,
            files: Vec::new(),
            replaced: 0,
            restored: false,
            already_applied: false,
            message: format!("unknown sky look: {look} (try: sky pink|black|cyan|purple|off)"),
        };
    };
    if !dir.is_dir() {
        return SkyReport {
            look: look.to_string(),
            found: false,
            files: Vec::new(),
            replaced: 0,
            restored: false,
            already_applied: false,
            message: format!("no timecycle dir at {}", dir.display()),
        };
    }
    let files = find_timecycle_files(dir);
    if files.is_empty() {
        return SkyReport {
            look: look.to_string(),
            found: false,
            files: Vec::new(),
            replaced: 0,
            restored: false,
            already_applied: false,
            message: "no weather files in the timecycle dir — sky colour not applied".to_string(),
        };
    }
    if look == "off" {
        let reports: Vec<FileSkyReport> = files.iter().map(|f| restore_file(f)).collect();
        let restored_n = reports.iter().filter(|r| r.restored).count();
        let errors: Vec<String> = reports
            .iter()
            .filter_map(|r| r.error.as_ref().map(|e| format!("{}: {e}", r.file_name)))
            .collect();
        let all_stock = restored_n == 0 && errors.is_empty();
        let message = if !errors.is_empty() {
            format!(
                "sky off — restore failed for {} file{} ({}); the rest are stock",
                errors.len(),
                if errors.len() == 1 { "" } else { "s" },
                errors.join("; ")
            )
        } else if restored_n > 0 {
            format!(
                "sky off — stock timecycle restored in {restored_n} file{} (takes effect on next launch)",
                if restored_n == 1 { "" } else { "s" }
            )
        } else {
            "sky off — stock files already in place (no backups to restore)".to_string()
        };
        return SkyReport {
            look: look.to_string(),
            found: true,
            files: reports,
            replaced: 0,
            restored: restored_n > 0,
            already_applied: all_stock,
            message,
        };
    }
    let reports: Vec<FileSkyReport> = files.iter().map(|f| apply_look_to_file(look, f)).collect();
    let replaced: usize = reports.iter().map(|r| r.replaced).sum();
    let matched_n = reports.iter().filter(|r| !r.skipped && r.error.is_none()).count();
    let written_n = reports
        .iter()
        .filter(|r| !r.already_applied && !r.skipped && r.error.is_none())
        .count();
    let errors: Vec<String> = reports
        .iter()
        .filter_map(|r| r.error.as_ref().map(|e| format!("{}: {e}", r.file_name)))
        .collect();
    let skipped: Vec<&str> = reports
        .iter()
        .filter(|r| r.skipped)
        .map(|r| r.file_name.as_str())
        .collect();
    let message = if !errors.is_empty() {
        format!(
            "{look} sky: write failed for {} file{} ({}); {written_n} file{} written",
            errors.len(),
            if errors.len() == 1 { "" } else { "s" },
            errors.join("; "),
            if written_n == 1 { "" } else { "s" }
        )
    } else if replaced == 0 {
        format!(
            "{look} sky: no timecycle variables matched in any of {} weather files — file shapes not recognized, nothing written",
            reports.len()
        )
    } else if written_n == 0 {
        format!("{look} sky already applied ({replaced} values across {matched_n} files) — takes effect on next launch")
    } else {
        let counts: Vec<String> = reports
            .iter()
            .filter(|r| !r.skipped && r.error.is_none())
            .map(|r| format!("{} {}", r.file_name, r.replaced))
            .collect();
        let mut message = format!(
            "{look} sky written ({replaced} values across {} files: {}) — sky colour takes effect on next launch; weather + shadows apply now",
            counts.len(),
            counts.join(", ")
        );
        let missing_notes: Vec<String> = reports
            .iter()
            .filter(|r| !r.missing.is_empty() && !r.skipped)
            .map(|r| format!("{}: no {}", r.file_name, r.missing.join(", ")))
            .collect();
        if !missing_notes.is_empty() {
            message.push_str(&format!(" (not in file: {})", missing_notes.join("; ")));
        }
        if !skipped.is_empty() {
            message.push_str(&format!(" (skipped, no variables matched: {})", skipped.join(", ")));
        }
        message
    };
    let all_applied = written_n == 0 && replaced > 0 && errors.is_empty();
    SkyReport {
        look: look.to_string(),
        found: true,
        files: reports,
        replaced,
        restored: false,
        already_applied: all_applied,
        message,
    }
}

// Startup entry: resolve the game-data timecycle dir and apply the
// look from the launcher setting. Called from config.rs settings()
// before the engine starts, so the engine reads the edited file.
pub fn apply_sky(look: &str) -> SkyReport {
    let dir = crate::config::game_dir().join("data/common/data/timecycle");
    apply_sky_in_dir(look, &dir)
}
