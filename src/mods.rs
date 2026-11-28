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
    std::fs::create_dir_all(&dest_dir)
        .with_context(|| format!("cannot create {}", dest_dir.display()))?;
    let dest = dest_dir.join("dlc.rpf");
    if ext == "zip" {
        extract_dlc_rpf(picked, &dest)?;
    } else {
        // Same 2 GB cap as the zip path: a bare .rpf used to copy
        // unbounded, so a bad pick could fill the disk.
        let size = std::fs::metadata(picked).map(|m| m.len()).unwrap_or(0);
        anyhow::ensure!(size <= 2 << 30, "dlc.rpf is too large");
        std::fs::copy(picked, &dest).with_context(|| format!("cannot copy {}", picked.display()))?;
    }
    add_dlc_list_line(&name)?;
    crate::debug::console_line(&format!("[mods] installed {name}"));
    Ok(name)
}

// vehicles.meta companion install. Some packs ship a vehicles.meta
// inside dlc.rpf that the RPF inspector cannot decompress (raw
// deflate + zlib both fail), so the game never registers the model
// and `car <code>` answers "Invalid vehicle model (not in game
// files)". The user picks the plaintext vehicles.meta and the
// launcher merges its models into the game's own vehicles.meta at
// data/common/data/levels/gta5/vehicles.meta, which the game does
// read. The base file is backed up to vehicles.meta.bak first, but
// only if no .bak exists yet, so the pristine stock file is kept.
// A copy of the picked .meta is kept in the mod's dlcPacks folder
// so removal can strip the same models back out.

fn base_vehicles_meta_path() -> PathBuf {
    crate::config::game_dir().join("data/common/data/levels/gta5/vehicles.meta")
}

fn mod_vehicles_meta_path(name: &str) -> PathBuf {
    packs_dir().join(name).join("vehicles.meta")
}

// All <modelName> values in the text, in order, de-duplicated
// case-insensitively (first spelling wins).
fn model_names_in(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut rest = text;
    while let Some(start) = rest.find("<modelName>") {
        let after = &rest[start + "<modelName>".len()..];
        let Some(end) = after.find("</modelName>") else {
            break;
        };
        let name = after[..end].trim().to_string();
        if !name.is_empty() && !out.iter().any(|n| n.eq_ignore_ascii_case(&name)) {
            out.push(name);
        }
        rest = &after[end + "</modelName>".len()..];
    }
    out
}

// End (exclusive byte index) of the <Item> block starting at
// `start`. Vehicle entries nest <Item>...</Item> pairs inside
// themselves (doorsWithCollisionWhenClosed, cinematicPartCamera,
// firstPersonDrivebyData), so the block does NOT end at the first
// </Item> — depth-count to the matching close. A flat scan used to
// truncate the block there and leave the merged file unbalanced.
fn item_block_end(text: &str, start: usize) -> Option<usize> {
    let mut depth = 0usize;
    let mut pos = start;
    loop {
        let next_open = text[pos..].find("<Item>").map(|i| pos + i);
        let next_close = text[pos..].find("</Item>").map(|i| pos + i);
        match (next_open, next_close) {
            (Some(o), Some(c)) if o < c => {
                depth += 1;
                pos = o + "<Item>".len();
            }
            (_, Some(c)) => {
                depth = depth.checked_sub(1)?;
                pos = c + "</Item>".len();
                if depth == 0 {
                    return Some(pos);
                }
            }
            _ => return None,
        }
    }
}

// The <Item>...</Item> block that declares this model, if any.
// Only top-level blocks are considered: after one is scanned, the
// search resumes past its end, so nested items are never mistaken
// for vehicle entries.
fn item_block_for(text: &str, model: &str) -> Option<String> {
    let mut pos = 0;
    while let Some(start) = text[pos..].find("<Item>").map(|i| pos + i) {
        let Some(end) = item_block_end(text, start) else {
            break;
        };
        let block = &text[start..end];
        if model_names_in(block)
            .iter()
            .any(|n| n.eq_ignore_ascii_case(model))
        {
            return Some(block.to_string());
        }
        pos = end;
    }
    None
}

