// RPF7 archive reader (GTA V) — read-only inspection of a mod's
// dlc.rpf, so the console can say what is actually inside the pack
// instead of guessing: the true modelName from vehicles.meta, whether
// setup2.xml / content.xml exist, whether a changeset enables the
// vehicle metadata, and which .yft files are present.
// Format per CodeWalker (RpfFile.cs) and the community RPF7 reference:
// 16-byte header (version, entry count, names length, encryption),
// EntryCount x 16-byte TOC entries, then the names blob. Names are
// null-terminated ASCII in the names blob; engine lookups are by
// JOAAT, so a wrong model name silently never loads. File data lives
// in 512-byte blocks after the header region (header + TOC + names,
// rounded up to 512). Binary entries are stored or raw-DEFLATE
// compressed; resource entries (.yft etc.) carry a 16-byte RSC7
// header, then raw DEFLATE. Mod packs ship OPEN (unencrypted); an
// AES/NG TOC is reported, never guessed at.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

const RPF7_A: u32 = 0x52504637;
const RPF7_B: u32 = 0x37465052;
const ENC_NONE: u32 = 0;
const ENC_OPEN: u32 = 0x4E45504F;
const ENC_AES: u32 = 0x0FFFFFF9;
const ENC_NG: u32 = 0x0FEFFFFF;
const DIR_MARKER: u32 = 0x7FFFFF00;
const BLOCK: u64 = 512;
const MAX_ENTRIES: u32 = 200_000;
const MAX_NAMES: u32 = 16 << 20;
const MAX_FILE: u64 = 4 << 30;
const MAX_EXTRACT: u64 = 16 << 20;
const MAX_NAME: usize = 256;
const MAX_DEPTH: usize = 16;

// One TOC entry after classification. Directories are only used
// while walking the tree; files are kept for lookup.
#[derive(Clone)]
struct Entry {
    path: String,
    is_resource: bool,
    file_off_blocks: u32,
    file_size: u32,
    uncomp_size: u32,
    encrypted: bool,
}

// One raw 16-byte TOC record, as four little-endian words.
#[derive(Clone, Copy)]
struct RawEntry {
    b0: u32,
    b1: u32,
    b2: u32,
    b3: u32,
}

// Everything the console (and spawninfo) needs to say about a pack.
pub struct RpfReport {
    pub mod_name: String,
    pub rpf_size: u64,
    pub version: String,
    pub entry_count: u32,
    pub encryption: String,
    pub encrypted_toc: bool,
    pub parse_error: Option<String>,
    pub file_count: usize,
    pub dir_count: usize,
    pub setup2: bool,
    pub setup2_device: String,
    pub setup2_type: String,
    pub content: bool,
    pub vehicles_meta: Option<String>,
    pub model_names: Vec<String>,
    pub meta_in_data_files: bool,
    pub meta_file_type: String,
    pub meta_enabled_by: Vec<String>,
    pub yft_files: Vec<String>,
    pub verdict: String,
    // Warnings that do not stop the inspection (an entry that
    // would not decompress, XML that is not XML, ...).
    pub notes: Vec<String>,
}

