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

---

# DEEP AUDIT — 2026-11-26 (round 3)

Ordered 2026-11-26 ~02:26 PST, while the archive.org IPA build was on
hold: "run another full audit on the whole code trying to look for
bugs trying to add fallbacks and trying to find crashes". Whole
codebase, read-only first (four parallel audit passes), then fixes in
place. Local only — NOT pushed. No workflow run, no IPA build.

## 9. Scope — files audited

Every source file in the repo: `src/*.rs` — aim, app, audio,
bin/muguet-server, config, debug, diagnostics, fs, game_data, gpu,
host, import, input, io, main, mp, pad, patch, performance, proto,
server, touch, touch_gestures — plus `ios/Launcher.swift`,
`ios/*.entitlements`, `Cargo.toml`, `build.rs`, `make-ios.sh`,
`make-app.sh`, `.github/workflows/build-game-ipa.yml`,
`.github/workflows/build-ipa-archive.yml`.

Counts before fixing: 206 `.unwrap()` / `.expect()` / `panic!` /
`assert!` sites across `src/` and `Launcher.swift` — 80 in `mp.rs`,
58 in `gpu.rs`. Not every one is a bug (most are guarded or in
`#[cfg(test)]`); §10 lists only the ones that can actually fire on
the phone, with the guarded ones noted in §13.

## 10. Bugs found, by severity

Line numbers are where each bug was found (pre-fix). Severity:
**C** = can crash the app on the phone, **H** = can hang / silently
kill a subsystem / corrupt a run, **M** = wrong behaviour or
degraded experience, **L** = hygiene / cosmetic.

### 10a. Critical — can crash the app