// Remove the <Item> blocks for these models. Returns the new text
// and the model names actually removed.
fn strip_item_blocks(text: &str, models: &[String]) -> (String, Vec<String>) {
    let mut out = String::with_capacity(text.len());
    let mut removed: Vec<String> = Vec::new();
    let mut pos = 0;
    while let Some(start) = text[pos..].find("<Item>").map(|i| pos + i) {
        let Some(end) = item_block_end(text, start) else {
            break;
        };
        let block = &text[start..end];
        let names = model_names_in(block);
        out.push_str(&text[pos..start]);
        if names
            .iter()
            .any(|n| models.iter().any(|m| m.eq_ignore_ascii_case(n)))
        {
            for n in names {
                if !removed.iter().any(|r| r.eq_ignore_ascii_case(&n)) {
                    removed.push(n);
                }
            }
            // Drop the removed block's own line ending so no blank
            // line is left behind.
            let mut next = end;
            if text[next..].starts_with("\r\n") {
                next += 2;
            } else if text[next..].starts_with('\n') {
                next += 1;
            }
            pos = next;
        } else {
            out.push_str(block);
            pos = end;
        }
    }
    out.push_str(&text[pos..]);
    (out, removed)
}

fn base_has_model(text: &str, model: &str) -> bool {
    text.to_ascii_lowercase().contains(&format!(
        "<modelname>{}</modelname>",
        model.to_ascii_lowercase()
    ))
}

// Pure merge: insert the <Item> blocks for models not already in
// the base, before </InitDatas>. Returns None when the base has no
// </InitDatas>. Re-merging is a no-op (already-registered models
// are skipped), so the install is idempotent.
fn merge_vehicles_meta(base: &str, mod_text: &str, models: &[String]) -> Option<String> {
    let close = base.find("</InitDatas>")?;
    let nl = if base.contains("\r\n") { "\r\n" } else { "\n" };
    let mut blocks: Vec<String> = Vec::new();
    for model in models {
        if base_has_model(base, model) {
            continue;
        }
        if let Some(block) = item_block_for(mod_text, model) {
            blocks.push(block);
        }
    }
    if blocks.is_empty() {
        return Some(base.to_string());
    }
    let mut merged = String::with_capacity(base.len() + blocks.join(nl).len());
    merged.push_str(&base[..close]);
    merged.push_str(&blocks.join(nl));
    merged.push_str(nl);
    merged.push_str(&base[close..]);
    Some(merged)
}

/// True when the game's own vehicles.meta already registers this
/// model (used by spawninfo so a merged model is not reported as
/// "not in the game files").
pub fn base_vehicles_meta_has(model: &str) -> bool {
    let Ok(text) = std::fs::read_to_string(base_vehicles_meta_path()) else {
        return false;
    };
    base_has_model(&text, model)
}

// Install a companion vehicles.meta for a mod: merge its models
// into the game's vehicles.meta and keep a copy with the mod.
// Returns the model names the .meta defines. A missing base file
// is not a failure — the copy is kept with the mod and the merge
// is skipped with a note.
pub fn install_vehicles_meta(raw_name: &str, meta_path: &Path) -> Result<Vec<String>> {
    let name = sanitize_name(raw_name);
    if name.is_empty() {
        bail!("no mod name given");
    }
    if is_stock(&name) {
        bail!("{name} is a built-in game pack and cannot be replaced");
    }
    let bytes =
        std::fs::read(meta_path).with_context(|| format!("cannot read {}", meta_path.display()))?;
    anyhow::ensure!(
        bytes.len() <= 16 << 20,
        "vehicles.meta is too large (over 16 MB)"
    );
    let text = String::from_utf8(bytes).context("vehicles.meta is not valid UTF-8 text")?;
    anyhow::ensure!(
        text.contains("<InitDatas>"),
        "vehicles.meta has no <InitDatas> — not a vehicles.meta file"
    );
    let models = model_names_in(&text);
    anyhow::ensure!(
        !models.is_empty(),
        "vehicles.meta has no <modelName> — nothing to install"
    );

    // Validate the base before changing anything: without
    // </InitDatas> there is nowhere to insert, so bail here and
    // leave both the base file and the mod folder untouched.
    let base_path = base_vehicles_meta_path();
    let base_text = std::fs::read_to_string(&base_path).ok();
    let merged = match &base_text {
        Some(base) => Some(merge_vehicles_meta(base, &text, &models)),
        None => None,
    };
    if let Some(None) = merged {
        bail!("base vehicles.meta has no </InitDatas> — refusing to edit it");
    }

    // Keep a copy with the mod first: removal reads the model names
    // back from here, and the folder may not exist yet.
    let dest_dir = packs_dir().join(&name);
    std::fs::create_dir_all(&dest_dir)
        .with_context(|| format!("cannot create {}", dest_dir.display()))?;
    std::fs::copy(meta_path, mod_vehicles_meta_path(&name))
        .with_context(|| format!("cannot copy {}", meta_path.display()))?;

    match (base_text, merged) {
        (Some(base), Some(Some(new_text))) => {
            // Back up the pristine stock file once; never overwrite
            // an existing .bak.
            let bak = base_path.with_extension("meta.bak");
            if !bak.exists() {
                std::fs::copy(&base_path, &bak)
                    .with_context(|| format!("cannot back up {}", base_path.display()))?;
            }
            if new_text != base {
                crate::import::write_atomic(&base_path, new_text.as_bytes())?;
            }
            crate::debug::console_line(&format!(
                "[mods] vehicles.meta installed for {name}: {}",
                models.join(", ")
            ));
            crate::debug::console_line(
                "[mods] registered in base vehicles.meta — restart the game",
            );
        }
        _ => {
            crate::debug::console_line(&format!(
                "[mods] vehicles.meta installed for {name}: {}",
                models.join(", ")
            ));
            crate::debug::console_line(
                "[mods] base vehicles.meta not found — meta kept with the mod only",
            );
        }
    }
    Ok(models)
}

