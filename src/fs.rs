// muguet - fs.rs
// Constantin Clerc (c22dev) - 0.1

use crate::{read_bytes, read_cstr, read_u64, write_bytes, write_u64};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::fs::{FileExt, MetadataExt};
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, LazyLock, Mutex};
use wasmtime::{SharedMemory, Val};

const EBADF: i64 = 8;
const EEXIST: i64 = 20;
const EINVAL: i64 = 28;
const EISDIR: i64 = 31;
const ENOENT: i64 = 44;
const ENOSYS: i64 = 52;
const ENOTDIR: i64 = 54;
const ENOTEMPTY: i64 = 55;
const ENOTTY: i64 = 59;

const O_ACCMODE: i64 = 3;
const O_CREAT: i64 = 64;
const O_EXCL: i64 = 128;
const O_TRUNC: i64 = 512;
const O_APPEND: i64 = 1024;
const O_DIRECTORY: i64 = 65536;
const AT_FDCWD: i64 = -100;

const S_IFCHR: u32 = 0o020000;
const S_IFDIR: u32 = 0o040000;
const S_IFREG: u32 = 0o100000;

enum Entry {
    File { file: File },
    Dir { guest: String, names: Option<Vec<(String, u8)>>, pos: u64 },
}

struct Fs {
    root: PathBuf,
    fds: HashMap<i64, Entry>,
    next_fd: i64,
    // Freed fd numbers, reused before allocating a new one so the guest
    // fd space stays bounded instead of growing forever (see alloc_fd).
    free_fds: Vec<i64>,
}

static FS: LazyLock<Mutex<Fs>> = LazyLock::new(|| {
    let root = std::env::var("MUGUET_FSROOT").unwrap_or_else(|_| "fsroot".into());
    let root = PathBuf::from(root);
    for d in ["tmp", "home/web_user", "dev", "proc/self"] {
        if let Err(e) = fs::create_dir_all(root.join(d)) {
            eprintln!("[fs] cannot create {}: {e}", root.join(d).display());
        }
    }
    Mutex::new(Fs { root, fds: HashMap::new(), next_fd: 3, free_fds: Vec::new() })
});

// Guest fd allocation: reuse a freed number first, cap the table at 1024
// open entries, and evict one arbitrary file entry (logged) instead of
// growing until the process RLIMIT_NOFILE is hit and every open fails.
const MAX_FDS: usize = 1024;
fn alloc_fd(fs: &mut Fs) -> i64 {
    if let Some(fd) = fs.free_fds.pop() {
        return fd;
    }
    if fs.fds.len() >= MAX_FDS {
        if let Some((&fd, _)) = fs.fds.iter().find(|(_, e)| matches!(e, Entry::File { .. })) {
            eprintln!("[fs] fd table full ({}); evicting fd {fd}", fs.fds.len());
            fs.fds.remove(&fd);
            return fd;
        }
    }
    let fd = fs.next_fd;
    fs.next_fd += 1;
    fd
}

fn guest_abs(fs: &Fs, dirfd: i64, path: &str) -> Result<String, i64> {
    let base = if path.starts_with('/') || dirfd == AT_FDCWD {
        "/".to_string()
    } else {
        match fs.fds.get(&dirfd) {
            Some(Entry::Dir { guest, .. }) => guest.clone(),
            Some(_) => return Err(ENOTDIR),
            None => return Err(EBADF),
        }
    };
    let mut parts: Vec<String> = Vec::new();
    for c in Path::new(&base).join(path).components() {
        match c {
            Component::Normal(s) => parts.push(s.to_string_lossy().into_owned()),
            Component::ParentDir => { parts.pop(); }
            _ => {}
        }
    }
    Ok(format!("/{}", parts.join("/")))
}

fn host_path(fs: &Fs, guest: &str) -> PathBuf {
    fs.root.join(guest.trim_start_matches('/'))
}