| # | Location | What happens | Likelihood |
|---|----------|--------------|------------|
| C1 | `src/audio.rs:35,37–39,48–54` | Ring buffer pointer, size and write cursor are taken from wasm-controlled memory with no validation; the mask assumes power-of-two capacity. A game-controlled bad pointer or non-power-of-two size reads out of bounds in the realtime audio callback — segfault, instant kill. | Low (needs a bad game value) but the blast radius is the whole process |
| C2 | `src/audio.rs:35` | `RT.get().unwrap()` panics if audio publishes before the runtime exists — a startup race. | Low |
| C3 | `src/input.rs:26–39` | `base()` builds raw pointers into wasm memory from a game-published BLOCK with no bounds check (memory length discarded). A stale/short block reads out of bounds. | Low–medium (stale block after a heap resize) |
| C4 | `.github/workflows/build-game-ipa.yml:65` | Download step calls deleted `ci/download-wasm.cjs` — the workflow can never reach the build. (The script was deleted on purpose 2026-11-26; the workflow was not updated.) | Certain if the workflow is ever run |
| C5 | `make-ios.sh:23–28` + `ios/Muguet-free.entitlements` | **Strongest new explanation for the 2–3 minute crash.** `HEAP_GB` / `MUGUET_IOS_HEAP_GB` is a dead knob — no code anywhere reads it — while `Muguet-free.entitlements` is an empty dict: no `increased-memory-limit`, no `extended-virtual-addressing`. The heap code budgets up to 3 GB, but a free/sideload build without the entitlement jetsams far below that (the exact limit depends on the device and iOS version — the debug log's `footprint` at death is the tell). A 10–20 MB/s ramp hitting a jetsam limit well below 3 GB dies at ~2–3 min — exactly the observed crash. Ad-hoc codesign with `increased-memory-limit` is not honoured by iOS without an Apple-issued provisioning profile, so this is a paid-developer-account (or TrollStore) problem, not a code problem. | High — matches the crash timing on any non-entitled build |
| A1 | `src/gpu.rs` `uniform_alloc()` / `ubo_shared` / `ubo_slots` | Uniform ring ratchets without a cap: one new 24 MB GPU buffer per chunk index, forever until purge. `ubo_chunk` resets each present but `ubo_shared`/`ubo_slots` are high-water marks. A uniform-heavy scene adds 24 MB per growth event with no ceiling. | Medium — adds to the 2–3 min ramp (§1e #3, now capped) |
| A2 | `src/gpu.rs` proxy textures | Depth/float proxy textures are permanent full-size duplicates of their source (one texture + view + bind group per mip × layer), never purged. | Medium — steady growth while streaming new areas |
| A3 | `src/gpu.rs` `u()` / `bytes()` / `atomic()` | Unchecked raw reads of wasm memory — game-controlled addresses, no bounds check against `mem.data_size()`. (Contrast: `main.rs` `read_bytes`/`write_bytes` ARE bounds-checked.) An out-of-range ring word reads arbitrary host memory. | Low–medium |
| A4 | `src/gpu.rs` ring protocol | No bounds validation on the command ring: a corrupt `head`/`n` runs garbage commands forever; `(n*4+8) as i32` wraps. | Low (needs corrupt game state) |
| A5 | `src/gpu.rs` `create_state` / `create_layout` / `create_shader` / viewports | Unbounded-count `Vec` allocations sized by ring words (viewports/scissors, create_state, create_layout, create_shader). A corrupt count word allocates gigabytes and the process is killed. | Low |
| B2 | `src/gpu.rs` vertex slots | Vertex slot ≥ 16 panics in 3 places (layout allows slots up to 31, consumer arrays are 16). A shader with a slot ≥ 16 kills the GPU thread. | Low |
| B6 | `src/gpu.rs` surface caps | `caps.formats[0]` / `caps.alpha_modes[0]` index panics if a device reports zero formats/alpha modes. | Very low |
| main:409 | `src/main.rs:409` | `RT.get().expect("runtime")` in a wasmtime host callback (`spawn_pthread`) — panics the engine thread if the runtime is not set yet. | Low |
| main:431 | `src/main.rs:431` | `high - size` underflow in pthread stack-limit computation — panics in debug, wraps in release. | Low |
| main:516–546 | `src/main.rs` `read_u64` / `read_u32` / `read_bytes` / `write_bytes` | `a + n` overflows before the bounds check, so the check itself can be defeated and the read/write goes out of bounds. | Low |
| io:24–28 | `src/io.rs` `atomic_i32` | Asserts on guest-controlled addresses — a bad address panics and kills the only I/O thread permanently (no restart). | Low–medium |
| io:20–21,43 | `src/io.rs` `manifest_files().expect(...)` | Panics the I/O thread at startup if the manifest is unreadable — no game, no retry. | Low |
| main:225 | `src/main.rs` unwind path | On an engine panic the main thread parks forever with no watchdog and no exit — the app hangs on a black screen instead of restarting or reporting. | Low |
| main:261–262 | `src/main.rs` embedded code | `__GAME` length underflow + `NonNull::unwrap()` when loading embedded game code. | Very low |

### 10b. High — hang, silent subsystem death, or data loss

| # | Location | What happens |
|---|----------|--------------|
| B1 | `src/gpu.rs` `process_maps` | `get_mapped_range().expect()` panics on a failed map — the map callback marks failure as done, so a failed readback kills the GPU thread. |
| B4 | `src/gpu.rs:67,289,917,949,3405`, `src/host.rs:75,104,133`, `src/input.rs`, `src/pad.rs`, `src/app.rs`, `src/fs.rs`, `src/mp.rs` (66 sites) | `.lock().unwrap()` everywhere — one poisoned Mutex (after any panic in a lock holder) cascades into every later lock on that Mutex, killing thread after thread. |
| D1 | `src/gpu.rs` thread body | Any panic kills the GPU thread permanently — no restart, no watchdog; the frame freezes forever. |
| D2 | `src/gpu.rs` (3 sites) | Unbounded `device.poll(Wait, timeout: None)` — SUSPENDED branch, op 8 fence, `present()` — a stuck GPU waits forever. |
| D3 | `src/gpu.rs` `Gpu::new` | Failure → `drain_forever`, no retry, no recovery; a transient device loss is a dead app. |
| H1 | `src/mp.rs:381,1000,1124`, `src/host.rs` | `RT.get().unwrap()` in hot multiplayer paths. |
| H2 | `src/mp.rs` receive_loop | `sleep(5s)` on the single mp-net thread when the room is full — self-reinforcing stall: nothing is received while it sleeps, so the room stays full. |
| H3 | `src/mp.rs` host change | Host change orphans every avatar + mirror entity — strongest game-side growth vector in these files when multiplayer is on (entities accumulate, never despawned). |
| H4 | `src/mp.rs` `PARKED` | Grows unbounded; the 300 s expiry is never enforced by the tidy pass. |
| H5 | `src/mp.rs` `Game.taken` | Insert-only, never cleared — a stale key blocks mirroring a later car that reuses the handle. |
| H6 | `src/mp.rs` receive_loop | Hot-spins on persistent recv errors (100% CPU); thread can die silently; `NET` caches `None` so it never retries; spawn failures ignored. |
| app:253–258 | `src/app.rs` `memory_warning` | Observability only — it logs and samples but cannot prevent the 2–3 min jetsam kill. (Now acts: see §11.) |
| H7 | `make-ios.sh:50–52` | `wasm-opt` failure destroys the only copy of the optimised wasm — the cache is wiped first, then the script aborts under `set -e`. |
| H8 | `src/fs.rs` fd table | Unbounded growth up to `RLIMIT_NOFILE`; no fd reuse, so long sessions exhaust descriptors. |
| H9 | `src/fs.rs` `getdents64` | Returns 0 forever when `count < 280` — the game sees an empty directory forever instead of an error. |
| H10 | `src/fs.rs` `fd_read` | Reads the whole file into one `Vec` (`vec![0u8; len]`) — a large game file spikes memory by its full size. |
| H11 | `src/config.rs` `locate()` | Failure swallowed to an empty path on iOS — a missing game dir looks like an empty one, no error. |
| H12 | `src/import.rs` swap | Destructive swap deletes the old game before the rename succeeds — a failed import leaves no game at all. |
| H13 | `src/import.rs` `CStr::from_ptr(zip)` | No null check on the FFI pointer. |
| H14 | `src/main.rs` `.cwasm` cache key | Keyed only by (length, mtime-seconds, patch-key) — a changed wasm with the same length and second can load a stale precompiled module. |
| H15 | `src/config.rs` `build_dir` | Picks the lexicographically first build, not the newest — after a re-import, stale shaders can pair with a current wasm. |
| H16 | `src/main.rs` config failure | Exits the process with `process::exit(1)` and no iOS-visible error — the app just vanishes on launch. (Now persists + shows the error: see §11.) |
| H17 | `src/app.rs` `create_window` / `create_surface` | `.expect()` — a transient surface failure at startup panics instead of retrying on next `resumed()`. |
| H18 | `src/app.rs` startup | No timeout — a stuck engine load hangs the launcher forever with no retryable error. |
| H19 | `src/app.rs` `launch_engine` | No double-launch guard; a clean engine return calls `process::exit(0)` — the app quits instead of returning to the launcher. |

### 10c. Medium — wrong behaviour, missing fallback, or waste

| # | Location | What happens |
|---|----------|--------------|
| C1 | `src/gpu.rs` `set_obj` | Dense `Vec` resized by a game-controlled id (cap was 64M entries). |
| C2 | `src/gpu.rs` `create_buffer` / `bc_decode` / `clear_uav` / `upload_*` | Per-call heap allocations sized by game values (BC decode, clear_uav, create_buffer shadow, upload `.to_vec()`, per-readback buffers). |
| C3 | `src/gpu.rs` copy_region / readback | Box coords underflow and wrap to huge extents. |
| C4 | `src/gpu.rs` caches | `bgl_cache`, `compute`, `variants`, `unfilt`, `nearest`, `pending_clears`, `proxy_pipelines`, `mip_pipelines` cleared only by purge (some never — see §11, proxy/mip now cleared by purge). |
| M1 | `src/mp.rs` `shutdown()` | Shuts nothing down — socket stays open, threads keep running. |
| M2 | `src/server.rs:87` | Id allocation `unwrap()` (safe today only because the room-count guard runs first). |
| M3 | `src/server.rs` sweep | Unbounded `players` by address + O(n²) name flood every 2 s. |
| M4 | `src/mp.rs` dead mirrors | `release()`d, not deleted — mirror state lingers. (Deliberately not changed: §13.) |
| M5 | `src/mp.rs` wasm scratch | Scratch can leak if `sp == 0`; `unwrap_i64()` assumes wasm64. |
| M6 | `src/mp.rs` | Per-frame / per-packet allocation churn (contributor, not a leak). |
| M7 | `src/mp.rs` `rel_seen` / `pending` | Only half-bounded. |
| M8 | `src/audio.rs` | `STARTED` latches true before success — no retry after a failed start; no route/interruption handling; hardcoded 48 kHz stereo, never queries the device. |
| M9 | `src/input.rs:252` | i32 overflow in mouse position (`saturating_add` now). |
| M10 | `src/input.rs:261–289` | `apply_cheat` spawns an unbounded, unjoined thread per call. |
| M11 | `src/touch.rs:178–210` | Unclamped sensitivity env vars; NaN poisons button geometry. |
| M12 | `src/touch.rs:312–384` | `install()` never removes a previous overlay — stale touch views stack. |
| M13 | `src/touch.rs:739–745,747` | `RefCell` `borrow_mut` panics on re-entrant touch/refresh. |
| M14 | `ios/Launcher.swift:1672–1674` | `muguetSetRefreshRate` re-reads config from disk and resets the HUD layout on every call (`Settings.init` calls `applyCustomLayout()`). |
| M15 | `ios/Launcher.swift:1050,1728` | `exit(0)` kills the app abruptly (both SwiftUI Exit button and menu "Thoát ứng dụng"). |
| M16 | `ios/Launcher.swift` menu/share | Picks the first scene, which may not be the foreground one. |
| M17 | `make-ios.sh:68,82` + `make-app.sh` | Quiet builds hide the error when they fail; shallow codesign verify; no `--locked` on cargo builds; `make-app.sh` copies `muguet-server` from the wrong target dir when embedded. |
| M18 | `.github/workflows/build-game-ipa.yml` | 90 min timeout too tight for a cold build; source floats on `ref: main`; `BUILD-INFO.txt` hardcodes a stale source SHA `0d43ef30746dc8c5076a6d509635b515f185bb40`; dead `MUGUET_IOS_HEAP_GB: "5"` env line. |
| M19 | `.github/workflows/build-ipa-archive.yml` | 20 GB download has no checksum and a non-failing content check (no pipefail; `unzip -l | grep | head` exits 0 via `head` even if `game.wasm` is absent); no Rust cache; unpinned Xcode; Release publishes the IPA with game code on every run. |
| M20 | `src/pad.rs` | Env vars parsed on every poll/look event; no controller connection notifications. |
| M21 | `src/config.rs` `find_all_settings_files` | Recursion without depth/symlink protection. |
| M22 | `src/fs.rs` `ok_i` | Truncates with `as` instead of clamping to i32. |
| M23 | `src/import.rs` | Zip-bomb exposure (no entry-count / total-size caps); `tidy_lists` writes non-atomically. |
| M24 | `src/patch.rs` | `tls_global` guesses index 1 when `__tls_base` is missing; index arithmetic can overflow. |
| M25 | `src/game_data.rs` | Aborts on the first missing file instead of listing all of them. |
| M26 | `src/diagnostics.rs` | `trim()` never called at install; `dup2` return unchecked; panic hook truncates the crash log instead of rotating it. |
| M27 | `src/debug.rs` | Log rotation missing; `persist_json` runs under the STATE lock (deadlock-prone) and on every call. |
| M28 | `src/main.rs` `coerce_args` / `build_argv` | Arg count mismatches silently dropped; unchecked writes in `build_argv`. |
| M29 | `src/io.rs` `handles` | Eviction clears all 1024 handles at once (thrash); slot scan can wrap; reads loop once and can short-read. |
| M30 | `src/config.rs` shader validation | Uses metadata-then-read (TOCTOU); `RUNTIME_MANIFEST.set` result ignored. |

### 10d. Low — hygiene / cosmetic

`proto.rs` decode unwraps (all guarded by length checks — `STATE_SIZE` 105, Shot 28, VehLook 69); `mp.rs:1389` `snaps.back().unwrap()` and `mp.rs:2313` `look.as_ref().unwrap()` (safe today, fragile); `punch_anim` never retries once the pick passes the length; `input.rs:174` `chars().next().unwrap()` (guarded); `input.rs:189` unknown mouse button becomes left-click; `touch.rs:546` unwrap on the hot path (provably safe today); `touch.rs:542` divides by scale; `touch_gestures.rs` clean; `aim.rs` clean; `Launcher.swift:8–9` force-index `[0]` on the documents directory; no `didReceiveMemoryWarning` / `sceneDidEnterBackground` / `AVAudioSession` handling in the launcher; DocumentPicker `asCopy: true` copies a ~20 GB zip with no size check; `shareDiagnostics`/`shareSaves` silently do nothing when there are no logs / no key window; `Settings.save()` failures swallowed; `build.rs:13` only `ios/Launcher.swift` is a `rerun-if-changed` trigger; `Cargo.toml` vendor/wgpu-core patch is an undeclared dependency; `audio.rs:66–79` logger thread never exits.

## 11. Fixes applied (round 3)

### 11a. The 2–3 minute crash — new findings and mitigations

- **C5 (entitlements) — the headline.** `ios/Muguet-free.entitlements` is an empty dict. A free/sideload build therefore jetsams far below the 3 GB the heap code budgets. This matches the crash timing on any non-entitled build and is the most likely explanation if the phone test is run on a sideloaded IPA. **Code cannot fix this**: the entitlement has to come from an Apple-issued provisioning profile (paid Developer account) or a TrollStore install. Recorded here so the phone test is read correctly — if the debug log shows the footprint dying at ~1–1.5 GB with a steady slope, it is the entitlement ceiling, not a leak. The dead `HEAP_GB` / `MUGUET_IOS_HEAP_GB` knob was removed from `make-ios.sh` (replaced with a comment: the cap lives in `src/performance.rs` `IOS_HEAP_MAX`, 3 GB) so nothing pretends to raise the limit anymore.
- **`src/performance.rs` — a working heap knob.** `ios_heap_budget()` now honours runtime env `MUGUET_HEAP_GB_MB` (validated, clamped 512–3072 MB). Note the limit: a sideloaded IPA has no launch env, so the compiled-in 3 GB is what the phone uses — the knob helps macOS/dev testing, it does not raise the jetsam ceiling on a free build.
- **`src/gpu.rs` `uniform_alloc()` — A1 capped.** New `UBO_MAX_CHUNKS` const: at most 8 chunks (192 MB worst case per purge window); beyond that the draw is skipped and a `log_once` line is written. `pack_copy` propagates the `None`.
- **`src/gpu.rs` purge — A2 fixed.** Purge now also clears `proxy_depth` / `proxy_stencil` / `proxy_fdepth` / `proxy_half` (full-size duplicate textures, rebuilt on demand) and `proxy_pipelines` / `mip_pipelines` (get-or-create caches, rebuilt on demand).
- **`src/app.rs` `memory_warning` — now acts.** A second warning within 60 s with available memory under 200 MB stops the game cleanly with an `ENGINE_ERROR` "Low memory" message instead of waiting for jetsam to kill the process mid-frame. A clean stop is diagnosable; a jetsam kill is not.

### 11b. Panic paths removed (graceful fallback instead of unwrap)

- **`src/gpu.rs`** — `atomic()` free fn bounds-checked with a static dummy `AtomicI32` fallback (OOB reads return 0, writes go nowhere); `u()`/`bytes()` bounds-checked against `mem.data_size()` with `log_once` on OOB; ring tail/head validated (resync on corrupt values) and per-command `n` checked (`checked_mul`, cap 1<<22 bytes, bounded by pending bytes or end of wasm memory), per-command `catch_unwind` around `exec` (log + skip on panic); `exec`'s local `u` closure bounds-checked (same pattern in `do_draw` and readback); ops 30/31 viewport/scissor counts capped at 16; `set_obj` id cap lowered 64M → 1M; `create_buffer` rejects sizes above `adapter.limits().max_buffer_size` (min 256 MB) with `log_once`; `upload_buffer`/`upload_texture` skip on short read instead of indexing `data[..n]`; `upload_texture` `tex_mut(id).unwrap()` → let-else; `create_shader` nin capped at 64; `create_layout` n capped at 64 and slots accepted only <16 (fixes all downstream 16-entry array indexing at the source); `create_state` words capped at 4096; `srv_view` `layers - c` → `layers.saturating_sub(c)`; `pass_info`/`args` unwraps → let-else with `self.skip(); return;`; copy_region/readback box coords use `saturating_sub` and reject empty/inverted boxes; `PendingMap` gained a `failed` flag (map_async callback records failure; `process_maps` drops failed buffers instead of `expect()`ing the mapped range; `get_mapped_range()` `Err` also skipped; process_maps wait path given a 2 s timeout); readback copy destination `to` bounds-checked against wasm memory length; `prune_graphics_cache` evicts oldest-first with a hard cap (dropped the `seen < recent` filter); `caps.formats[0]` → `.first().copied().unwrap_or(Bgra8Unorm)`, `alpha_modes[0]` → `.first().copied().unwrap_or(Opaque)`; SUSPENDED-branch, op 8 fence, and `present()` `device.poll(Wait)` calls given finite 2 s timeouts (present waits on the 3-frames-old submission); GPU thread body wrapped in `catch_unwind` — on panic it logs, sets `engine_error`, and parks instead of a silent frozen frame; `SURFACE`, `log_once`, `kinds`, compile-thread locks poison-tolerant; compile-thread spawn failure logged instead of panicking `Gpu::new`; `start()` spawn failure clears `STARTED` and surfaces `engine_error`. Remaining `gpu.rs` `.unwrap()` sites were re-checked one by one and are get-or-create (`encoder()`, `empty_bgl()`, blit pipeline) or immediately-preceded-by-check patterns — left alone, see §13.
- **`src/host.rs`** — `missing_text` TEXT lock poison-tolerant + RT guard returning `Ok(0)`; `call` RT guard returning `Ok(())`; `PENDING_MAILBOX` locks poison-tolerant; `exit`/`proc_exit` now logs and ignores `exit(0)` (non-zero still terminates); `invoke` uses `params.get(1..).unwrap_or(&[])`; `heap_max` now uses `ios_heap_budget` so the 3 GB cap holds regardless of caller; `resize_heap` clamps the request to max before the multiply and uses `saturating_mul`.
- **`src/main.rs`** — footprint_mb named the rusage word and logs once on failure; `engine_thread_qos` parens explicit + mixer match case-insensitive; config-setup failure on iOS also persists the error to `Documents/muguet-startup-error.txt`; `run_engine` unwind path parks at most 5 s then returns an error instead of parking forever; embedded game-code load uses `checked_sub` for the `__GAME` length + a `NonNull` check; JIT `load_module` cache now keys on a hash of the wasm bytes (not only length + mtime), logs an unusable cached `.cwasm` instead of silently discarding it, writes via temp file + atomic rename; `heap_type` uses checked arithmetic with a page-size guard; `spawn_pthread` returns error code 6 instead of `expect("runtime")`; `run_pthread` stack limits use `checked_sub` with validation; `coerce_args` logs count mismatches and pads missing args with type defaults; `build_argv` checks every write + checked arithmetic; `read_u64`/`read_u32`/`read_bytes`/`write_bytes` use `checked_add`; `args.len()` cast to i32 is saturating.
- **`src/io.rs`** — rewritten: `atomic_i32` returns `Option` with checked bounds/alignment, `manifest_files` returns `Result` instead of `expect`, `start()` clears `STARTED` on thread exit or spawn failure so a retry is possible, slot count capped at 4096 with the whole table validated before scanning, handles eviction removes 16 at a time instead of clearing all 1024, reads loop with `read_at` returning bytes actually read, `dst+len` uses `checked_add`.
- **`src/app.rs`** — `startup_status`/`engine_error` and all lock sites use `unwrap_or_else(|e| e.into_inner())`; `backbuffer_size` validates `MUGUET_SCALE` (finite, clamped 0.25–2.0) and `MUGUET_RES` (320–2560 × 240–1440); `create_window`/`create_surface` failures return for retry on next `resumed()` instead of panicking; startup times out after 120 s, resets `started=false` and `runtime_rx=None`, shows a retryable error; `start_engine` spawn failure resets `started=false`; `launch_engine` has an `AtomicBool` double-launch guard and a clean engine return sets `ENGINE_ERROR` instead of `process::exit(0)`. After these edits `app.rs`, `main.rs`, `io.rs` have zero remaining `.lock().unwrap()` / `.expect()` / `.unwrap()` sites; the remaining `process::exit(0)` calls are window-close and Cmd-Q — intentional user exits with `mp::shutdown()` first.
- **`src/fs.rs`** — `Fs` gained a `free_fds` reuse list + `alloc_fd()` helper (reuse freed numbers, cap 1024 open entries, evict one arbitrary file entry with a log line instead of growing to `RLIMIT_NOFILE`); create_dir_all errors in FS init now logged instead of ignored; `ok_i` clamps i32 instead of truncating with `as`; iovecs capped at 1024 with checked address arithmetic; FS lock poison-tolerant; openat dir/file allocation uses `alloc_fd` and the real open error is logged (keeping the -ENOENT fallback because the exact emscripten errno numbers for EACCES/ENOSPC/EMFILE are not verified in this codebase — do not guess them); fstat64 metadata unwraps replaced with match returning -EBADF; `getdents64` returns EINVAL when count < 280 with entries remaining and stops on failed `write_bytes` instead of advancing; `fd_read` reads in 1 MiB chunks with a reused buffer and logs read errors instead of swallowing them to 0; `fd_close` pushes the freed number back for reuse.
- **`src/config.rs`** — `build_dir` picks the newest build by `game.wasm` mtime and warns if more than one build exists; shader-index validation uses a capped reader instead of metadata-then-read, validates shader entries exist and names missing ones (up to 10), checks `RUNTIME_MANIFEST.set` result instead of ignoring it; `setup()` bails on iOS if HOME is unset instead of letting `support_dir()` fall back to /tmp; iOS `locate()` failure propagated unless game code is embedded, in which case it logs and continues; `find_all_settings_files` now iterative with depth cap 8, file cap 64, symlink skipping; fps/start_mode filter non-finite values and clamp fps to 15–240; Regex patterns in `set_num`/`set_float`/`set_bool` use `regex::escape(tag)`; `DEFAULT_CONFIG` parse uses expect with a message (compile-time constant).
- **`src/game_data.rs`** — `files.len()` capped at 1,000,000 before `with_capacity`; all missing files collected and reported together (up to 10 names + count) instead of aborting on the first.
- **`src/import.rs`** — zip entry count capped at 1,000,000, total uncompressed size capped at 64 GiB with `checked_add`; extraction + swap wrapped in a closure so a mid-import failure cleans up staging; rollback-safe swap (old game moved to `dest.old` first, staging renamed in, backup deleted only then, restored on failure); `tidy_lists` writes via `.tmp` + atomic rename (new `write_atomic` helper); FFI `muguet_import` null-checks the zip pointer; ERROR lock poison-tolerant; `muguet_import_error` pointer documented as valid only until the next import call.
- **`src/patch.rs`** — `checked_add` in `function_index`, `parse_import_section`, `parse_export_section`, Call construction (bail on overflow); `tls_global` now bails if no `__tls_base` global instead of guessing index 1; duplicate function names log a warning instead of silently keeping the first.
- **`src/diagnostics.rs`** — `trim()` called at `install()`; `dup2` return checked; panic hook wraps `snapshot_text()` in `catch_unwind` and appends to the crash log (rotates at 1 MiB) instead of truncating.
- **`src/debug.rs`** — run counter uses `saturating_add`; `muguet-debug.log` rotates at 1 MiB (rename to `muguet-debug-prev.log`); `persist_json` moved out of the STATE lock (dirty flag, flush after drop) and throttled to at most once per 2 s (new `last_persist` field).

### 11c. Multiplayer / server

- **`src/mp.rs`** — all 66 `lock().unwrap()` sites converted to `lock().unwrap_or_else(|e| e.into_inner())` (verified 0 remaining, 66 converted). `NET` reworked from `OnceLock<Option<Net>>` (cached a failed init forever) to a retryable `Mutex<Option<&'static Net>>` + `NET_LAST_TRY` (retry at most every 30 s) + `build_net()` extraction with `Box::leak`; `try_clone` expect → return `None` with a log; `shutdown()` sets a new STOP flag and shuts the socket down so `recv` unblocks; `explosion()` RT guard; receive_loop: STOP check, transient `None` → sleep 1 s + continue instead of silent exit, HELLO gated by a new `full_until` field, recv errors split into WouldBlock/TimedOut (continue) vs other (throttled 1 s log + 50 ms sleep) instead of hot-spinning at 100% CPU; dispatch FULL sets `full_until = now + 5s` and keeps receiving instead of sleeping 5 s (WELCOME clears it); `script_tick` RT guard + GAME `try_lock` (skip tick on WouldBlock instead of deadlocking on re-entrant `muguet_script`; poison recovered); `sp == 0` skips the scratch allocation (2 KB leak fix) and `unwrap_i64()` replaced with a match on `Val::I64`/`I32`; host-change now defers despawn until `Cmd` exists, drains + despawns avatars and mirrors via `despawn()`/`remove_mirror()`, and clears `taken`; `taken` changed from `HashSet<(u8,u32)>` to `HashMap<(u8,u32), Instant>` with 60 s expiry in `mirror_population`; `park()` caps PARKED at 64 (evict oldest); `adopt_parked`/`tidy_parked` rewritten with `retain_mut` in place (no whole-Vec clone per call) and `tidy_parked` now enforces the 300 s `PARKED_KEEP` expiry; `send_reliable` pending capped at 128 (drain oldest 16); `rel_seen` entries removed for timed-out peers in the peer-retain pass; `snaps.back().unwrap()` → and_then/map, `look.as_ref().unwrap()` → if-let. Note: with multiplayer off, `frame()` never runs and the mp-net thread exits at once (`mp.rs:431` returns `None` unless `MUGUET_HOST`/`MUGUET_SERVER` are set; `config.rs:208–214` sets those only when the multiplayer flag is on, default server `18.143.103.253`) — so no Rust-side unbounded leak growing 10–20 MB/s exists in these files in pure single-player.
- **`src/server.rs`** — Player gained `name_dirty: bool` (set on join and rename); the sweep broadcasts names only for dirty players (collected first, then sent) instead of O(n²) every 2 s; total player cap 256 across rooms (FULL beyond it); id allocation unwrap → let-else sending FULL.

### 11d. Audio / input / pad / touch

- **`src/audio.rs`** — ring validated before the realtime callback ever dereferences it (capacity must be > 0 and power-of-two; `ring + 64 + capacity*8 <= mem_len`, else silent audio, not a segfault); RT guard returning `Err("runtime not ready")`; STARTED latches only on success (`compare_exchange` guard; cleared on play failure or spawn failure so the next publish retries); sample rate now prefers `device.default_output_config()` (native rate) with 48 kHz stereo fallback; logger prints the actual rate instead of assuming 48000. Caveat: if the device's native rate is not 48 kHz, the game still generates 48 kHz samples — the stream will play at the wrong pitch until a resampler is added (§13).
- **`src/input.rs`** — all 6 lock sites poison-tolerant (verified 0 remaining); `base()` now bounds-checks BLOCK against mem length (requires 512 bytes of room; the block layout tops out at offset 440+4) so stale blocks return `None`; SENS LazyLock rejects non-finite and clamps 0.1–10; mouse_delta uses `saturating_add`; `apply_cheat` has a `CHEAT_RUNNING` AtomicBool dedupe guard (cleared at thread end); unknown mouse button ignored instead of mapping to left-click; start-mode index uses `.get().copied().unwrap_or("?")`; `chars().next().unwrap()` → `is_some_and`.
- **`src/pad.rs`** — STATE locks poison-tolerant; `pad_sensitivity` and aim sens cached in LazyLock statics (parsed once, NaN/inf rejected, clamped) instead of env-parse on every poll/look event.
- **`src/touch.rs`** — new `env_f64()` helper (rejects non-finite, clamps) applied to touch sens (0.25–6.0), aim sens (0.1–3.0), button scale/offsets/opacity, stick offsets; `install()` removes the previous overlay's root UIView via `removeFromSuperview` before replacing it; all RefCell borrows changed to `try_borrow_mut` (touch/refresh/loading/release/`muguet_apply_button_layout`/`update_settings_from_env`/install assignment); `is_wheel`/`spec_act`/`apply_layout`/`button_at` use `BUTTONS.get()` instead of direct indexing; `touch()` guards scale (finite, > 0, else 1.0) and `spec_act` unwrap → let-else return.

### 11e. Launcher (Swift)

- **`ios/Launcher.swift`** — Settings gained `static var cachedPromotionSync` (updated in `init()` and `save()`); `muguetSetRefreshRate` reads the cached value instead of constructing a fresh `Settings()` (which re-read `config.json` and re-applied the button layout on every FPS change); new `foregroundKeyWindow()` / `foregroundRootViewController()` helpers (foreground-active scene, fallback any key window) used by `muguetOpenMenu`, `shareDiagnostics`, `shareSaves`; new `suspendApp()` (`UIApplication.shared.perform(#selector(NSXPCConnection.suspend))`) replaces both `exit(0)` calls (SwiftUI Exit button and menu "Thoát ứng dụng" action); `shareDiagnostics` shows a "No logs" alert instead of silently doing nothing when there are no logs; **startup-error surfacing** (round-3 §10b H16): the launcher now reads `Documents/muguet-startup-error.txt` on appear (`checkStartupError()`), shows it in the existing `error` label, and deletes the file after one show — a config failure before the game window exists no longer looks like a silent quit on the next launch.

### 11f. Build scripts, build.rs, workflows

- **`build.rs`** — xcrun closure now checks the exit status and includes stderr in the panic message, uses `from_utf8_lossy` instead of `unwrap`; `OUT_DIR` unwrap → expect with a message; swiftc now uses `.output()` (not `.status()`) with stderr in the assert message; `parent().unwrap().parent().unwrap()` chain replaced with an explicit check; `rerun-if-changed` added for the entitlements, `project.yml`, `Cargo.toml`; assert that `vendor/wgpu-core/Cargo.toml` exists with a clear message (a checkout without the vendor dir used to fail later with an opaque patch error).
- **`make-ios.sh`** — dead `HEAP_GB` / `MUGUET_IOS_HEAP_GB` export removed (replaced with the comment in §11a); `wasm-opt` fallback — the old cache is kept until the new file verifies (`test -s`), and on failure the script warns and continues with the unoptimised wasm instead of aborting under `set -e` after destroying the only good copy; `codesign --verify` → `--verify --deep --strict`; both cargo builds get `--locked`; `xcodegen` checked with a helpful message; `-quiet` dropped from `xcodebuild` so failures are visible.
- **`make-app.sh`** — both cargo builds get `--locked`; `muguet-server` now comes from the same target dir as `muguet` (`target/embed/release/` when embedded, instead of always `target/release/`); missing binaries fail with a clear message; `cp assets/*.mp3` guarded (an unmatched glob used to stay literal in `sh` and fail the copy).
- **`.github/workflows/build-game-ipa.yml`** — download step no longer calls the deleted `ci/download-wasm.cjs`: it takes a `workflow_dispatch` input `game_wasm_url` (required), downloads with curl + retry, and verifies SHA-256 against the pinned `11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0` before use (fails fast with a clear message if no URL is given); timeout 90 → 180 min; source pinned to SHA `3b4b7c69f512c49ba47a44b93f88abdecc6c9d0f` instead of floating `ref: main`; dead `MUGUET_IOS_HEAP_GB: "5"` env line removed; `BUILD-INFO.txt` writes the actual checked-out SHA (`git rev-parse HEAD`) instead of the hardcoded stale `0d43ef30746dc8c5076a6d509635b515f185bb40`; cache key adds `vendor/**`; `-quiet` dropped from `xcodebuild`.
- **`.github/workflows/build-ipa-archive.yml`** — download step now has `set -euo pipefail`, verifies the archive.org SHA-1 `94432a5e4538a6ed90a4281ff14a9c5508d147f2` for the 20 GB zip (a resumed download can stitch a corrupt file), and the content check is fail-fast (`grep -q` for `b/8b0b5899ed/game.wasm`, `data/manifest.json`, `shaders/index.json` — the old `unzip -l | grep | head` exited 0 via `head` even when `game.wasm` was absent); Rust cache added; dead `if [ -f game.zip ]` fallback removed from the Build step (curl `--fail` already fails the download step); Release step gated behind a `workflow_dispatch` input `publish_release` (default false — the IPA contains game code, it should not publish publicly on every run); artifact upload gets `if-no-files-found: error` + 7-day retention.

## 12. Fallbacks added (summary)

- Audio fails / bad ring → silent audio, game keeps running; audio start retries on next publish.
- GPU device lost / `Gpu::new` fails → `engine_error` surfaced, no silent frozen frame; GPU thread panic → logged + parked, not a hung frame.
- Surface/window creation fails → retry on next `resumed()`; startup stuck → 120 s timeout + retryable error; engine returns cleanly → back to launcher, not `exit(0)`.
- Heap growth refused → logged with run + GPU counts (unchanged from §2); memory warning twice in 60 s under 200 MB → clean stop with a "Low memory" message instead of a jetsam kill.
- Uniform ring full → draw skipped, one log line, no unbounded buffer growth.
- Shader/texture/state creation with corrupt counts → capped, skipped, logged.
- Multiplayer net init fails → retries every 30 s instead of caching `None` forever; room full → keep receiving, retry the HELLO after 5 s; recv errors → throttled, not a 100% CPU spin.
- I/O thread dies → `STARTED` cleared, retry possible; manifest unreadable → error, not a panic.
- Import fails mid-way → staging cleaned up, old game restored from `dest.old`; zip bombs capped (1,000,000 entries / 64 GiB).
- Config fails before the window exists → error persisted to `muguet-startup-error.txt` and shown in the launcher on next launch.
- `wasm-opt` fails → warn and continue with unoptimised wasm; download corrupt → SHA-1/SHA-256 verification fails the workflow before the build starts.
- Controller disconnects → touch still works (unchanged); pad sensitivity is a cached, validated value, not a per-event env parse.

## 13. Deliberately NOT fixed, and why

- **`src/gpu.rs` device-loss recovery / `Gpu::new` retry.** The handoff (surface + window) is consumed by the first attempt; a retry would come up headless. Needs the window handed back from `app.rs` — a bigger refactor, not a surgical fix. Documented in code + here.
- **`mp.rs` `Cmd::mem()` unwrap (`RT.get().unwrap()`, mp.rs:1219).** Guarded at both entry points (`script_tick`, `explosion`) and `RT` (OnceLock) is never cleared, so the unwrap is unreachable-after-guard. Left as-is, documented in the audit doc, not re-reported as fixed.
- **`mp.rs` M4 dead mirrors `release()` vs delete.** A behaviour change to mirror lifecycle; needs measurement on a live multiplayer session before changing.
- **`mp.rs` M6 allocation churn.** Performance, not correctness; no leak.
- **`src/audio.rs` logger thread never exits.** One leaked thread, negligible.
- **`src/audio.rs` resampling.** If the device's native rate is not 48 kHz, the stream plays at the wrong pitch. Needs a resampler — not a crash fix, left for a later pass.
- **`src/gpu.rs` C2 `create_buffer` shadow / `bc_decode` / `clear_uav` multi-GB texture caps.** The buffer cap is now enforced against `adapter.limits().max_buffer_size`; texture allocations are mip-clamped and go through `scoped()` validation, so a 16K×16K case is theoretical, not reachable from the game's own validated texture descriptors. Not capped further.
- **`src/server.rs` O(n²) name sweep.** Bounded by the dirty-flag change instead of a rewrite (names now broadcast only for dirty players).
- **`mp.rs` L6 `punch_anim` never retries.** Cosmetic.
- **`src/touch.rs` / launcher background/interruption handling** (`didReceiveMemoryWarning`, `sceneDidEnterBackground`, `AVAudioSession`), **DocumentPicker `asCopy` size check**, **`configURL [0]` force-index**, **`Settings.save()` swallowed errors.** Not done — each needs a design decision (e.g. what to do with a 20 GB copy) rather than a one-line fix; listed here so they are not lost.
- **`src/pad.rs` GCController connection notifications.** Polling already covers connect/disconnect within 250 ms; notifications are polish, not a fix.
- **`src/fs.rs` errno mapping.** The real open error is now logged, but the -ENOENT fallback is kept because the exact emscripten errno numbers for EACCES/ENOSPC/EMFILE are not verified in this codebase — do not guess them.
- **`src/gpu.rs` remaining 46 `.unwrap()` / `.expect()` sites.** Re-checked one by one after the fixes: they are get-or-create patterns (`encoder()` creates the encoder if `None`, then unwraps; `empty_bgl()` same; blit pipeline same) or immediately-preceded-by-check patterns (`tex_mut(id)` after a `tex(id)` check in the same call, `pass.as_mut()` inside the pass scope, `surface.as_ref()` in `present()` after start), static `Regex` LazyLocks over compile-time-constant patterns (a code bug, not runtime input — panics only if a literal pattern is invalid), or `try_into().unwrap()` on slices whose length was just proven by a guard/`get()`. Left alone. If the Xcode build ever shows one of these firing, it is a logic bug in the guard, not a missing check.
- **`src/proto.rs` / `src/mp.rs` `try_into().unwrap()` on packet slices.** All guarded by length checks (`STATE_SIZE` 105, Shot 28, VehLook 69, per-chunk lengths) — left alone.
- **Test asserts** (`touch_gestures.rs`, `aim.rs`, `performance.rs` — all inside `#[cfg(test)]` modules). Never run on the phone.

## 14. Verification (round 3)

- Same limits as §6: `cargo check` cannot run on this Linux VM (fails inside `objc2`, Apple-only, before muguet is checked); no `aarch64-apple-ios` target, no rustfmt, no macOS/Xcode, Swift unchecked. Every edit was verified by re-reading the diff against the surrounding code (names, fields, signatures, types). **Never claim compile-verified.** First Xcode build is the real gate — it type-checks both the Rust (iOS target) and the Swift changes, including the new `checkStartupError()` / `suspendApp()` / `foregroundKeyWindow()` Swift code and the workflow YAML.
- `git diff --stat` for the whole working tree (rounds 1+2 were pushed via the GitHub API snapshot and never committed locally, so the local diff covers all three rounds — see §15): 25 files changed, 1824 insertions, 658 deletions. The two `download-wasm.cjs` deletions (root + `tools/`, 82 lines each) are the user's ordered deletion from 2026-11-26, not round-3 work.
- After the round-3 edits, remaining `.unwrap()` / `.expect()` / `panic!` / `assert!` counts: `gpu.rs` 46 (audited, §13), `mp.rs` 9 (guarded slices + `Cmd::mem()`), `proto.rs` 7 (guarded slices), `touch_gestures.rs` 11 (all `#[cfg(test)]`), `config.rs` 5 (compile-time constant / guarded `builds.last()` / escaped regexes), `performance.rs` 6 (all `#[cfg(test)]`), `aim.rs` 3 (all `#[cfg(test)]`), `fs.rs` 1 (a comment), `app.rs` / `audio.rs` / `debug.rs` / `diagnostics.rs` / `game_data.rs` / `host.rs` / `import.rs` / `input.rs` / `io.rs` / `main.rs` / `pad.rs` / `patch.rs` / `server.rs` / `touch.rs` / `ios/Launcher.swift` 0.
- No game run, no IPA build, no `make-ios.sh`, no downloads. No game files in the repo. The workflow file on GitHub (commit `2d46280`) is untouched by this audit — the run must NOT start until the user says so.

## 15. Files changed (round 3)

- `src/gpu.rs` — bounds-checked wasm-memory access, ring validation, per-command `catch_unwind`, caps (set_obj 1M, uniform 8 chunks, viewports 16, shader nin 64, layout 64, state 4096), 2 s poll timeouts, `catch_unwind` on the GPU thread, poison-tolerant locks, `PendingMap.failed`, proxy/mip pipeline + proxy texture purge, oldest-first cache pruning.
- `src/host.rs` — RT guards, poison-tolerant locks, `exit(0)` ignored, `ios_heap_budget` in `heap_max`, saturating heap math.
- `src/main.rs` — checked arithmetic everywhere (heap, stacks, argv, memory accessors), hash-keyed `.cwasm` cache with atomic writes, 5 s unwind cap, startup-error persistence.
- `src/io.rs` — rewritten: `Option`-returning atomics, `Result` manifest, retryable start, capped slots, 16-at-a-time eviction, chunked reads.
- `src/app.rs` — poison-tolerant locks, validated scale/res, retryable window/surface, 120 s startup timeout, double-launch guard, clean-return-to-launcher, acting memory warning.
- `src/fs.rs` — fd reuse + 1024 cap, clamped `ok_i`, capped iovecs, EINVAL on short getdents, chunked reads, logged errors.
- `src/config.rs` — newest-build selection, capped shader validation, HOME bail on iOS, `locate()` propagation, iterative settings scan, clamped fps, escaped regexes.
- `src/game_data.rs` — 1M file cap, all-missing-files report.
- `src/import.rs` — zip-bomb caps, rollback-safe swap, atomic `tidy_lists`, FFI null check.
- `src/patch.rs` — checked arithmetic, `__tls_base` bail, duplicate-name warning.
- `src/diagnostics.rs` — `trim()` at install, checked `dup2`, rotating crash log, `catch_unwind` around the snapshot.
- `src/debug.rs` — saturating run counter, 1 MiB log rotation, lock-free `persist_json` throttled to 2 s.
- `src/performance.rs` — `MUGUET_HEAP_GB_MB` runtime heap knob (512–3072 MB).
- `src/mp.rs` — 66 poison-tolerant locks, retryable NET, STOP flag, no 5 s sleep stall, host-change despawn, PARKED cap + expiry, `taken` expiry, capped `send_reliable` pending.
- `src/server.rs` — dirty-flag name broadcast, 256-player cap, FULL on id exhaustion.
- `src/audio.rs` — ring validation, RT guard, retryable start, native sample rate.
- `src/input.rs` — bounds-checked BLOCK, clamped SENS, saturating mouse delta, cheat dedupe.
- `src/pad.rs` — cached, validated sensitivity statics.
- `src/touch.rs` — `env_f64()` clamping, overlay removal, `try_borrow_mut`, `BUTTONS.get()`.
- `ios/Launcher.swift` — cached ProMotion sync, foreground-scene helpers, `suspendApp()` replacing `exit(0)`, "No logs" alert, `checkStartupError()` surfacing the Rust startup-error file.
- `build.rs` — checked xcrun/swiftc with stderr, explicit toolchain-parent check, `rerun-if-changed` for entitlements/project/Cargo.toml, vendor assert.
- `make-ios.sh` — dead heap knob removed, `wasm-opt` fallback, `--locked`, `--deep --strict` codesign verify, xcodegen check, no `-quiet` on xcodebuild.
- `make-app.sh` — `--locked`, same-target-dir `muguet-server`, missing-binary errors, guarded mp3 copy.
- `.github/workflows/build-game-ipa.yml` — URL-input + SHA-256-verified download (no deleted script), 180 min timeout, pinned source SHA, real SHA in BUILD-INFO.txt, no dead heap env.
- `.github/workflows/build-ipa-archive.yml` — SHA-1-verified 20 GB download, fail-fast content check, Rust cache, opt-in Release, artifact `if-no-files-found: error`.
- `DEBUG_AUDIT.md` (this file) — this section.

## 16. What still needs the phone test

Everything in §7 still applies, plus the round-3 additions:

- **Entitlement ceiling (C5):** note whether the IPA being tested is a paid-developer build or a sideloaded one. If sideloaded, expect the crash at a footprint well under 3 GB — the debug log's `footprint` at death is the tell. A paid build with `increased-memory-limit` should survive much longer if the growth is only host-cache; if it still dies at ~2–3 min, the growth is game-owned (§1e #1–2) and no host fix will save it.
- **New log lines to watch for:** `critical purge` (purge fired under 192 MB), `uniform ring full` / draw skips (uniform cap hit), `LEAK WATCH`, `Low memory` engine error (clean stop instead of jetsam), `audio ring invalid` (bad game ring values — silent audio instead of a segfault), `surface texture unavailable`.
- **Multiplayer:** host-change despawn, room-full behaviour, and the retryable NET init can only be verified with a live multiplayer session — single-player testing covers none of it.
- **Picker / gamepad / import:** unchanged from §7, plus: after a failed config/startup, the launcher should now show the startup error text on next launch instead of silently returning to the menu.
- Still missing, asked repeatedly: iPhone model / RAM / iOS version; standing still vs driving/flying; Story vs Sandbox; freeze-then-close vs instant close; exact elapsed time to crash.