// Strip a mod's vehicles.meta models back out of the game's
// vehicles.meta. Best-effort: a missing base file or a failed
// strip never fails the removal — the caller reports it on the
// console instead.
fn remove_mod_meta(models: &[String]) -> Result<()> {
    if models.is_empty() {
        return Ok(());
    }
    let base_path = base_vehicles_meta_path();
    let text = std::fs::read_to_string(&base_path)
        .with_context(|| format!("cannot read {}", base_path.display()))?;
    let (stripped, removed) = strip_item_blocks(&text, models);
    if removed.is_empty() {
        return Ok(());
    }
    crate::import::write_atomic(&base_path, stripped.as_bytes())?;
    crate::debug::console_line(&format!(
        "[mods] removed {} from base vehicles.meta",
        removed.join(", ")
    ));
    Ok(())
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
    // The copied vehicles.meta lives inside the folder being
    // deleted, so read its model names first, then delete the
    // folder, then strip those models from the base file.
    let meta_models = std::fs::read_to_string(mod_vehicles_meta_path(&name))
        .map(|t| model_names_in(&t))
        .unwrap_or_default();
    let dir = packs_dir().join(&name);
    if dir.exists() {
        anyhow::ensure!(dir.is_dir(), "expected a folder for {name}");
        std::fs::remove_dir_all(&dir).with_context(|| format!("cannot remove {}", dir.display()))?;
    }
    remove_dlc_list_lines(&name)?;
    if let Err(e) = remove_mod_meta(&meta_models) {
        crate::debug::console_line(&format!(
            "[mods] warning: could not strip {name} from base vehicles.meta: {e:#}"
        ));
    }
    crate::debug::console_line(&format!("[mods] removed {name}"));
    Ok(())
}

#[cfg(target_os = "ios")]
mod ffi {
    use std::ffi::{c_char, CStr, CString};
    use std::sync::Mutex;

    static ERROR: Mutex<Option<CString>> = Mutex::new(None);
    static LAST_NAME: Mutex<Option<CString>> = Mutex::new(None);
    static LAST_META_MODELS: Mutex<Option<CString>> = Mutex::new(None);

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

    #[no_mangle]
    pub extern "C" fn muguet_install_vehicles_meta(
        mod_name: *const c_char,
        meta_path: *const c_char,
    ) -> bool {
        let mod_name = cstr_or_empty(mod_name);
        let meta_path = cstr_or_empty(meta_path);
        match super::install_vehicles_meta(&mod_name, std::path::Path::new(&meta_path)) {
            Ok(models) => {
                *LAST_META_MODELS.lock().unwrap_or_else(|e| e.into_inner()) =
                    CString::new(models.join(", ")).ok();
                true
            }
            Err(e) => {
                set_error(format!("{e:#}"));
                false
            }
        }
    }

    // The returned pointer is only valid until the next
    // install_vehicles_meta call, which replaces the string behind
    // it. Swift must copy it out before installing again.
    #[no_mangle]
    pub extern "C" fn muguet_vehicles_meta_models() -> *const c_char {
        LAST_META_MODELS
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|s| s.as_ptr())
            .unwrap_or(std::ptr::null())
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
