// Embeds the shared application icon and the PerMonitorV2 DPI manifest as
// Windows PE resources. Without the icon, Explorer, the taskbar, Alt+Tab, and
// shortcuts (`exe,0`) fall back to a generic placeholder; without the manifest,
// Windows bitmap-stretches the whole window above 100% scaling.

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let icon_path = manifest_dir
        .parent()
        .and_then(|native| native.parent())
        .map(|root| root.join("assets").join("amd-mobile-power.ico"))
        .expect("repository root");
    println!("cargo:rerun-if-changed={}", icon_path.display());
    assert!(
        icon_path.is_file(),
        "application icon is missing: {}",
        icon_path.display()
    );

    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows")
        || env::var("CARGO_CFG_TARGET_ENV").as_deref() != Ok("msvc")
    {
        return;
    }

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let rc_source = out_dir.join("app-icon.rc");
    let res_file = out_dir.join("app-icon.res");
    let escaped_icon = icon_path.display().to_string().replace('\\', "\\\\");

    let manifest_path = manifest_dir.join("app.manifest");
    println!("cargo:rerun-if-changed={}", manifest_path.display());
    assert!(
        manifest_path.is_file(),
        "application manifest is missing: {}",
        manifest_path.display()
    );
    let escaped_manifest = manifest_path.display().to_string().replace('\\', "\\\\");

    fs::write(
        &rc_source,
        format!("1 ICON \"{escaped_icon}\"\n1 24 \"{escaped_manifest}\"\n"),
    )
    .expect("write generated resource script");

    let rc = find_rc().unwrap_or_else(|| {
        panic!(
            "rc.exe was not found. Install the Windows 10/11 SDK resource compiler or set \
             the RC environment variable; a GUI without an embedded icon is a release blocker."
        )
    });

    let output = Command::new(&rc)
        .arg("/nologo")
        .arg("/fo")
        .arg(&res_file)
        .arg(&rc_source)
        .output()
        .unwrap_or_else(|error| panic!("unable to run {}: {error}", rc.display()));
    if !output.status.success() {
        panic!(
            "resource compilation failed with {}: {}{}",
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    println!("cargo:rustc-link-arg-bins={}", res_file.display());
}

fn find_rc() -> Option<PathBuf> {
    if let Ok(explicit) = env::var("RC") {
        let candidate = PathBuf::from(explicit);
        if candidate.is_file() {
            return Some(candidate);
        }
    }

    if let Some(path) = env::var_os("PATH") {
        for directory in env::split_paths(&path) {
            let candidate = directory.join("rc.exe");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    sdk_rc_candidates().into_iter().find(|path| path.is_file())
}

fn sdk_rc_candidates() -> Vec<PathBuf> {
    let mut bins = Vec::new();
    for variable in ["ProgramFiles(x86)", "ProgramFiles"] {
        if let Some(base) = env::var_os(variable) {
            bins.push(
                PathBuf::from(base)
                    .join("Windows Kits")
                    .join("10")
                    .join("bin"),
            );
        }
    }

    let mut candidates: Vec<(Vec<u64>, PathBuf)> = Vec::new();
    for bin in bins {
        let Ok(entries) = fs::read_dir(&bin) else {
            continue;
        };
        for entry in entries.flatten() {
            if !entry.path().is_dir() {
                continue;
            }
            let Ok(name) = entry.file_name().into_string() else {
                continue;
            };
            let version: Vec<u64> = name
                .split('.')
                .map(|part| part.parse::<u64>().unwrap_or(0))
                .collect();
            for arch in ["x64", "x86"] {
                let candidate = entry.path().join(arch).join("rc.exe");
                if candidate.is_file() {
                    candidates.push((version.clone(), candidate));
                }
            }
        }
    }

    candidates.sort_by(|left, right| right.0.cmp(&left.0));
    candidates.into_iter().map(|(_, path)| path).collect()
}
