# Muguet debug audit — crash after 2–3 runs, gamepad camera, file picker

Repo: `pentafcb/muguet-ios-build` (fork of `iOSVNNews/muguet-ios-build`),
head `3b4b7c69`, 2026-10-12. Local edits only — NOT pushed.
Date: 2026-11-26. No phone test, no IPA build, no game files used.

## 0. Is this the latest from the original creator? No.

This is **not** the latest from the original creator. The original
`c22dev/muguet` (Constantin Clerc) was taken down by a Take-Two DMCA
notice on 2026-11-18. This repo is the `iOSVNNews/muguet-ios-build`
rebuild fork, head `3b4b7c69` from 2026-10-12. There is no newer
original to pull from — everything below is fixed in this fork.

## 1. Crash after 2–3 runs — findings

### 1a. Correction to the first read-only audit

The first audit said `memory_warning` sets a flag with "no real purge".
That was wrong. `gpu.rs` `check_memory()` **does** purge: on
`MEMORY_PRESSURE` (throttled to 15 s) it flushes, waits up to 2 s for
submitted work, clears `bind_groups`, drops finished pipelines,
clears `compute`, `bgl_cache`, shader program variants and uniform
slots, then logs `memory cleanup: {before} -> {after} MB`.
`prune_graphics_cache()` also runs every 120 presents on iOS.
The problem is not "no purge" — it is that the purge fires too late
and misses several caches. The fixes below target exactly that.

### 1b. Leak suspects (file + function + why it grows)

| # | Location | Problem |
|---|----------|---------|
| 1 | `src/gpu.rs` `set_obj()` | Overwrote an old `Tex`/`Buf` without destroying it. Dropping the wrapper leaves the wgpu texture/buffer alive while cached bind groups still reference it. **Fixed**: `set_obj()` now calls the existing `destroy()` first. |
| 2 | `src/gpu.rs` `check_memory()` | Purge only ran when available memory fell under **192 MB** — close to jetsam already — and only every 15 s. **Fixed**: trigger raised to 384 MB. |
| 3 | `src/gpu.rs` `check_memory()` | Purge never cleared per-texture cached views (`Tex.views`, `ViewObj.views`), `blit_bg`, `mip_passes`, or `dummy_tex`. Each cached `TextureView` pins its texture. **Fixed**: all cleared on purge. They are rebuilt on demand (get-or-create in the view accessors, `mip_passes` at `gpu.rs:2915`). |
| 4 | `src/gpu.rs` `log_once()` / `LOGGED` | `LOGGED: HashSet<String>` only ever grew — one entry per unique warning for the whole session. **Fixed**: capped at 1024 entries (clears, then re-logs) and cleared on purge. |
| 5 | `src/main.rs` `load_module()` (jit) | Every game update wrote a new `game-<len>-<stamp>-<key>.cwasm` (multi-hundred MB) and never deleted the old ones — disk growth across runs. **Fixed**: old `game-*.cwasm` files are deleted when a new one is written, keeping only the latest. |
| 6 | `src/gpu.rs` `objs: Vec<Option<Obj>>` | Never compacts, and the host can never free a texture/buffer the game still owns by id. If the game wasm creates object ids monotonically without destroying them, live GPU objects grow for the whole session. Not directly fixable host-side — now **visible** via the leak counters (below). |
| 7 | `src/host.rs` `resize_heap()` | The wasm heap only grows, never shrinks (wasm memory cannot shrink). Growth refusals now log the run number and GPU counts (`src/debug.rs` `note_heap_refusal()`). |
| 8 | `src/main.rs` `Runtime` (`OnceLock`) + `spawn_pthread()` | Engine, module and shared memory live for the whole process; pthread `Store`+`Instance` pairs are never joined. By design — the process exits when the engine returns. |
| 9 | `src/audio.rs` `STARTED` (once-only), stream parked forever | Process-lifetime by design; the process exits at engine end, so this is not a cross-launch leak. Not changed. |
| 10 | `src/io.rs` `serve_loop()` open-file map, `MAX_OPEN = 1024` | Bounded, but when full it closes the **whole** map at once. Suspect, not changed (needs a phone repro first). |
| 11 | `src/fs.rs` `FS` open fds | Closed only on explicit `fd_close` from the game. Game-owned; not changed. |
| 12 | `src/mp.rs` `NET` peers/shots | Capped (peers 64, snaps 20 per peer) — bounded, not a suspect. |
| 13 | `src/diagnostics.rs` | No run counter, no memory history, no GPU counts; a jetsam kill is not a Rust panic so it leaves no crash log at all. **Fixed** by the debug tools below. |

