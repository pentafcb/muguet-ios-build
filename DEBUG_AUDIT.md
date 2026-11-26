# Muguet debug audit — crash 2–3 minutes into a single session, gamepad camera, file picker

Repo: `pentafcb/muguet-ios-build` (fork of `iOSVNNews/muguet-ios-build`),
head `3b4b7c69`, 2026-10-12. Date: 2026-11-26. No phone test, no IPA
build, no game files used.

## CORRECTION — the crash timing (2026-11-26 ~01:28 PST)

The first version of this audit, and pushed commit `2ed2c2c`, were built
on the wrong premise: "crash after 2–3 runs". The user corrected it in
his words: "I didn't said after 2-3 runs I said after 2-3 minutes of
playing every time like I open the game and it crashes after 2-3
minutes never played more than 5". So the crash is: **every session,
2–3 minutes into ONE play session, never surviving past 5 minutes**.
Everything in §1, §2, §3 and §7 below is rewritten to that premise.
The gamepad (§4) and file picker (§5) fixes are unaffected. This
correction is local only — NOT pushed.

## 0. Is this the latest from the original creator? No.

This is **not** the latest from the original creator. The original
`c22dev/muguet` (Constantin Clerc) was taken down by a Take-Two DMCA
notice on 2026-11-18. This repo is the `iOSVNNews/muguet-ios-build`
rebuild fork, head `3b4b7c69` from 2026-10-12. There is no newer
original to pull from — everything below is fixed in this fork.

## 1. Crash 2–3 minutes into a single session — findings

Corrected premise: the game opens, plays for 2–3 minutes, and crashes
every time, never past 5 minutes. This is a within-session kill, not a
cross-launch accumulation. A jetsam kill (iOS killing the app for
memory) fits it exactly; a Rust panic would leave a crash log, a
jetsam kill leaves none.

### 1a. What the timing implies — the growth rate