fn write_stat(mem: &SharedMemory, buf: u64, md: &fs::Metadata, chr: bool) {
    let mode = if chr { S_IFCHR | 0o666 } else if md.is_dir() { S_IFDIR | 0o777 } else { S_IFREG | 0o666 };
    let mut b = [0u8; 112];
    let put32 = |b: &mut [u8], o: usize, v: u32| b[o..o + 4].copy_from_slice(&v.to_le_bytes());
    let put64 = |b: &mut [u8], o: usize, v: u64| b[o..o + 8].copy_from_slice(&v.to_le_bytes());
    put32(&mut b, 0, 1);
    put32(&mut b, 4, mode);
    put64(&mut b, 8, 1);
    put64(&mut b, 32, md.len());
    put32(&mut b, 40, 4096);
    put32(&mut b, 44, md.len().div_ceil(512) as u32);
    for (o, s) in [(48, md.atime()), (64, md.mtime()), (80, md.ctime())] {
        put64(&mut b, o, s as u64);
    }
    put64(&mut b, 96, md.ino());
    write_bytes(mem, buf, &b);
}

fn ok_i(results: &mut [Val], v: i64) {
    // An empty results slice used to drop the return value silently; a
    // value that does not fit in i32 used to truncate with `as`. Clamp
    // instead, and never write past the slice.
    if let Some(r) = results.get_mut(0) {
        *r = match r {
            Val::I64(_) => Val::I64(v),
            _ => Val::I32(v.clamp(i32::MIN as i64, i32::MAX as i64) as i32),
        };
    }
}

// The iovec count comes straight from the wasm guest: cap it, or a
// corrupt n tries to allocate an unbounded Vec and aborts the process.
// Addresses are computed with checked arithmetic so a wrapped iovs+k*16
// reads (0, 0) instead of the wrong memory.
fn iovecs(mem: &SharedMemory, iovs: u64, n: u64) -> Vec<(u64, u64)> {
    const IOV_MAX: u64 = 1024;
    let n = n.min(IOV_MAX);
    (0..n).map(|k| {
        let base = iovs.checked_add(k.checked_mul(16).unwrap_or(u64::MAX)).unwrap_or(u64::MAX);
        let ptr = read_u64(mem, base).unwrap_or(0);
        let len = read_u64(mem, base.checked_add(8).unwrap_or(u64::MAX)).unwrap_or(0);
        (ptr, len)
    }).collect()
}

fn read_dir_names(host: &Path) -> Vec<(String, u8)> {
    let mut v = vec![(".".to_string(), 4u8), ("..".to_string(), 4u8)];
    if let Ok(rd) = fs::read_dir(host) {
        for e in rd.flatten() {
            let t = if e.file_type().map(|t| t.is_dir()).unwrap_or(false) { 4 } else { 8 };
            v.push((e.file_name().to_string_lossy().into_owned(), t));
        }
    }
    v
}

