// muguet - audio.rs
// Constantin Clerc (c22dev) - 0.1

use crate::RT;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};

static UNDERRUN_FRAMES: AtomicU64 = AtomicU64::new(0);
static CALLBACKS: AtomicU64 = AtomicU64::new(0);

static STARTED: AtomicBool = AtomicBool::new(false);

pub fn start(ring: u64, capacity: u32) {
    // STARTED used to latch true before play() ran, so one transient
    // failure (no device, wrong sample rate, bad ring) muted the app
    // for the rest of the session with no retry. Latch only on
    // success; a failed attempt clears it so the next publish retries.
    if std::env::var("MUGUET_MUTE").is_ok() {
        return;
    }
    if STARTED.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
        return;
    }
    if let Err(e) = std::thread::Builder::new()
        .name("audio".into())
        .spawn(move || match play(ring, capacity) {
            Ok(stream) => {
                eprintln!("[audio] CoreAudio output started (ring 0x{ring:x}, {capacity} frames)");
                let _keep = stream;
                loop { std::thread::park(); }
            }
            Err(e) => {
                STARTED.store(false, Ordering::SeqCst);
                eprintln!("[audio] no output: {e:#}");
            }
        })
    {
        STARTED.store(false, Ordering::SeqCst);
        eprintln!("[audio] failed to spawn audio thread: {e}");
    }
}

fn play(ring: u64, capacity: u32) -> anyhow::Result<cpal::Stream> {
    let host = cpal::default_host();
    let device = host.default_output_device().ok_or_else(|| anyhow::anyhow!("no default output device"))?;
    let Some(rt) = RT.get() else { return Err(anyhow::anyhow!("runtime not ready")); };
    let (base, mem_len) = crate::mem_base_len(&rt.mem);
    // Validate the game-controlled ring BEFORE the realtime callback
    // ever dereferences it. capacity 0 or non-power-of-two made the
    // mask wrap (mask = capacity - 1) and read up to ~8 GB past the
    // ring — a segfault inside the audio callback. An invalid ring
    // now means silent audio, not a crash.
    if capacity == 0 || !capacity.is_power_of_two() {
        return Err(anyhow::anyhow!("bad audio ring capacity {capacity}"));
    }
    if (ring as usize).checked_add(64 + capacity as usize * 8).filter(|e| *e <= mem_len).is_none() {
        return Err(anyhow::anyhow!("audio ring 0x{ring:x} outside wasm memory"));
    }
    // Sample rate: the old code hardcoded 48 kHz stereo and failed on
    // any output that rejects it (Bluetooth, USB, AirPlay). Prefer the
    // device's native config; fall back to 48 kHz stereo.
    let config = match device.default_output_config() {
        Ok(c) => {
            let mut cfg: cpal::StreamConfig = c.into();
            cfg.channels = 2;
            cfg.buffer_size = cpal::BufferSize::Default;
            cfg
        }
        Err(_) => cpal::StreamConfig { channels: 2, sample_rate: 48000, buffer_size: cpal::BufferSize::Default },
    };
    let rate = config.sample_rate;
    let base = base as usize;
    let hdr = move |i: usize| -> &'static AtomicI32 { unsafe { &*((base + ring as usize + 4 * i) as *const AtomicI32) } };
    let data = base + ring as usize + 64;
    let mask = capacity.wrapping_sub(1);
    let stream = device.build_output_stream(
        config,
        move |out: &mut [f32], _| {
            let frames = out.len() / 2;
            let read = hdr(1).load(Ordering::SeqCst) as u32;
            let write = hdr(0).load(Ordering::SeqCst) as u32;
            let take = (write.wrapping_sub(read) as usize).min(frames);
            for i in 0..take {
                let at = ((read.wrapping_add(i as u32) & mask) * 2) as usize;
                unsafe {
                    let p = (data as *const f32).add(at);
                    out[2 * i] = *p;
                    out[2 * i + 1] = *p.add(1);
                }
            }
            for s in &mut out[take * 2..] { *s = 0.0; }
            UNDERRUN_FRAMES.fetch_add((frames - take) as u64, Ordering::Relaxed);
            CALLBACKS.fetch_add(1, Ordering::Relaxed);
            hdr(1).store(read.wrapping_add(take as u32) as i32, Ordering::SeqCst);
            hdr(3).fetch_add(1, Ordering::SeqCst);
        },
        |e| eprintln!("[audio] stream error: {e}"),
        None,
    )?;
    stream.play()?;

    std::thread::spawn(move || {
        let mut last_w = hdr(0).load(Ordering::SeqCst) as u32;
        let mut last_u = 0;
        let mut last_c = 0;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(5));
            let w = hdr(0).load(Ordering::SeqCst) as u32;
            let (u, c) = (UNDERRUN_FRAMES.load(Ordering::Relaxed), CALLBACKS.load(Ordering::Relaxed));
            eprintln!("[audio] mixer produced {:.0} frames/s (needs {}), underrun {:.0} frames/s, {} callbacks/s, ring fill {}",
                w.wrapping_sub(last_w) as f64 / 5.0, rate, (u - last_u) as f64 / 5.0, (c - last_c) / 5, w.wrapping_sub(hdr(1).load(Ordering::SeqCst) as u32));
            last_w = w; last_u = u; last_c = c;
        }
    });
    Ok(stream)
}
