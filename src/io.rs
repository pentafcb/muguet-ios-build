// muguet - io.rs
// Constantin Clerc (c22dev) - 0.1

use crate::mem_base_len;
use std::collections::HashMap;
use std::fs::File;
use std::os::unix::fs::FileExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::time::Duration;
use wasmtime::SharedMemory;

static STARTED: AtomicBool = AtomicBool::new(false);
const MAX_OPEN: usize = 1024;
// The guest I/O table is a header plus one 64-byte slot per request.
const TABLE_HEADER: u64 = 64;
const SLOT_SIZE: u64 = 64;
const MAX_SLOTS: u64 = 4096;

pub fn data_dir() -> PathBuf {
    PathBuf::from(std::env::var("MUGUET_DATA").unwrap_or_default())
}

fn manifest_files() -> Result<Vec<(String, u64)>, String> {
    crate::game_data::runtime_files(&data_dir()).map_err(|e| format!("{e:#}"))
}

// Checked guest-memory access: the table address and every slot offset
// come from the game, so an out-of-range or unaligned address must
// return None instead of asserting (an assert here used to panic the
// only I/O thread and stop all native file I/O forever).
fn atomic_i32(mem: &SharedMemory, addr: u64) -> Option<&AtomicI32> {
    let (base, len) = mem_base_len(mem);
    let a = addr as usize;
    if addr % 4 != 0 { return None; }
    if a.checked_add(4).is_none_or(|e| e > len) { return None; }
    Some(unsafe { &*(base.add(a) as *const AtomicI32) })
}

pub fn start(mem: &SharedMemory, table: u64) {
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    let mem = mem.clone();
    match std::thread::Builder::new().name("io".into()).spawn(move || {
        serve_loop(mem, table);
        // The I/O thread exited (manifest failure or a bad table). Clear
        // STARTED so a later start() can retry instead of the game
        // hanging on atomic_wait32 forever with no I/O.
        STARTED.store(false, Ordering::SeqCst);
        eprintln!("[io] native I/O thread stopped; it can be restarted");
    }) {
        Ok(_) => eprintln!("[io] native I/O thread started (table=0x{table:x})"),
        Err(e) => {
            STARTED.store(false, Ordering::SeqCst);
            eprintln!("[io] cannot spawn I/O thread: {e}");
        }
    }
}

fn serve_loop(mem: SharedMemory, table: u64) {
    // A manifest that was valid at validation time can still be gone by
    // now (import, user in Files, disk error). Return an error instead
    // of expect()ing and panicking this thread before serving a read.
    let files = match manifest_files() {
        Ok(f) => f,
        Err(e) => {
            eprintln!("[io] cannot load runtime manifest: {e}; I/O thread exiting");
            return;
        }
    };
    let root = data_dir();
    let mut handles: HashMap<i32, File> = HashMap::new();
    let mut served: u64 = 0;
    let mut bytes: u64 = 0;
    loop {
        let Some(seen_cell) = atomic_i32(&mem, table) else { break };
        let seen = seen_cell.load(Ordering::SeqCst);
        let Some(n_cell) = atomic_i32(&mem, table.checked_add(4).unwrap_or(u64::MAX)) else { break };
        // The slot count is guest-written: cap it and validate the whole
        // table fits in wasm memory before scanning, or one corrupt count
        // makes this thread iterate millions of slots per wakeup.
        let n = (n_cell.load(Ordering::SeqCst).max(0) as u64).min(MAX_SLOTS);
        let table_end = table.checked_add(TABLE_HEADER)
            .and_then(|t| t.checked_add(n.checked_mul(SLOT_SIZE)?));
        if table_end.is_none_or(|e| e as usize > mem.data_size()) {
            let _ = mem.atomic_wait32(table, seen as u32, Some(Duration::from_millis(20)));
            continue;
        }
        for slot in 0..n {
            let Some(w) = table.checked_add(TABLE_HEADER)
                .and_then(|t| t.checked_add(slot.checked_mul(SLOT_SIZE)?)) else { break };
            let Some(state) = atomic_i32(&mem, w) else { continue };
            if state.compare_exchange(1, 3, Ordering::SeqCst, Ordering::SeqCst).is_err() {
                continue;
            }
            let word = |k: u64| -> u64 {
                match w.checked_add(4 * k).and_then(|a| atomic_i32(&mem, a)) {
                    Some(c) => c.load(Ordering::SeqCst) as u32 as u64,
                    None => 0,
                }
            };
            let complete = |mem: &SharedMemory, w: u64, result: i64| {
                if let Some(c) = atomic_i32(mem, w.checked_add(28).unwrap_or(u64::MAX)) {
                    c.store(result as i32, Ordering::SeqCst);
                }
                if let Some(c) = atomic_i32(mem, w) {
                    c.store(2, Ordering::SeqCst);
                }
                let _ = mem.atomic_notify(w, 1);
            };
            let id = word(1) as i32;
            let off = word(2) | (word(3) << 32);
            let dst = word(4) | (word(5) << 32);
            let mut len = word(6);
            let result: i64 = match files.get(id as usize) {
                None => -1,
                Some((path, size)) => {
                    if off >= *size {
                        0
                    } else {
                        len = len.min(size - off);

                        if !handles.contains_key(&id) {
                            if handles.len() >= MAX_OPEN {
                                // Evict a few handles instead of dropping
                                // all 1024 at once, which thrashed when
                                // the game cycled more than MAX_OPEN assets.
                                let evict: Vec<i32> = handles.keys().take(16).copied().collect();
                                for k in evict { handles.remove(&k); }
                            }
                            match File::open(root.join(path)) {
                                Ok(f) => { handles.insert(id, f); }
                                Err(e) => eprintln!("[io] open {path}: {e}"),
                            }
                        }
                        let (base, mlen) = mem_base_len(&mem);
                        let Some(f) = handles.get(&id) else {
                            complete(&mem, w, -1);
                            continue;
                        };
                        // checked_add: a guest dst+len near u64::MAX used
                        // to wrap past the bounds check.
                        let end = dst.checked_add(len);
                        if end.is_none_or(|e| e as usize > mlen) {
                            -1
                        } else {
                            // Read in a loop and return the bytes actually
                            // read: a short file used to fail the whole
                            // request with -1 instead of the bytes present.
                            let buf = unsafe { std::slice::from_raw_parts_mut(base.add(dst as usize), len as usize) };
                            let mut got = 0usize;
                            let mut ok = true;
                            while got < len as usize {
                                match f.read_at(&mut buf[got..], off + got as u64) {
                                    Ok(0) => break,
                                    Ok(n) => got += n,
                                    Err(e) => { eprintln!("[io] read {path}@{off}+{len}: {e}"); ok = false; break; }
                                }
                            }
                            if ok { got as i64 } else { -1 }
                        }
                    }
                }
            };
            served += 1;
            if result > 0 { bytes += result as u64; }
            if served % 2000 == 0 {
                eprintln!("[io] {served} reads, {} MB", bytes >> 20);
            }
            complete(&mem, w, result);
        }

        let _ = mem.atomic_wait32(table, seen as u32, Some(Duration::from_millis(20)));
    }
}