pub fn handle(name: &str, mem: &SharedMemory, p: &[Val], results: &mut [Val]) -> bool {
    let a = |i: usize| -> i64 { match p.get(i) { Some(Val::I32(x)) => *x as i64, Some(Val::I64(x)) => *x, _ => 0 } };
    // Poison tolerance: a thread that panicked while holding FS used to
    // make every later guest syscall panic on lock().unwrap().
    // Note: the lock is still held across the whole syscall below (the
    // table itself is the shared state); the I/O itself is short file
    // reads/writes, and dropping it mid-syscall would need the entry
    // taken out of the table first — a follow-up, not done here.
    let mut fs = FS.lock().unwrap_or_else(|e| e.into_inner());
    let r: i64 = match name {
        "__syscall_openat" => (|| {
            let flags = a(2);
            let mode_creat = flags & O_CREAT != 0;
            let guest = guest_abs(&fs, a(0), &read_cstr(mem, a(1) as u64)).map_err(|e| -e)?;
            let host = host_path(&fs, &guest);
            let exists = host.exists();
            if exists && mode_creat && flags & O_EXCL != 0 { return Err(-EEXIST); }
            if host.is_dir() {
                if flags & O_ACCMODE != 0 { return Err(-EISDIR); }
                let fd = alloc_fd(&mut fs);
                fs.fds.insert(fd, Entry::Dir { guest, names: None, pos: 0 });
                return Ok(fd);
            }
            if flags & O_DIRECTORY != 0 { return Err(if exists { -ENOTDIR } else { -ENOENT }); }
            if !exists && !mode_creat { return Err(-ENOENT); }
            if mode_creat {
                if let Some(parent) = host.parent() {
                    let _ = fs::create_dir_all(parent);
                }
            }
            let acc = flags & O_ACCMODE;
            let file = OpenOptions::new()
                .read(acc == 0 || acc == 2)
                .write(acc == 1 || acc == 2)
                .append(flags & O_APPEND != 0)
                .create(mode_creat)
                .truncate(flags & O_TRUNC != 0)
                .open(&host)
                .map_err(|e| {
                    // Every OS error used to become -ENOENT, so a full
                    // disk, a permission error and a missing file all
                    // looked identical to the game. Log the real error;
                    // the -ENOENT fallback is kept because the exact
                    // emscripten errno numbers for EACCES/ENOSPC/EMFILE
                    // are not verified in this codebase — do not guess.
                    eprintln!("[fs] open {} failed: {e}", host.display());
                    -ENOENT
                })?;
            let fd = alloc_fd(&mut fs);
            fs.fds.insert(fd, Entry::File { file });
            Ok(fd)
        })().unwrap_or_else(|e| e),
        "__syscall_stat64" | "__syscall_lstat64" | "__syscall_newfstatat" => {
            let (dirfd, path, buf) = if name == "__syscall_newfstatat" { (a(0), a(1), a(2)) } else { (AT_FDCWD, a(0), a(1)) };
            match guest_abs(&fs, dirfd, &read_cstr(mem, path as u64)) {
                Ok(g) => match fs::metadata(host_path(&fs, &g)) {
                    Ok(md) => { write_stat(mem, buf as u64, &md, g.starts_with("/dev/")); 0 }
                    Err(_) => -ENOENT,
                },
                Err(e) => -e,
            }
        }
        "__syscall_fstat64" => {
            let fd = a(0);
            if fd <= 2 {
                // /dev/null metadata used to be unwrap()ed: a panic here
                // unwinds through wasmtime for an ordinary fstat.
                match fs::metadata("/dev/null") {
                    Ok(md) => { write_stat(mem, a(1) as u64, &md, true); 0 }
                    Err(_) => -EBADF,
                }
            } else {
                match fs.fds.get(&fd) {
                    Some(Entry::File { file, .. }) => match file.metadata() { Ok(md) => { write_stat(mem, a(1) as u64, &md, false); 0 } Err(_) => -EBADF },
                    Some(Entry::Dir { guest, .. }) => match fs::metadata(host_path(&fs, guest)) {
                        Ok(md) => { write_stat(mem, a(1) as u64, &md, false); 0 }
                        Err(_) => -EBADF,
                    },
                    None => -EBADF,
                }
            }
        }
        "__syscall_mkdirat" => match guest_abs(&fs, a(0), &read_cstr(mem, a(1) as u64)) {
            Ok(g) => { let h = host_path(&fs, &g); if h.exists() { -EEXIST } else if fs::create_dir_all(&h).is_ok() { 0 } else { -ENOENT } }
            Err(e) => -e,
        },
        "__syscall_unlinkat" => match guest_abs(&fs, a(0), &read_cstr(mem, a(1) as u64)) {
            Ok(g) => {
                let h = host_path(&fs, &g);
                let res = if a(2) & 0x200 != 0 { fs::remove_dir(&h) } else { fs::remove_file(&h) };
                if res.is_ok() { 0 } else if !h.exists() { -ENOENT } else { -ENOTEMPTY }
            }
            Err(e) => -e,
        },
        "__syscall_rmdir" => match guest_abs(&fs, AT_FDCWD, &read_cstr(mem, a(0) as u64)) {
            Ok(g) => { let h = host_path(&fs, &g); if fs::remove_dir(&h).is_ok() { 0 } else if !h.exists() { -ENOENT } else { -ENOTEMPTY } }
            Err(e) => -e,
        },
        "__syscall_renameat" => {
            let from = guest_abs(&fs, a(0), &read_cstr(mem, a(1) as u64));
            let to = guest_abs(&fs, a(2), &read_cstr(mem, a(3) as u64));
            match (from, to) {
                (Ok(f), Ok(t)) => {
                    let tf = host_path(&fs, &t);
                    if let Some(p) = tf.parent() { let _ = fs::create_dir_all(p); }
                    if fs::rename(host_path(&fs, &f), &tf).is_ok() { 0 } else { -ENOENT }
                }
                (Err(e), _) | (_, Err(e)) => -e,
            }
        }
        "__syscall_ftruncate64" => match fs.fds.get(&a(0)) {
            Some(Entry::File { file, .. }) => if file.set_len(a(1) as u64).is_ok() { 0 } else { -EINVAL },
            _ => -EBADF,
        },
        "__syscall_getcwd" => {
            let (buf, size) = (a(0) as u64, a(1) as u64);
            if size < 2 { -EINVAL } else { write_bytes(mem, buf, b"/\0"); 2 }
        }
        "__syscall_getdents64" => {
            let (fd, dirp, count) = (a(0), a(1) as u64, a(2) as u64);
            let root = fs.root.clone();
            match fs.fds.get_mut(&fd) {
                Some(Entry::Dir { guest, names, pos }) => {
                    let names = names.get_or_insert_with(|| read_dir_names(&root.join(guest.trim_start_matches('/'))));
                    let start = (*pos / 280) as usize;
                    // A buffer smaller than one 280-byte record used to
                    // return 0 entries with pos never advancing, so the
                    // game's readdir loop spun forever. That is EINVAL,
                    // not "end of directory".
                    if count < 280 && start < names.len() {
                        EINVAL
                    } else {
                        let end = names.len().min(start + (count / 280) as usize);
                        let mut off = 0u64;
                        for (idx, (n, t)) in names.iter().enumerate().take(end).skip(start) {
                            let mut rec = [0u8; 280];
                            rec[0..8].copy_from_slice(&((idx as u64) + 1).to_le_bytes());
                            rec[8..16].copy_from_slice(&(((idx + 1) * 280) as u64).to_le_bytes());
                            rec[16..18].copy_from_slice(&280u16.to_le_bytes());
                            rec[18] = *t;
                            let nb = n.as_bytes();
                            let l = nb.len().min(255);
                            rec[19..19 + l].copy_from_slice(&nb[..l]);
                            // A failed write used to be ignored while off
                            // still advanced, so the guest read stale
                            // memory believing bytes were written.
                            if !write_bytes(mem, dirp + off, &rec) { break; }
                            off += 280;
                        }
                        *pos = (start as u64 + off / 280) * 280;
                        off as i64
                    }
                }
                Some(_) => -ENOTDIR,
                None => -EBADF,
            }
        }
        "__syscall_fcntl64" => if a(0) <= 2 || fs.fds.contains_key(&a(0)) { 0 } else { -EBADF },
        "__syscall_ioctl" => -ENOTTY,
        "__syscall_statfs64" => { write_bytes(mem, a(2) as u64, &statfs()); 0 }

        "__syscall_socket" | "__syscall_connect" | "__syscall_accept4" | "__syscall_sendto"
        | "__syscall_recvfrom" | "__syscall_setsockopt" | "__syscall_getsockopt"
        | "__syscall_getsockname" | "__syscall_shutdown" | "__syscall_poll" => -ENOSYS,

        "fd_read" | "fd_pread" => {
            let fd = a(0);
            let iov = iovecs(mem, a(1) as u64, a(2) as u64);
            let (offset, nread_ptr) = if name == "fd_pread" { (Some(a(3) as u64), a(4) as u64) } else { (None, a(3) as u64) };
            match fs.fds.get_mut(&fd) {
                Some(Entry::File { file, .. }) => {
                    let mut total = 0u64;
                    let mut off = offset;
                    for (ptr, len) in iov {
                        // A single iovec used to allocate its full guest
                        // length up front (gigabytes on a corrupt len).
                        // Read in 1 MiB chunks with a reused buffer.
                        let mut remaining = len;
                        let mut cur_ptr = ptr;
                        let mut cur_off = off;
                        let mut buf = vec![0u8; 1 << 20];
                        let mut failed = false;
                        while remaining > 0 {
                            let chunk = remaining.min(1 << 20) as usize;
                            let n = match cur_off {
                                Some(o) => file.read_at(&mut buf[..chunk], o),
                                None => file.read(&mut buf[..chunk]),
                            };
                            let n = match n {
                                Ok(n) => n,
                                Err(e) => {
                                    // Read errors used to be swallowed to
                                    // 0, so a disk error looked like a
                                    // clean EOF. Log it and stop.
                                    eprintln!("[fs] fd_read failed: {e}");
                                    failed = true;
                                    break;
                                }
                            };
                            if n == 0 { break; }
                            write_bytes(mem, cur_ptr, &buf[..n]);
                            total += n as u64;
                            cur_ptr += n as u64;
                            remaining -= n as u64;
                            if let Some(o) = cur_off.as_mut() { *o += n as u64; }
                            if (n as u64) < chunk as u64 { break; }
                        }
                        off = cur_off;
                        if failed || remaining > 0 { break; }
                    }
                    write_u64(mem, nread_ptr, total);
                    0
                }
                Some(Entry::Dir { .. }) => EISDIR,
                None if fd == 0 => { write_u64(mem, nread_ptr, 0); 0 }
                None => EBADF,
            }
        }
        "fd_write" | "fd_pwrite" if a(0) > 2 => {
            let fd = a(0);
            let iov = iovecs(mem, a(1) as u64, a(2) as u64);
            let (offset, nw_ptr) = if name == "fd_pwrite" { (Some(a(3) as u64), a(4) as u64) } else { (None, a(3) as u64) };
            match fs.fds.get_mut(&fd) {
                Some(Entry::File { file, .. }) => {
                    let mut total = 0u64;
                    let mut off = offset;
                    for (ptr, len) in iov {
                        let data = read_bytes(mem, ptr, len);
                        let ok = match off { Some(o) => file.write_all_at(&data, o).is_ok(), None => file.write_all(&data).is_ok() };
                        if !ok { break; }
                        total += len;
                        if let Some(o) = off.as_mut() { *o += len; }
                    }
                    write_u64(mem, nw_ptr, total);
                    0
                }
                _ => EBADF,
            }
        }
        "fd_seek" => {
            let (fd, offset, whence, out) = (a(0), a(1), a(2), a(3) as u64);
            match fs.fds.get_mut(&fd) {
                Some(Entry::File { file, .. }) => {
                    let sf = match whence { 0 => SeekFrom::Start(offset as u64), 1 => SeekFrom::Current(offset), 2 => SeekFrom::End(offset), _ => return { ok_i(results, EINVAL); true } };
                    match file.seek(sf) { Ok(p) => { write_u64(mem, out, p); 0 } Err(_) => EINVAL }
                }
                Some(Entry::Dir { pos, .. }) => { if whence == 0 { *pos = offset as u64; } write_u64(mem, out, *pos); 0 }
                None => EBADF,
            }
        }
        "fd_close" => if fs.fds.remove(&a(0)).is_some() || a(0) <= 2 {
            // Freed numbers are reused by alloc_fd so the guest fd
            // space stays bounded instead of growing forever.
            if a(0) > 2 { fs.free_fds.push(a(0)); }
            0
        } else { EBADF },
        _ => return false,
    };
    drop(fs);
    ok_i(results, r);
    true
}

