// muguet - build.rs
// Constantin Clerc (c22dev) - 0.1

use std::process::Command;

fn main() {
    println!("cargo::rustc-check-cfg=cfg(game_code)");
    println!("cargo:rerun-if-env-changed=MUGUET_GAME_CODE");
    if std::env::var("MUGUET_GAME_CODE").is_ok_and(|p| std::path::Path::new(&p).is_file()) {
        println!("cargo:rustc-cfg=game_code");
    }
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("ios") {
        return;
    }
    println!("cargo:rustc-link-arg-bins=-Wl,-segprot,__GAME,rx,rx");

    println!("cargo:rerun-if-changed=ios/Launcher.swift");
    // Changes to these used to leave a stale Swift static lib behind.
    println!("cargo:rerun-if-changed=ios/Muguet.entitlements");
    println!("cargo:rerun-if-changed=ios/Muguet-free.entitlements");
    println!("cargo:rerun-if-changed=ios/Muguet-sideload.entitlements");
    println!("cargo:rerun-if-changed=ios/project.yml");
    println!("cargo:rerun-if-changed=Cargo.toml");
    // The wgpu-core patch points at vendor/; a checkout without it
    // used to fail later with an opaque patch error.
    assert!(std::path::Path::new("vendor/wgpu-core/Cargo.toml").is_file(),
        "vendor/wgpu-core is missing: this checkout is incomplete, re-clone the repo");
    let out = std::env::var("OUT_DIR").expect("cargo did not set OUT_DIR");
    let xcrun = |args: &[&str]| {
        // xcrun's exit status used to be ignored, so a failed SDK
        // lookup produced an empty path and a confusing failure
        // downstream; non-UTF8 output panicked instead of reporting.
        let o = Command::new("xcrun").args(args).output().expect("failed to run xcrun (is Xcode selected? try: sudo xcode-select -s /Applications/Xcode.app)");
        if !o.status.success() {
            panic!("xcrun {} failed (exit {}): {}", args.join(" "), o.status, String::from_utf8_lossy(&o.stderr).trim());
        }
        String::from_utf8_lossy(&o.stdout).trim().to_string()
    };
    let sdk = xcrun(&["--sdk", "iphoneos", "--show-sdk-path"]);
    let swiftc = xcrun(&["--sdk", "iphoneos", "-f", "swiftc"]);
    let output = Command::new(&swiftc)
        .args(["-parse-as-library", "-emit-library", "-static", "-O", "-module-name", "MuguetLauncher"])
        .args(["-target", "arm64-apple-ios15.0", "-sdk", &sdk])
        .arg("ios/Launcher.swift")
        .arg("-o")
        .arg(format!("{out}/libmuguetlauncher.a"))
        .output()
        .expect("failed to run swiftc");
    assert!(output.status.success(), "swiftc failed: {}", String::from_utf8_lossy(&output.stderr).trim());
    println!("cargo:rustc-link-search=native={out}");
    println!("cargo:rustc-link-lib=static=muguetlauncher");

    println!("cargo:rustc-link-search=native={sdk}/usr/lib/swift");
    let swiftc_path = std::path::Path::new(&swiftc);
    let toolchain = swiftc_path.parent().and_then(|p| p.parent())
        .map(|p| p.join("lib/swift/iphoneos"))
        .expect("swiftc path has no toolchain parent (expected <Toolchain>/usr/bin/swiftc)");
    println!("cargo:rustc-link-search=native={}", toolchain.display());
}
