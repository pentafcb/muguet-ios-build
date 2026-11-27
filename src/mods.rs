// muguet - mods.rs
// Add-on DLC mod install/remove. Install copies dlc.rpf into
// game/data/x64/dlcPacks/<name>/ and adds exactly one line to
// game/data/common/data/dlcList.xml; remove deletes only that one
// folder and only that mod's lines. The XML is edited line by line,
// never re-serialized, so other mods and the stock packs are untouched.

use anyhow::{bail, Context, Result};
use std::fs::File;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

// The 11 packs that ship with the game. They are never listed as
// mods, never installed over, and never removed.
pub const STOCK_PACKS: &[&str] = &[
    "mpbeach", "mpbusiness", "mpbusiness2", "mpchristmas", "mphipster",
    "mpindependence", "mplts", "mppilot", "mpvalentines", "spupgrade", "verityradio",
];

pub fn is_stock(name: &str) -> bool {
    STOCK_PACKS.contains(&name.to_ascii_lowercase().as_str())
}

// Mod names are folder names and XML values, so keep them to a safe
// alphabet: lowercase letters, digits and underscore.
pub fn sanitize_name(raw: &str) -> String {
    raw.trim()
        .to_ascii_lowercase()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect()
}

fn packs_dir() -> PathBuf {
    crate::config::game_dir().join("data/x64/dlcPacks")
}

fn dlc_list_path() -> PathBuf {
    crate::config::game_dir().join("data/common/data/dlcList.xml")
}

// True when this line already lists this pack, in either of the two
// formats the game understands (platform:\dlcPacks\<name>\ and
// dlcpacks:/<name>/). The trailing separator keeps "low" from
// matching "loweyezv".
fn line_lists_pack(line: &str, name: &str) -> bool {
    let lower = line.to_ascii_lowercase().replace('/', "\\");
    lower.contains(&format!("dlcpacks\\{name}\\"))
}

fn read_dlc_list() -> Result<(PathBuf, String)> {
    let path = dlc_list_path();
    let text = std::fs::read_to_string(&path).with_context(|| format!("cannot read {}", path.display()))?;
    Ok((path, text))
}

// Rejoin lines with the file's own newline style, keeping a trailing
// newline exactly when the original had one.
fn join_lines(text: &str, lines: &[String]) -> String {
    let nl = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let mut out = lines.join(nl);
    if text.ends_with('\n') {
        out.push_str(nl);
    }
    out
}

fn add_dlc_list_line(name: &str) -> Result<()> {
    let (path, text) = read_dlc_list()?;
    if text.lines().any(|l| line_lists_pack(l, name)) {
        return Ok(());
    }
    let mut lines: Vec<String> = text.lines().map(str::to_string).collect();
    let Some(pos) = lines.iter().position(|l| l.trim() == "</Paths>") else {
        bail!("dlcList.xml has no </Paths> line, refusing to edit it");
    };
    lines.insert(pos, format!("        <Item>platform:\\dlcPacks\\{name}\\</Item>"));
    let out = join_lines(&text, &lines);
    crate::import::write_atomic(&path, out.as_bytes())?;
    Ok(())
}

fn remove_dlc_list_lines(name: &str) -> Result<()> {
    let (path, text) = read_dlc_list()?;
    let kept: Vec<String> = text.lines().filter(|l| !line_lists_pack(l, name)).map(str::to_string).collect();
    if kept.len() == text.lines().count() {
        return Ok(());
    }
    let out = join_lines(&text, &kept);
    crate::import::write_atomic(&path, out.as_bytes())?;
    Ok(())
}

fn open_zip(path: &Path) -> Result<zip::ZipArchive<std::io::BufReader<File>>> {
    let file = File::open(path).with_context(|| format!("cannot open {}", path.display()))?;
    zip::ZipArchive::new(std::io::BufReader::with_capacity(1 << 20, file))
        .context("cannot read the zip (incomplete, corrupt, or not a zip)")
}

// Index of the shallowest dlc.rpf entry at any depth, so a wrapper
// folder in the zip does not break the install.
fn find_dlc_rpf(zip: &mut zip::ZipArchive<std::io::BufReader<File>>) -> Result<usize> {
    anyhow::ensure!(zip.len() <= 100_000, "zip has too many entries");
    let mut best: Option<(usize, usize)> = None;
    for k in 0..zip.len() {
        let entry = zip.by_index_raw(k)?;
        let Some(n) = entry.enclosed_name() else { continue };
        if entry.is_dir() {
            continue;
        }
        let name = n.to_string_lossy().replace('\\', "/");
        let lower = name.to_ascii_lowercase();
        if !lower.ends_with("/dlc.rpf") && lower != "dlc.rpf" {
            continue;
        }
        let depth = name.matches('/').count();
        if best.as_ref().map_or(true, |(d, _)| depth < *d) {
            best = Some((depth, k));
        }
    }
    let Some((_, idx)) = best else {
        bail!("this zip has no dlc.rpf in it");
    };
    Ok(idx)
}

// Mod name for a zip install: the parent folder of dlc.rpf inside
// the zip (loweyezv/dlc.rpf -> loweyezv), else the zip filename.
fn mod_name_from_zip(zip_path: &Path) -> Result<String> {
    let mut zip = open_zip(zip_path)?;
    let idx = find_dlc_rpf(&mut zip)?;
    let entry = zip.by_index_raw(idx)?;
    let Some(name) = entry.enclosed_name() else {
        bail!("could not read the dlc.rpf entry name");
    };
    let name = name.to_string_lossy().replace('\\', "/");
    let parent = name.rsplit('/').nth(1).unwrap_or("");
    let derived = sanitize_name(parent);
    if !derived.is_empty() {
        return Ok(derived);
    }
    let stem = zip_path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let derived = sanitize_name(stem);
    if derived.is_empty() {
        bail!("could not work out a name for this mod");
    }
    Ok(derived)
}