impl RpfReport {
    // Full report for the `rpf` command.
    pub fn lines(&self) -> Vec<String> {
        let mut out = Vec::new();
        out.push(format!("[rpf] {}: {:.1} MB, {}, {} entries, encryption {}",
            self.mod_name, self.rpf_size as f64 / 1_048_576.0, self.version, self.entry_count, self.encryption));
        if let Some(e) = &self.parse_error {
            out.push(format!("[rpf] cannot inspect: {e}"));
            return out;
        }
        if self.encrypted_toc {
            out.push("[rpf] TOC is encrypted (AES/NG) — cannot inspect without the exe keys; the engine may still mount it".to_string());
            return out;
        }
        out.push(format!("[rpf] files: {} in {} folders", self.file_count, self.dir_count));
        out.push(if self.setup2 {
            format!("[rpf] setup2.xml: found (device {}, type {})", self.setup2_device, self.setup2_type)
        } else {
            "[rpf] setup2.xml: MISSING — the pack cannot register with the engine".to_string()
        });
        out.push(if self.content {
            "[rpf] content.xml: found".to_string()
        } else {
            "[rpf] content.xml: MISSING — no data files can register".to_string()
        });
        match &self.vehicles_meta {
            Some(p) => out.push(format!("[rpf] vehicles.meta: {p}")),
            None => out.push("[rpf] vehicles.meta: MISSING — no vehicle model is declared".to_string()),
        }
        if self.model_names.is_empty() {
            out.push("[rpf] modelName: none found".to_string());
        } else {
            out.push(format!("[rpf] modelName: {}", self.model_names.join(", ")));
        }
        if self.content {
            out.push(format!("[rpf] vehicles.meta in content.xml dataFiles: {}",
                if self.meta_in_data_files { format!("yes ({})", self.meta_file_type) } else { "no".to_string() }));
            out.push(format!("[rpf] vehicles.meta enabled by changeset: {}",
                if self.meta_enabled_by.is_empty() { "none".to_string() } else { self.meta_enabled_by.join(", ") }));
        }
        if self.yft_files.is_empty() {
            out.push("[rpf] .yft files: none".to_string());
        } else {
            let shown: Vec<&str> = self.yft_files.iter().take(6).map(String::as_str).collect();
            out.push(format!("[rpf] .yft files: {} ({})", self.yft_files.len(), shown.join(", ")));
        }
        for n in &self.notes {
            out.push(format!("[rpf] note: {n}"));
        }
        out.push(format!("[rpf] verdict: {}", self.verdict));
        out
    }

    // Condensed report for `spawninfo`: verdict plus the facts it
    // turns on, without the full file list.
    pub fn summary_lines(&self) -> Vec<String> {
        let mut out = Vec::new();
        if let Some(e) = &self.parse_error {
            out.push(format!("[rpf] cannot inspect: {e}"));
            return out;
        }
        if self.encrypted_toc {
            out.push("[rpf] TOC is encrypted (AES/NG) — cannot inspect; the engine may still mount it".to_string());
            return out;
        }
        out.push(format!("[rpf] setup2.xml: {}  content.xml: {}  vehicles.meta: {}",
            if self.setup2 { "found" } else { "MISSING" },
            if self.content { "found" } else { "MISSING" },
            self.vehicles_meta.clone().unwrap_or_else(|| "MISSING".to_string())));
        if self.model_names.is_empty() {
            out.push("[rpf] modelName: none found".to_string());
        } else {
            out.push(format!("[rpf] modelName: {}", self.model_names.join(", ")));
        }
        for n in &self.notes {
            out.push(format!("[rpf] note: {n}"));
        }
        out.push(format!("[rpf] verdict: {}", self.verdict));
        out
    }
}

fn u32le(b: &[u8], off: usize) -> u32 {
    u32::from_le_bytes([b[off], b[off + 1], b[off + 2], b[off + 3]])
}

fn align_up(v: u64, a: u64) -> u64 {
    (v + a - 1) / a * a
}

fn read_at(file: &mut File, off: u64, len: usize) -> Result<Vec<u8>, String> {
    let mut buf = vec![0u8; len];
    file.seek(SeekFrom::Start(off)).map_err(|e| format!("seek failed: {e}"))?;
    file.read_exact(&mut buf).map_err(|e| format!("read failed: {e}"))?;
    Ok(buf)
}

// Raw DEFLATE first (what RPF7 stores), zlib-wrapped as a fallback.
// The output cap keeps a corrupt size field from allocating forever.
fn inflate(bytes: &[u8]) -> Result<Vec<u8>, String> {
    use flate2::read::{DeflateDecoder, ZlibDecoder};
    for raw in [true, false] {
        let mut out = Vec::new();
        let n = if raw {
            let mut d = DeflateDecoder::new(bytes);
            d.by_ref().take(MAX_EXTRACT + 1).read_to_end(&mut out).map(|_| out.len())
        } else {
            let mut d = ZlibDecoder::new(bytes);
            d.by_ref().take(MAX_EXTRACT + 1).read_to_end(&mut out).map(|_| out.len())
        };
        match n {
            Ok(len) if len as u64 <= MAX_EXTRACT && !out.is_empty() => return Ok(out),
            _ => continue,
        }
    }
    Err("could not decompress (tried raw deflate + zlib)".to_string())
}

// Extracted bytes are only trusted as XML when they actually
// start with '<' — if the TOC offsets do not line up, inflate can
// succeed on the wrong bytes and produce garbage instead.
fn as_xml(bytes: Vec<u8>) -> Option<String> {
    let text = String::from_utf8_lossy(&bytes).into_owned();
    if text.trim_start().starts_with('<') {
        Some(text)
    } else {
        None
    }
}