If the process starts with roughly 1.5–2.5 GB of usable headroom
(device RAM minus OS, Metal, audio and the game heap itself) and dies
at ~150 s, the footprint is growing at roughly **10–20 MB/s, i.e.
~600–1200 MB/min**. That is fast. A slow leak (a HashSet entry per
warning, a log line per frame) cannot do that. Only three things in
this codebase grow that fast: the wasm game heap (§1e #1), game-owned
GPU textures/buffers streamed in as the world loads (§1e #2), and
host-side per-frame allocations that are retained, not freed (§1e #3).

### 1b. Purge timing vs a 150 s crash — the math

`gpu.rs` `check_memory()` runs every GPU loop iteration, but it only
samples once a second, and it only asks for a purge when available
memory falls under 384 MB. The purge itself is throttled: at most one
every 15 s (now 5 s when available is under 192 MB — see §3 #7).
At ~15 MB/s, available memory falls 384 MB → 0 in ~25 s, so the old
15 s throttle allowed at most one purge in the whole crash window.
Worse, a purge only clears **host caches** (bind groups, pipelines,
compute, cached views, uniform ring). It never frees a texture or
buffer the game still owns by id, and it never shrinks the wasm heap.
So if the growth is game-owned (§1e #1–2), the purge frees almost
nothing and the footprint keeps climbing ~15 MB/s straight into
jetsam, no matter how often it runs. The purge is a mitigation for
host-cache growth, not a fix for game-side growth. The debug log's
slope (§2) is what tells which one it is: a purge that drops the
footprint shows up as a negative slope; a slope that ignores purges
means the growth is game-owned.

### 1c. No host timer fires at 2–3 minutes

Checked by grep over `src/*.rs`: there is no host timer, timeout or
counter anywhere near 120–180 s. The timers that exist are the 45 s
startup warning (only before the first frame is ever displayed),
the audio 5 s logger, multiplayer send/look/resend timers (33 ms /
1 s / 150 ms / 4 s) and a 5 s multiplayer server timeout
(`proto.rs` `TIMEOUT_SECS = 5`, multiplayer only). None of them can
cause a single-player crash at 2–3 minutes. The trigger is therefore
almost certainly game-side: the point where streaming a new area,
compiling a burst of shaders, or growing the heap past a limit
collides with the memory ceiling. Do not invent a host timer that
is not in the code.

### 1d. Correction to the first read-only audit

The first audit said `memory_warning` sets a flag with "no real purge".
That was wrong. `gpu.rs` `check_memory()` **does** purge: on
`MEMORY_PRESSURE` it flushes, waits up to 2 s for submitted work,
clears `bind_groups`, drops finished pipelines, clears `compute`,
`bgl_cache`, shader program variants and uniform slots, then logs
`memory cleanup: {before} -> {after} MB`. `prune_graphics_cache()`
also runs every 120 presents on iOS. The problem is not "no purge" —
it is that the purge fires too late, is throttled, and cannot free
game-owned memory. The fixes below target exactly that.

### 1e. Leak suspects, re-ranked for a 150 s in-session kill

| # | Location | Problem |
|---|----------|---------|
| 1 | `src/host.rs` `resize_heap()` + `src/main.rs` `heap_type()` / `src/performance.rs` `ios_heap_budget()` | **Most likely.** The wasm heap only grows, never shrinks, and is capped at `IOS_HEAP_MAX` 3072 MB (65% of physical). GTA streams the world into the heap; once it approaches the cap, `growth_fits` refuses and `resize_heap` returns false — the game then traps/aborts, or jetsam takes the process first. If the heap grows ~10 MB/s from a ~1.5 GB start, it hits the cap at ~150 s. A purge cannot help: it never shrinks the heap. **Not fixed, only instrumented** — refusals log run + GPU counts + elapsed (`src/debug.rs` `note_heap_refusal()`). Visible in the log as `heap` climbing steadily while `tex live` stays flat. |
| 2 | `src/gpu.rs` `objs: Vec<Option<Obj>>` + `create_texture()` / `create_buffer()` | **Second most likely.** The game creates texture/buffer ids as it streams new areas; the host can never free one the game still owns by id. If GTA never destroys old area textures while driving, live tex count climbs linearly with distance travelled — hundreds of MB in 2–3 min of driving. **Not directly fixable host-side** — now visible via the leak counters and the slope (§2). Visible as `tex live` climbing with `created − destroyed ≈ live`. |
| 3 | `src/gpu.rs` `uniform_alloc()` / `ubo_shared` + `pack_copy()` | Per-frame uniform data is copied into a ring; if one frame needs more than `RING_CHUNK` 8 MB, a NEW 24 MB buffer (8 MB × 3 frame slots) is allocated and retained in `ubo_shared`, plus a CPU staging `Vec` per chunk per slot (up to 8 MB each). Only freed on purge. A uniform-heavy scene can add 24 MB per chunk-growth event. Demoted vs #1–2: bounded by per-frame uniform volume, and the purge does clear it. |
| 4 | `src/gpu.rs` `stage_bind_group()` + `get_pipeline()` | **Verified per-scene, NOT per-frame.** The bind-group key is (layout, shader uid, chunk id, texture/buffer/sampler ids, offsets) — the chunk id is stable per chunk index and the uniform offset rides in `dyn_off`, not the key. New bind groups appear only for new shader/texture/state combos, i.e. new areas. Pruned every 120 presents down to `BG_LIMIT` 4096 / `PIPE_LIMIT` 4096, so it plateaus at the limit instead of growing forever. Demoted: contributes at most a plateau, not a 150 s ramp. |
| 5 | `src/gpu.rs` `upload_buffer()` / `upload_texture()` + `bc_decode()` | Every upload does `bytes().to_vec()`, and BC textures get a full decoded `Vec` (a 1024×1024 BC7 texture decodes to 4 MB) plus half/a8 conversions — per upload, per frame. These are transient (freed after `write_texture`), so they cause allocator churn and raise the peak RSS the jetsam limit is measured against, not a monotonic leak. Not fixed (would need a staging pool); the slope log shows whether the climb is steady (retained) or spiky (transient). |
| 6 | `src/gpu.rs` `set_obj()` | **Fixed** — destroys the old `Tex`/`Buf` before overwriting. Was a real leak, but one object id at a time — far too slow to kill a session in 150 s on its own. Kept as a fix, demoted as the cause. |
| 7 | `src/gpu.rs` `check_memory()` purge | **Fixed in part** — trigger 192 → 384 MB, clears cached views / `blit_bg` / `mip_passes` / `dummy_tex` / `LOGGED`, throttle now 5 s under 192 MB available. Still cannot free game-owned memory (§1b above). |
| 8 | `src/gpu.rs` `log_once()` / `LOGGED` | **Fixed** — capped at 1024 entries. Far too slow to matter at 150 s; hygiene only. |
| 9 | `src/main.rs` `load_module()` (jit) stale `.cwasm` | **Fixed** — deletes old `game-*.cwasm` files, keeping only the latest. **Demoted: this is DISK growth across game updates, once per launch at most.** The file is written once at load, before play starts. It cannot cause a crash 2–3 minutes into a session. Kept as hygiene, explicitly NOT the cause. |
| 10 | `src/main.rs` `Runtime` (`OnceLock`) + `spawn_pthread()` | Engine, module and shared memory live for the whole process; pthread `Store`+`Instance` pairs are never joined. By design, process-lifetime; cannot grow minute by minute after startup. Not a suspect. |
| 11 | `src/audio.rs` `STARTED` (once-only), stream parked forever | Process-lifetime by design. Not a suspect. |
| 12 | `src/io.rs` `serve_loop()` open-file map, `MAX_OPEN = 1024` | Bounded, but when full it closes the **whole** map at once. Suspect, not changed (needs a phone repro first). |
| 13 | `src/fs.rs` `FS` open fds | Closed only on explicit `fd_close` from the game. Game-owned; not changed. |
| 14 | `src/mp.rs` `NET` peers/shots | Capped (peers 64, snaps 20 per peer) — bounded, not a suspect. |
| 15 | `src/diagnostics.rs` | No run counter, no memory history, no GPU counts; a jetsam kill is not a Rust panic so it leaves no crash log at all. **Fixed** by the debug tools below. |

### 1f. Open questions (revised — run count is no longer relevant)

The old question — "2–3 app launches or 2–3 in-app starts?" — is
answered and dead: it is one session, 2–3 minutes in, every time.
What is still unknown, and what the next phone test must answer:
- iPhone model / RAM / iOS version (sets the headroom in the §1a math).
- Does it crash standing still in one spot, or only while driving /
  flying into new areas? Standing still rules out streaming (§1e #2);
  moving rules it in.
- Story Mode or Sandbox? (different streaming / script load).
- Freeze-then-close, or instant close to the home screen? A freeze
  first suggests the heap-refusal trap; an instant vanish suggests
  jetsam.
- The debug log from ONE session: the slope at 30 / 60 / 90 / 120 s,
  whether `heap` or `tex live` is climbing, and whether purges bend
  the slope at all.
No `muguet-runtime.log`, `muguet-previous.log` or `muguet-crash.log`
has been shared yet.

## 2. Debug tools added

New module `src/debug.rs`, gated behind `MUGUET_DEBUG=1` (off by
default). Enable it before launching — there is no in-app toggle; the
flag is read at startup.

- **Run counter** — `Documents/muguet-debug.json`:
  `{"runs": N, "prev_peak_tex": T, "prev_peak_buf": B}`. Bumped on
  every launch, even with debug off, so refusals and panics can always
  name the run number.
- **Per-run log** — `Documents/muguet-debug.log`, one line per sample:
  `sample run 3 t 90s footprint 1842 MB avail 512 MB heap 1200 MB
  slope 900 MB/min | tex live 1234 (created 5000 destroyed 3766) |
  buf live 89 (created 900 destroyed 811) | shaders 12 pipes 340 bg
  1200 draws 99999 presents 12345`. Sampled every **2 s** from
  `gpu.rs` `check_memory()` (was 5 s — a 150 s session only gives ~30
  points at 5 s) and on every iOS memory warning (`app.rs`
  `memory_warning()`). Every line carries elapsed time `t` since
  session start and the footprint slope in MB/min measured from the
  first sample (n/a before 30 s of data; negative after a purge means
  the purge freed memory). The slope, not the level, is the diagnostic:
  a steady ~600–1200 MB/min slope is a jetsam ramp; a flat slope with
  a sudden jump is a single streaming/shader burst.
- **Leak counters** — `TEX_CREATED`/`TEX_DESTROYED`,
  `BUF_CREATED`/`BUF_DESTROYED`, `SHADER_CREATED`/`SHADER_DESTROYED`
  (`src/gpu.rs`), incremented in `create_texture` / `create_buffer` /
  `create_shader` / `destroy()`. Logged every 10 s by `log_fps()` as
  `leak watch: textures live … (created … destroyed …)`. If live
  textures/buffers exceed the previous run's peak, the debug log gets
  one `LEAK WATCH: … exceed previous run peak …` line per run.
- **Panic hook** — `src/diagnostics.rs` now dumps the snapshot
  (`run | t | footprint | avail | heap | tex buf shaders pipes bg
  draws presents`) into `muguet-crash.log` and stderr. Note: a jetsam
  kill still leaves no crash log — that is why the 2 s samples matter.
- **Heap refusals** — `src/host.rs` `resize_heap()` logs run number +
  GPU counts via `debug::snapshot_text()` / `note_heap_refusal()`.
- **Snapshot function** — `debug::snapshot_text()` is callable from
  `app.rs` `memory_warning()` and `gpu.rs` `check_memory()`; the last
  sampled GPU counts are kept in memory so a warning/panic can report
  them even when debug logging is off.
- **Swift bridge** — `muguet_debug_log()` (Rust `#[no_mangle]`, declared
  in `ios/Launcher.swift`) lets Swift log picker cancel/errors to
  `muguet-runtime.log` and, when enabled, `muguet-debug.log`.
- **Diagnostics share** — the launcher "Share startup / memory logs"
  button now also includes `muguet-debug.log`.

## 3. Leak fixes applied

1. `src/gpu.rs` `set_obj()` destroys the previous `Tex`/`Buf` via the
   existing `destroy()` before overwriting.
2. `src/gpu.rs` `check_memory()` purge trigger 192 MB → **384 MB**,
   with a 30 s / 30 FPS limit after each purge. Throttle is 15 s
   normally, 5 s when available is under 192 MB (see #7).
3. `src/gpu.rs` `check_memory()` purge now also clears cached texture
   views, `blit_bg`, `mip_passes`, `dummy_tex`, and `LOGGED`, and logs
   how many bind groups / pipelines / views were cleared.
4. `src/gpu.rs` `log_once()` `LOGGED` set capped at 1024 entries.
5. `src/main.rs` `load_module()` deletes stale `game-*.cwasm` files,
   keeping only the latest. Hygiene only — **demoted**: disk growth
   across game updates cannot cause a crash 2–3 minutes into a
   session (§1e #9).
6. `src/host.rs` heap-growth refusals log run number + GPU counts.
7. `src/gpu.rs` `check_memory()` purge throttle: still 15 s normally,
   but 5 s when available memory is under 192 MB, with a `critical
   purge` log line. A purge only clears host caches, so this buys
   time — it does not fix game-owned growth (§1b).

Not changed on purpose: game logic, multiplayer, shaders, input
handling (except the pad fix in §4), audio, `fs.rs`/`io.rs` (bounded
suspects, need a phone repro first).

## 4. Gamepad camera sensitivity — investigation + fix

Controller: BKELHS Bluetooth Mobile Game Controller (normal BT
controller, no special case needed).

### 4a. Does the in-game "max" setting reach pad.rs? No.

The pad path never reads any game setting. Chain before the fix
(`src/pad.rs` → `src/aim.rs` `scale_delta()` → `src/input.rs`
`mouse_delta_f()`):

- `LOOK_SPEED = 700` (hardcoded), deadzone 0.12, curve `powf(1.8)`.
- Per poll: `dx = curve * 700 * dt`, then `scale_delta(..., 1.0, …)`,
  then `× MUGUET_MOUSE_SENS` (config `mouse_sensitivity`, default
  2.0 — the only sensitivity that ever reached the pad, and the iOS
  launcher has no slider for it).
- The game's own in-game sensitivity slider lives in the game's
  `settings.xml`; the host never reads it. The pad feeds the same
  DX/DY words as mouse/touch look, so if the game scales DX/DY by its
  slider it scales the pad too — but it multiplies a host base rate
  that is far too low. Whether the game scales DX/DY could not be
  verified here (no game files); the fix raises the host rate and adds
  a dedicated control, so it works either way.

### 4b. Measured effective speed (before fix)

Full stick, not aiming, `MUGUET_MOUSE_SENS` = 2.0:

| Poll rate | Per-poll accel | Sustained rate |
|---|---|---|
| 30 Hz | 2.50 (capped) | ~3500 px/s |
| 60 Hz | 2.17 | ~3034 px/s |
| 120 Hz | 1.58 | ~2216 px/s |

The `scale_delta()` acceleration depends on the **per-poll** delta
size, so full-stick speed changed with poll rate — slowest at 120 Hz
ProMotion, which is what the user is most likely running. For
comparison, one fast touch swipe delivers ~2000+ px in a **single**
event, so the pad could never turn as fast as a finger.

Other suspects, checked:

1. **LOOK_SPEED 700 too low** — yes, the main bottleneck.
2. **1.8 power curve crushes mid-stick** — yes: 50% deflection gave
   only 22% of max speed (~387 px/s at 60 Hz); 75% gave 55%.
3. **dt cap 0.05 + poll rate** — yes, via the accel above (frame-rate
   dependent); the dt cap itself only bites below 20 Hz polling.
4. **Aim scale 0.4 when aiming** — partly: `pad.rs` falls back to 0.4,
   but on iOS `config.rs` sets `MUGUET_AIM_SENS` from
   `aim_sensitivity` (default **0.8**, launcher slider 0.1–3.0), so
   aimed full-stick was ~1120 px/s at 60 Hz. Kept as a separate
   multiplier, untouched by the pad setting.
5. **`mouse_delta_f` FRAC truncation losing small deltas** — **no**.
   `input.rs` accumulates the fraction across calls, so nothing is
   lost.

### 4c. Fix applied

- `LOOK_SPEED` 700 → **1400**, curve 1.8 → **1.5** (50% stick now
  28% of max instead of 22%; 75% stick 61% instead of 55%).
- New setting `pad_sensitivity` (default **2.0**) in `config.json`,
  mapped to `MUGUET_PAD_SENS` in `src/config.rs`, with a **Gamepad
  sensitivity slider (0.25–4.0×)** in the iOS launcher next to Look
  sensitivity (`ios/Launcher.swift`). Also honoured on reload
  (`MUGUET_PAD_SENS` added to `SETTING_VARS`).
- The pad no longer goes through `scale_delta()`'s per-event accel:
  rate is now flat `LOOK_SPEED × pad_sens` px/s before the shared
  mouse sensitivity, at **any** frame rate. Aim multiplier stays
  separate (`× aim_scale`, 0.85 vertical factor kept).
- **New effective speed** (defaults, not aiming):
  `1400 × 2.0 (pad) × 2.0 (mouse sens) = 5600 px/s` full stick,
  flat across frame rates — ~1.6× the old 60 Hz rate, ~2.5× the old
  120 Hz rate. Half stick ≈ 1590 px/s (was ~387). Aimed full stick
  ≈ 4480 px/s (aim scale 0.8).
- Debug logging (`MUGUET_DEBUG=1`): effective speed logged on
  controller connect (`pad connected: … effective full-stick 5600
  px/s`), and while the right stick moves, one line per second with
  raw stick value, curved value, dt, rate and final dx/dy
  (`src/debug.rs` `note_pad()`).

## 5. File picker tap does nothing — investigation + fix

### 5a. Root cause (verified in this code)

`ios/Launcher.swift:1458` still used SwiftUI `.fileImporter`:

```swift
.fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
    if case .success(let url) = result { importer.run(url) }
}
```

There is **no `.failure` branch at all**, so a tap that fails is
silently swallowed — exactly the bug the user hit on 2026-10-11 on the
original repo, for **any** zip, not just the game zip. It was
identified then as SwiftUI `fileImporter` swallowing taps on iOS 26.
Note: the picker selects a game **.zip file**, not a folder — only
`.zip` is allowed. The manual fallback in `importView` (unzip in
Files, copy `data/` and `b/` under On My iPhone > Muguet > `game/`)
was already in the UI and is correct; it is unchanged.

### 5b. Fix applied

- Replaced `.fileImporter` with a UIKit
  `UIDocumentPickerViewController` wrapped in a
  `UIViewControllerRepresentable` (`DocumentPicker` in
  `ios/Launcher.swift`): `forOpeningContentTypes: [.zip]`,
  `asCopy: true`, single selection.
- Delegate reports all three outcomes separately:
  `didPickDocumentsAt` / `didPickDocumentAt` → existing
  `Importer.run(url)` path unchanged (NSFileCoordinator +
  `muguet_import`); `documentPickerWasCancelled` → logged via
  `muguet_debug_log()`; a pick that returns no file → error shown in
  the launcher (`importer.error = "Import failed: …"`) and logged.
  A failed tap can no longer disappear silently.
- `Importer.run(url)` itself is untouched.

## 6. Verification

- `cargo check` on this Linux VM: **could not run**. The host check
  fails inside the `objc2` crate itself (`objc2 only works on Apple
  platforms`, a `compile_error!` in `objc2-0.6.5/src/lib.rs`) before
  the muguet crate is ever checked — this codebase cannot be
  host-checked on Linux at all. Toolchain here is cargo/rustc 1.100.0
  with only the `x86_64-unknown-linux-gnu` target installed;
  `aarch64-apple-ios` / `aarch64-apple-darwin` are not installed and
  were not installed (per the no-blind-toolchain-install rule).
- The Rust edits were therefore verified by careful re-reading against
  the surrounding code (all names, fields and signatures checked
  against the files as read), **not** by the compiler. The Xcode
  build (macOS) is the real gate: it will type-check both the Rust
  (iOS target) and the Swift changes. Treat the first Xcode build as
  the verification step — do not assume it is green.
- The Swift changes **cannot** be checked here (no macOS/Xcode); they
  are small and follow the file's existing patterns, but the
  `DocumentPicker` and the slider need the Xcode build to confirm.
- Revision 2026-11-26 (~01:30 PST): the crash premise was corrected
  (2–3 minutes into one session, not 2–3 runs). The new code in this
  revision — 2 s sampling with elapsed + slope in `src/debug.rs`,
  the 5 s critical purge throttle in `src/gpu.rs` — was verified by
  re-reading only, same as above. This revision is local only, NOT
  pushed; pushed commit `2ed2c2c` still carries the old premise in its
  audit text (the code fixes in it are unaffected).
- No game run, no IPA build, no `make-ios.sh`. No game files
  downloaded, no GTA assets in the repo.

## 7. How to test (phone)

### Crash / memory — ONE session, watch the clock

1. Rebuild + install the IPA from this branch (do not use the old
   Build 8.9 IPA — it has none of this).
2. Play ONE session the way it used to crash and note the elapsed
   time to the crash (2 min? 3 min? past 5?). Note whether you were
   standing still or driving/flying, and Story Mode or Sandbox.
3. Note how it dies: freeze first and then close, or instant close
   straight to the home screen?
4. In Files > Muguet, share `muguet-debug.log`,
   `muguet-runtime.log`, `muguet-previous.log` and `muguet-crash.log`
   (or use the launcher "Share startup / memory logs" button, which
   now includes `muguet-debug.log`).
5. In `muguet-debug.log`, read the slope, not the level: is the
   slope steady at ~600–1200 MB/min from the start (retained leak),
   flat then a sudden jump (one burst), or negative after a purge
   (purge worked, growth is elsewhere)? Then check which column
   climbs with it — `heap` (wasm heap, §1e #1), `tex live`
   (streaming, §1e #2), or neither (transient uploads, §1e #5).
   A `LEAK WATCH` line means live counts beat the previous run's peak.

To enable the debug log: `MUGUET_DEBUG=1` must be set at launch. It
is off by default; there is no in-app toggle yet.

### Gamepad camera

1. In the launcher, set **Gamepad sensitivity** (new slider next to
   Look sensitivity). Default 2.0× ≈ 5600 px/s full stick.
2. In game, hold the right stick fully left/right: the camera should
   now turn roughly twice as fast as before at 120 Hz.
3. If it is still slow or now too fast, move the slider (0.25–4.0×)
   — no rebuild needed, it is read from `config.json` on Play.
4. With `MUGUET_DEBUG=1`, `muguet-debug.log` shows one `pad …` line
   per second while the stick moves (raw / curved / dt / rate /
   final dx/dy) and the effective speed on connect.

### File picker

1. In the launcher, tap **Import game data .zip** (or "Import other
   game data…"). The system Files picker should open.
2. Tap a `.zip`: import progress should start (same as before).
3. Tap **Cancel**: the picker closes, no hang, and
   `muguet-runtime.log` gets a `picker cancelled` line.
4. If tapping a file still does nothing, share the runtime log — the
   failure now has a log line instead of silence.

## 8. Files changed

- `src/debug.rs` (new) — run counter, per-run log, sampling, leak
  watch, snapshot, pad logging, Swift bridge. Revised 2026-11-26:
  2 s sampling (was 5 s), every sample line carries elapsed `t` and
  the footprint slope in MB/min; `snapshot_text()` also carries `t`.
- `src/main.rs` — `mod debug`, `debug::init()`, stale `.cwasm`
  cleanup in `load_module()`.
- `src/diagnostics.rs` — panic hook dumps run + memory + GPU counts.
- `src/app.rs` — `memory_warning()` samples + logs the snapshot.
- `src/host.rs` — heap-growth refusals log run + GPU counts.
- `src/gpu.rs` — leak counters, `set_obj()` destroys the old object,
  `LOGGED` capped at 1024, purge trigger 192 → 384 MB, purge clears
  cached views / `blit_bg` / `mip_passes` / `dummy_tex` / `LOGGED`
  and logs what was cleared, `log_fps()` leak line. Revised 2026-11-26:
  purge throttle 15 s normally, 5 s when available is under 192 MB,
  with a `critical purge` log line.
- `src/config.rs` — `pad_sensitivity` default 2.0 + `MUGUET_PAD_SENS`
  mapping + reload list.
- `src/input.rs` — `mouse_sensitivity()` getter for the pad log.
- `src/pad.rs` — `LOOK_SPEED` 700 → 1400, curve 1.8 → 1.5, flat
  frame-rate-independent rate, `MUGUET_PAD_SENS`, connect + 1/s
  debug logging, aim multiplier kept separate.
- `ios/Launcher.swift` — Gamepad sensitivity setting + slider,
  UIKit `DocumentPicker` replacing `.fileImporter`, `muguet_debug_log`
  declaration, diagnostics share includes `muguet-debug.log`.
- `DEBUG_AUDIT.md` (this file).