fn extract_dlc_rpf(zip_path: &Path, dest: &Path) -> Result<()> {
    let mut zip = open_zip(zip_path)?;
    let idx = find_dlc_rpf(&mut zip)?;
    let mut entry = zip.by_index(idx)?;
    // A zip bomb (small compressed, huge uncompressed) used to write
    // until the disk was full. A real dlc.rpf is tens to low hundreds
    // of MB; 2 GB is a generous cap.
    anyhow::ensure!(entry.size() <= 2 << 30, "dlc.rpf inside the zip is too large");
    let mut out = File::create(dest).with_context(|| format!("cannot write {}", dest.display()))?;
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = entry.read(&mut buf).with_context(|| "reading dlc.rpf from the zip")?;
        if n == 0 {
            break;
        }
        out.write_all(&buf[..n])?;
    }
    Ok(())
}

// Install the picked file (.zip or bare .rpf). name_hint is the name
// the user typed for a bare .rpf; for a zip it is empty and the name
// comes from the zip structure. Returns the installed mod name.
// The folder is written before the XML line, so a failed XML edit
// leaves an inert unlisted folder instead of a dangling XML line.
pub fn install_mod(picked: &Path, name_hint: &str) -> Result<String> {
    let ext = picked.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
    let name = if ext == "zip" {
        let hint = sanitize_name(name_hint);
        if hint.is_empty() {
            mod_name_from_zip(picked)?
        } else {
            hint
        }
    } else if ext == "rpf" {
        sanitize_name(name_hint)
    } else {
        bail!("unsupported file: pick a .zip or a .rpf");
    };
    if name.is_empty() {
        bail!("enter a name for the mod (e.g. loweyezv)");
    }
    if is_stock(&name) {
        bail!("{name} is a built-in game pack and cannot be replaced");
    }
    let dest_dir = packs_dir().join(&name);
    std::fs::create_dir_all(&dest_dir).with_context(|| format!("cannot create {}", dest_dir.display()))?;
    let dest = dest_dir.join("dlc.rpf");
    if ext == "zip" {
        extract_dlc_rpf(picked, &dest)?;
    } else {
        std::fs::copy(picked, &dest).with_context(|| format!("cannot copy {}", picked.display()))?;
    }
    add_dlc_list_line(&name)?;
    crate::debug::console_line(&format!("[mods] installed {name}"));
    Ok(name)
}

// Remove only this mod: its folder under dlcPacks and only its own
// dlcList.xml lines. Stock packs are refused outright.
pub fn remove_mod(raw_name: &str) -> Result<()> {
    let name = sanitize_name(raw_name);
    if name.is_empty() {
        bail!("no mod name given");
    }
    if is_stock(&name) {
        bail!("{name} is a built-in game pack and cannot be removed");
    }
    let dir = packs_dir().join(&name);
    if dir.exists() {
        anyhow::ensure!(dir.is_dir(), "expected a folder for {name}");
        std::fs::remove_dir_all(&dir).with_context(|| format!("cannot remove {}", dir.display()))?;
    }
    remove_dlc_list_lines(&name)?;
    crate::debug::console_line(&format!("[mods] removed {name}"));
    Ok(())
}

#[cfg(target_os = "ios")]
mod ffi {
    use std::ffi::{c_char, CStr, CString};
    use std::sync::Mutex;

    static ERROR: Mutex<Option<CString>> = Mutex::new(None);
    static LAST_NAME: Mutex<Option<CString>> = Mutex::new(None);

    fn set_error(message: String) {
        *ERROR.lock().unwrap_or_else(|e| e.into_inner()) = CString::new(message).ok();
    }

    fn cstr_or_empty(ptr: *const c_char) -> String {
        if ptr.is_null() {
            return String::new();
        }
        unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
    }

    #[no_mangle]
    pub extern "C" fn muguet_install_mod(path: *const c_char, name: *const c_char) -> bool {
        let path = cstr_or_empty(path);
        let name = cstr_or_empty(name);
        match super::install_mod(std::path::Path::new(&path), &name) {
            Ok(installed) => {
                *LAST_NAME.lock().unwrap_or_else(|e| e.into_inner()) = CString::new(installed).ok();
                true
            }
            Err(e) => {
                set_error(format!("{e:#}"));
                false
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn muguet_remove_mod(name: *const c_char) -> bool {
        match super::remove_mod(&cstr_or_empty(name)) {
            Ok(()) => true,
            Err(e) => {
                set_error(format!("{e:#}"));
                false
            }
        }
    }

    // The returned pointer is only valid until the next install/remove
    // call, which replaces the string behind it. Swift must copy it
    // out before installing or removing again.
    #[no_mangle]
    pub extern "C" fn muguet_mod_error() -> *const c_char {
        ERROR.lock().unwrap_or_else(|e| e.into_inner()).as_ref().map(|s| s.as_ptr()).unwrap_or(std::ptr::null())
    }

    #[no_mangle]
    pub extern "C" fn muguet_mod_name() -> *const c_char {
        LAST_NAME.lock().unwrap_or_else(|e| e.into_inner()).as_ref().map(|s| s.as_ptr()).unwrap_or(std::ptr::null())
    }
}