// Every <tag>...</tag> body in a small XML file, trimmed. No real
// XML parser: these files are small, flat Rockstar metadata.
fn xml_tags(text: &str, tag: &str) -> Vec<String> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(s) = rest.find(&open) {
        let after = &rest[s + open.len()..];
        let Some(e) = after.find(&close) else { break; };
        let body = after[..e].trim().to_string();
        if !body.is_empty() {
            out.push(body);
        }
        rest = &after[e + close.len()..];
        if out.len() >= 32 {
            break;
        }
    }
    out
}

// One <filename> followed by its <fileType> inside content.xml's
// <dataFiles> block, in file order.
fn data_file_pairs(text: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let Some(d) = text.find("<dataFiles>") else { return out; };
    let rest = &text[d..];
    let Some(end) = rest.find("</dataFiles>") else { return out; };
    let mut block = &rest[..end];
    while let Some(s) = block.find("<filename>") {
        let after = &block[s + "<filename>".len()..];
        let Some(e) = after.find("</filename>") else { break; };
        let name = after[..e].trim().to_string();
        let after_name = &after[e + "</filename>".len()..];
        let ftype = match after_name.find("<fileType>") {
            Some(f) => {
                let a2 = &after_name[f + "<fileType>".len()..];
                match a2.find("</fileType>") {
                    Some(e2) => a2[..e2].trim().to_string(),
                    None => String::new(),
                }
            }
            None => String::new(),
        };
        if !name.is_empty() {
            out.push((name, ftype));
        }
        block = after_name;
        if out.len() >= 64 {
            break;
        }
    }
    out
}

// Each changeset name with the filenames its filesToEnable lists.
fn changeset_enables(text: &str) -> Vec<(String, Vec<String>)> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(s) = rest.find("<changeSetName>") {
        let after = &rest[s + "<changeSetName>".len()..];
        let Some(e) = after.find("</changeSetName>") else { break; };
        let name = after[..e].trim().to_string();
        let after_name = &after[e + "</changeSetName>".len()..];
        let mut items = Vec::new();
        if let Some(f) = after_name.find("<filesToEnable>") {
            let fb = &after_name[f + "<filesToEnable>".len()..];
            if let Some(fe) = fb.find("</filesToEnable>") {
                let mut b = &fb[..fe];
                while let Some(i) = b.find("<Item>") {
                    let a2 = &b[i + "<Item>".len()..];
                    let Some(e2) = a2.find("</Item>") else { break; };
                    let v = a2[..e2].trim().to_string();
                    if !v.is_empty() {
                        items.push(v);
                    }
                    b = &a2[e2 + "</Item>".len()..];
                    if items.len() >= 64 {
                        break;
                    }
                }
            }
        }
        if !name.is_empty() {
            out.push((name, items));
        }
        rest = after_name;
        if out.len() >= 16 {
            break;
        }
    }
    out
}

fn names_name(names: &[u8], off: usize) -> Option<String> {
    if off >= names.len() {
        return None;
    }
    let mut end = off;
    while end < names.len() && names[end] != 0 && end - off < MAX_NAME {
        if !(0x20..=0x7e).contains(&names[end]) {
            return None;
        }
        end += 1;
    }
    if end >= names.len() || names[end] != 0 {
        return None;
    }
    Some(String::from_utf8_lossy(&names[off..end]).into_owned())
}