pub fn httpfs_manifest(mem: &SharedMemory, p: &[Val], results: &mut [Val]) {
    static MANIFEST: LazyLock<Option<Arc<[u8]>>> = LazyLock::new(|| {
        let dir = std::env::var("MUGUET_DATA").unwrap_or_default();
        crate::game_data::runtime_manifest(Path::new(&dir)).ok()
    });
    let a = |i: usize| -> i64 { match p.get(i) { Some(Val::I32(x)) => *x as i64, Some(Val::I64(x)) => *x, _ => 0 } };
    let r = match MANIFEST.as_ref() {
        None => -1,
        Some(bytes) => {
            if a(1) as usize > bytes.len() {
                write_bytes(mem, a(0) as u64, bytes);
                write_bytes(mem, a(0) as u64 + bytes.len() as u64, &[0]);
            }
            bytes.len() as i64
        }
    };
    ok_i(results, r);
}

fn statfs() -> [u8; 88] {
    let mut b = [0u8; 88];
    let blocks: u64 = 16 << 20;
    b[8..12].copy_from_slice(&4096u32.to_le_bytes());
    b[72..76].copy_from_slice(&4096u32.to_le_bytes());
    for (off, v) in [(16, blocks), (24, blocks), (32, blocks), (40, 1 << 20), (48, 1 << 20)] {
        b[off..off + 8].copy_from_slice(&(v as u64).to_le_bytes());
    }
    b[64..68].copy_from_slice(&255u32.to_le_bytes());
    b
}