### 1c. Open question (still needs the user)

It is still unknown whether "2–3 times" means 2–3 **app launches** or
2–3 **in-app game starts**, and no `muguet-runtime.log`,
`muguet-previous.log` or `muguet-crash.log` has been shared yet, nor
the iPhone model / RAM / iOS version. That matters: a fresh process per
launch rules out in-process leaks as the cross-launch cause and points
at within-session growth (suspects 1–6) or disk accumulation (suspect
5). The debug log below is designed to answer it.

## 2. Debug tools added

New module `src/debug.rs`, gated behind `MUGUET_DEBUG=1` (off by
default). Enable it before launching — there is no in-app toggle; the
flag is read at startup.

- **Run counter** — `Documents/muguet-debug.json`:
  `{"runs": N, "prev_peak_tex": T, "prev_peak_buf": B}`. Bumped on
  every launch, even with debug off, so refusals and panics can always
  name the run number.
- **Per-run log** — `Documents/muguet-debug.log`, one line per sample:
  `sample run 3 footprint 1842 MB avail 512 MB heap 1200 MB | tex live
  1234 (created 5000 destroyed 3766) | buf live 89 (created 900
  destroyed 811) | shaders 12 pipes 340 bg 1200 draws 99999 presents 12345`.
  Sampled every 5 s from `gpu.rs` `check_memory()` and on every iOS
  memory warning (`app.rs` `memory_warning()`).
- **Leak counters** — `TEX_CREATED`/`TEX_DESTROYED`,
  `BUF_CREATED`/`BUF_DESTROYED`, `SHADER_CREATED`/`SHADER_DESTROYED`
  (`src/gpu.rs`), incremented in `create_texture` / `create_buffer` /
  `create_shader` / `destroy()`. Logged every 10 s by `log_fps()` as
  `leak watch: textures live … (created … destroyed …)`. If live
  textures/buffers exceed the previous run's peak, the debug log gets
  one `LEAK WATCH: … exceed previous run peak …` line per run.
- **Panic hook** — `src/diagnostics.rs` now dumps the snapshot
  (`run | footprint | avail | heap | tex buf shaders pipes bg draws
  presents`) into `muguet-crash.log` and stderr. Note: a jetsam kill
  still leaves no crash log — that is why the 5 s samples matter.
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
   still throttled to 15 s with a 30 s / 30 FPS limit after.
3. `src/gpu.rs` `check_memory()` purge now also clears cached texture
   views, `blit_bg`, `mip_passes`, `dummy_tex`, and `LOGGED`, and logs
   how many bind groups / pipelines / views were cleared.
4. `src/gpu.rs` `log_once()` `LOGGED` set capped at 1024 entries.
5. `src/main.rs` `load_module()` deletes stale `game-*.cwasm` files,
   keeping only the latest.
6. `src/host.rs` heap-growth refusals log run number + GPU counts.

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
- No game run, no IPA build, no `make-ios.sh`. No game files
  downloaded, no GTA assets in the repo.

## 7. How to test (phone)

### Crash / memory

1. Rebuild + install the IPA from this branch (do not use the old
   Build 8.9 IPA — it has none of this).
2. Play 2–3 sessions the way it used to crash (note whether the crash
   is after 2–3 **app launches** or 2–3 **in-app starts** — that
   distinction is still missing).
3. In Files > Muguet, share `muguet-debug.log`,
   `muguet-runtime.log`, `muguet-previous.log` and `muguet-crash.log`
   (or use the launcher "Share startup / memory logs" button, which
   now includes `muguet-debug.log`).
4. In `muguet-debug.log`, check: does `tex live` / `buf live` climb
   every session while `created − destroyed` stays near zero (game
   leaking ids), or does `created` climb while `destroyed` lags (host
   not freeing)? A `LEAK WATCH` line means live counts beat the
   previous run's peak.

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
  watch, snapshot, pad logging, Swift bridge.
- `src/main.rs` — `mod debug`, `debug::init()`, stale `.cwasm`
  cleanup in `load_module()`.
- `src/diagnostics.rs` — panic hook dumps run + memory + GPU counts.
- `src/app.rs` — `memory_warning()` samples + logs the snapshot.
- `src/host.rs` — heap-growth refusals log run + GPU counts.
- `src/gpu.rs` — leak counters, `set_obj()` destroys the old object,
  `LOGGED` capped at 1024, purge trigger 192 → 384 MB, purge clears
  cached views / `blit_bg` / `mip_passes` / `dummy_tex` / `LOGGED`
  and logs what was cleared, `log_fps()` leak line.
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