// Walk one directory's contiguous child range. Directories recurse
// into their own ranges; files are collected with full paths.
fn walk(
    raw: &[RawEntry],
    names: &[u8],
    idx: usize,
    count: usize,
    prefix: &str,
    depth: usize,
    files: &mut Vec<Entry>,
    dirs: &mut usize,
) -> Result<(), String> {
    if depth > MAX_DEPTH {
        return Err("directory nesting too deep".to_string());
    }
    if idx.checked_add(count).map_or(true, |e| e > raw.len()) {
        return Err("directory range runs past the TOC".to_string());
    }
    for i in idx..idx + count {
        let e = raw[i];
        if e.b1 == DIR_MARKER {
            let name = names_name(names, e.b0 as usize).unwrap_or_default();
            *dirs += 1;
            let child_prefix = format!("{prefix}{name}/");
            walk(raw, names, e.b2 as usize, e.b3 as usize, &child_prefix, depth + 1, files, dirs)?;
        } else if e.b1 & 0x8000_0000 != 0 {
            // Resource file: name u16, size 3 bytes LE, offset
            // 3 bytes LE (&0x7FFFFF — the top bit is the marker).
            let name_off = (e.b0 & 0xFFFF) as usize;
            let file_size = ((e.b0 >> 16) & 0xFF) | (((e.b0 >> 24) & 0xFF) << 8) | ((e.b1 & 0xFF) << 16);
            let file_off = (e.b1 >> 8) & 0x7FFF_FF;
            let Some(name) = names_name(names, name_off) else { continue; };
            files.push(Entry {
                path: format!("{prefix}{name}"),
                is_resource: true,
                file_off_blocks: file_off,
                file_size,
                uncomp_size: 0,
                encrypted: false,
            });
        } else {
            // Binary file: first 8 bytes are a packed u64 — name
            // offset 16b, on-disk size 24b, offset in 512-blocks 24b.
            let packed = (e.b0 as u64) | ((e.b1 as u64) << 32);
            let name_off = (packed & 0xFFFF) as usize;
            let file_size = ((packed >> 16) & 0xFFFF_FF) as u32;
            let file_off = ((packed >> 40) & 0xFFFF_FF) as u32;
            let Some(name) = names_name(names, name_off) else { continue; };
            files.push(Entry {
                path: format!("{prefix}{name}"),
                is_resource: false,
                file_off_blocks: file_off,
                file_size,
                uncomp_size: e.b2,
                encrypted: e.b3 == 1,
            });
        }
        if files.len() > raw.len() {
            return Err("more files than TOC entries".to_string());
        }
    }
    Ok(())
}

// Extract one file's bytes. Binary entries are stored (size 0) or
// raw-DEFLATE compressed; resource entries are only presence-checked
// here (RSC7 magic), their full decode is not needed.
fn extract(file: &mut File, data_start: u64, e: &Entry) -> Result<Vec<u8>, String> {
    let pos = data_start
        .checked_add(e.file_off_blocks as u64 * BLOCK)
        .ok_or_else(|| "file offset overflow".to_string())?;
    if e.is_resource {
        // Only the 16-byte RSC7 header is needed; never read past
        // the entry's own declared size (0xFFFFFF means the true
        // size lives in that header, so read the header itself).
        let n = if e.file_size == 0xFFFF_FF { 16 } else { (e.file_size as usize).min(16) };
        if n < 4 {
            return Err("resource entry is smaller than its own header".to_string());
        }
        let head = read_at(file, pos, n)?;
        if head.len() < 4 || &head[0..4] != b"RSC7" {
            return Err("resource data does not start with RSC7 — TOC offsets do not line up".to_string());
        }
        return Ok(head);
    }
    if e.encrypted {
        return Err("entry is flagged encrypted".to_string());
    }
    if e.file_size == 0 {
        let len = e.uncomp_size as usize;
        if len as u64 > MAX_EXTRACT {
            return Err("stored file is implausibly large".to_string());
        }
        let bytes = read_at(file, pos, len)?;
        return Ok(bytes);
    }
    let raw = {
        // The files this reader extracts are small XML metadata;
        // cap the compressed read so a corrupt size field cannot
        // make read_at allocate gigabytes.
        if e.file_size as u64 > MAX_EXTRACT {
            return Err("compressed entry is implausibly large".to_string());
        }
        read_at(file, pos, e.file_size as usize)?
    };
    inflate(&raw)
}

fn find<'a>(files: &'a [Entry], wanted: &str) -> Option<&'a Entry> {
    let want = wanted.to_ascii_lowercase();
    files.iter().find(|e| {
        let p = e.path.to_ascii_lowercase();
        p == want || p.ends_with(&format!("/{want}"))
    })
}

fn base_name(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

// The pack's dlc.rpf: the folder as given, then lowercased (the
// installer sanitizes folder names to [a-z0-9_]).
pub fn mod_rpf_path(mod_name: &str) -> Option<PathBuf> {
    let base = crate::config::game_dir().join("data/x64/dlcPacks");
    let clean = mod_name.trim();
    if clean.is_empty() {
        return None;
    }
    let direct = base.join(clean).join("dlc.rpf");
    if direct.is_file() {
        return Some(direct);
    }
    let lower = base.join(clean.to_ascii_lowercase()).join("dlc.rpf");
    if lower.is_file() {
        return Some(lower);
    }
    None
}

pub fn inspect_rpf(path: &Path, mod_name: &str) -> RpfReport {
    let mut report = RpfReport {
        mod_name: mod_name.to_string(),
        rpf_size: std::fs::metadata(path).map(|m| m.len()).unwrap_or(0),
        version: "unknown".to_string(),
        entry_count: 0,
        encryption: "unknown".to_string(),
        encrypted_toc: false,
        parse_error: None,
        file_count: 0,
        dir_count: 0,
        setup2: false,
        setup2_device: String::new(),
        setup2_type: String::new(),
        content: false,
        vehicles_meta: None,
        model_names: Vec::new(),
        meta_in_data_files: false,
        meta_file_type: String::new(),
        meta_enabled_by: Vec::new(),
        yft_files: Vec::new(),
        verdict: String::new(),
        notes: Vec::new(),
    };
    let outcome = inspect_inner(path, &mut report);
    if let Err(e) = outcome {
        report.parse_error = Some(e);
    }
    report.verdict = verdict(&report);
    report
}

fn verdict(r: &RpfReport) -> String {
    if let Some(e) = &r.parse_error {
        return format!("cannot inspect: {e}");
    }
    if r.encrypted_toc {
        return "TOC is encrypted (AES/NG) — cannot inspect without the exe keys; the engine may still mount it".to_string();
    }
    if !r.setup2 {
        return "setup2.xml MISSING — the pack cannot register with the engine".to_string();
    }
    if !r.content {
        return "content.xml MISSING — no data files can register".to_string();
    }
    if r.vehicles_meta.is_none() {
        return "vehicles.meta MISSING — no vehicle model is declared".to_string();
    }
    if r.model_names.is_empty() {
        return "vehicles.meta has no <modelName> — nothing to spawn".to_string();
    }
    if !r.meta_in_data_files {
        return "vehicles.meta is NOT in content.xml dataFiles — the engine never loads it".to_string();
    }
    if r.meta_enabled_by.is_empty() {
        return "vehicles.meta is listed but no changeset enables it — the engine never loads it".to_string();
    }
    let missing_yft: Vec<&String> = r
        .model_names
        .iter()
        .filter(|m| {
            let want = format!("{}.yft", m.to_ascii_lowercase());
            !r.yft_files.iter().any(|y| base_name(y).to_ascii_lowercase() == want)
        })
        .collect();
    if let Some(m) = missing_yft.first() {
        return format!("model {m} has no .yft in the pack — it cannot stream");
    }
    if !r.model_names.iter().any(|m| m.eq_ignore_ascii_case(&r.mod_name)) {
        return format!(
            "pack looks complete — but the model is named '{}', not '{}'. Spawn with: car {}",
            r.model_names[0], r.mod_name, r.model_names[0]
        );
    }
    format!("pack looks complete — model '{}' is declared, enabled, and has its .yft", r.model_names[0])
}

fn inspect_inner(path: &Path, report: &mut RpfReport) -> Result<(), String> {
    let mut file = File::open(path).map_err(|e| format!("cannot open dlc.rpf: {e}"))?;
    let len = file.metadata().map_err(|e| format!("cannot stat dlc.rpf: {e}"))?.len();
    if len < 16 {
        return Err("file is too small to be an RPF".to_string());
    }
    if len > MAX_FILE {
        return Err("file is implausibly large".to_string());
    }
    let head = read_at(&mut file, 0, 16)?;
    let version = u32le(&head, 0);
    // Two byte orders appear in references for the same constant;
    // accept either, and report the raw magic either way.
    if version != RPF7_A && version != RPF7_B {
        return Err(format!("not an RPF7 archive (magic {:02x} {:02x} {:02x} {:02x})", head[0], head[1], head[2], head[3]));
    }
    report.version = "RPF7".to_string();
    let entry_count = u32le(&head, 4);
    let names_len = u32le(&head, 8) & 0x0FFF_FFFF;
    let encryption = u32le(&head, 12);
    report.entry_count = entry_count;
    report.encryption = match encryption {
        ENC_NONE => "NONE".to_string(),
        ENC_OPEN => "OPEN".to_string(),
        ENC_AES => "AES".to_string(),
        ENC_NG => "NG".to_string(),
        other => format!("unknown 0x{other:08x}"),
    };
    if entry_count == 0 || entry_count > MAX_ENTRIES {
        return Err(format!("implausible entry count: {entry_count}"));
    }
    if names_len > MAX_NAMES {
        return Err(format!("implausible names length: {names_len}"));
    }
    if encryption == ENC_AES || encryption == ENC_NG {
        report.encrypted_toc = true;
        return Ok(());
    }
    if encryption != ENC_NONE && encryption != ENC_OPEN {
        return Err(format!("unknown encryption tag 0x{encryption:08x}"));
    }
    let toc_len = entry_count as usize * 16;
    let toc_off = 16u64;
    let names_off = toc_off + toc_len as u64;
    let data_start = align_up(names_off + names_len as u64, BLOCK);
    if data_start > len {
        return Err("header runs past the end of the file".to_string());
    }
    let toc = read_at(&mut file, toc_off, toc_len)?;
    let names = read_at(&mut file, names_off, names_len as usize)?;
    let mut raw = Vec::with_capacity(entry_count as usize);
    for i in 0..entry_count as usize {
        let o = i * 16;
        raw.push(RawEntry { b0: u32le(&toc, o), b1: u32le(&toc, o + 4), b2: u32le(&toc, o + 8), b3: u32le(&toc, o + 12) });
    }
    if raw[0].b1 != DIR_MARKER {
        return Err("first TOC entry is not the root directory".to_string());
    }
    let mut files: Vec<Entry> = Vec::new();
    let mut dirs = 0usize;
    walk(&raw, &names, raw[0].b2 as usize, raw[0].b3 as usize, "", 0, &mut files, &mut dirs)?;
    report.file_count = files.len();
    report.dir_count = dirs;
    report.yft_files = files
        .iter()
        .filter(|e| e.path.to_ascii_lowercase().ends_with(".yft"))
        .map(|e| e.path.clone())
        .collect();
    if let Some(e) = find(&files, "setup2.xml") {
        report.setup2 = true;
        match extract(&mut file, data_start, e) {
            Ok(bytes) => match as_xml(bytes) {
                Some(text) => {
                    report.setup2_device = xml_tags(&text, "deviceName").into_iter().next().unwrap_or_default();
                    report.setup2_type = xml_tags(&text, "type").into_iter().next().unwrap_or_default();
                }
                None => report.notes.push("setup2.xml did not decompress to XML — TOC offsets may not line up".to_string()),
            },
            Err(e) => report.notes.push(format!("setup2.xml could not be extracted: {e}")),
        }
    }
    let mut content_text = String::new();
    if let Some(e) = find(&files, "content.xml") {
        report.content = true;
        match extract(&mut file, data_start, e) {
            Ok(bytes) => match as_xml(bytes) {
                Some(text) => content_text = text,
                None => report.notes.push("content.xml did not decompress to XML — TOC offsets may not line up".to_string()),
            },
            Err(e) => report.notes.push(format!("content.xml could not be extracted: {e}")),
        }
    }
    if let Some(e) = find(&files, "vehicles.meta") {
        report.vehicles_meta = Some(e.path.clone());
        match extract(&mut file, data_start, e) {
            Ok(bytes) => match as_xml(bytes) {
                Some(text) => report.model_names = xml_tags(&text, "modelName"),
                None => report.notes.push("vehicles.meta did not decompress to XML — TOC offsets may not line up".to_string()),
            },
            Err(e) => report.notes.push(format!("vehicles.meta could not be extracted: {e}")),
        }
    }
    if report.content && !content_text.is_empty() {
        let pairs = data_file_pairs(&content_text);
        for (name, ftype) in &pairs {
            let norm = name.replace("%PLATFORM%", "x64").to_ascii_lowercase();
            if norm == "common/data/vehicles.meta" || norm.ends_with("/vehicles.meta") || norm == "vehicles.meta" {
                report.meta_in_data_files = true;
                report.meta_file_type = ftype.clone();
                break;
            }
        }
        for (set, items) in changeset_enables(&content_text) {
            let enables = items.iter().any(|it| {
                let norm = it.replace("%PLATFORM%", "x64").to_ascii_lowercase();
                norm == "common/data/vehicles.meta" || norm.ends_with("/vehicles.meta") || norm == "vehicles.meta"
            });
            if enables {
                report.meta_enabled_by.push(set);
            }
        }
    }
    Ok(())
}
