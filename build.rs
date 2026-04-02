#[cfg(windows)]
fn build_windows() {
    let file = "src/platform/windows.cc";
    let file2 = "src/platform/windows_delete_test_cert.cc";
    cc::Build::new().file(file).file(file2).compile("windows");
    println!("cargo:rustc-link-lib=WtsApi32");
    println!("cargo:rerun-if-changed={}", file);
    println!("cargo:rerun-if-changed={}", file2);
}

#[cfg(windows)]
fn ensure_sciter_dll() {
    use std::path::{Path, PathBuf};
    use std::process::Command;

    const SCITER_DLL_URL: &str =
        "https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.win/x64/sciter.dll";

    fn release_dir_from_out_dir(out_dir: &Path) -> Option<PathBuf> {
        out_dir.parent()?.parent()?.parent().map(Path::to_path_buf)
    }

    let out_dir = std::env::var_os("OUT_DIR").map(PathBuf::from);
    let Some(out_dir) = out_dir else {
        return;
    };
    let Some(release_dir) = release_dir_from_out_dir(&out_dir) else {
        return;
    };
    let target_sciter = release_dir.join("sciter.dll");

    println!("cargo:rerun-if-env-changed=SCITER_DLL_PATH");
    println!("cargo:rerun-if-changed=sciter.dll");

    if target_sciter.exists() {
        return;
    }

    let manifest_dir = std::env::var_os("CARGO_MANIFEST_DIR").map(PathBuf::from);
    let mut candidates = Vec::new();
    if let Ok(path) = std::env::var("SCITER_DLL_PATH") {
        candidates.push(PathBuf::from(path));
    }
    if let Some(manifest_dir) = &manifest_dir {
        candidates.push(manifest_dir.join("sciter.dll"));
    }

    for candidate in candidates {
        if candidate.is_file() {
            std::fs::copy(&candidate, &target_sciter).unwrap_or_else(|err| {
                panic!(
                    "Failed to copy sciter.dll from {} to {}: {}",
                    candidate.display(),
                    target_sciter.display(),
                    err
                )
            });
            return;
        }
    }

    let download_command = format!(
        "Invoke-WebRequest -Uri '{}' -OutFile '{}'",
        SCITER_DLL_URL,
        target_sciter.display()
    );
    let status = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", &download_command])
        .status()
        .unwrap_or_else(|err| panic!("Failed to start PowerShell to download sciter.dll: {}", err));

    if !status.success() {
        panic!(
            "Failed to download sciter.dll to {}. Set SCITER_DLL_PATH or place sciter.dll in the repository root.",
            target_sciter.display()
        );
    }
}

#[cfg(target_os = "macos")]
fn build_mac() {
    let file = "src/platform/macos.mm";
    let mut b = cc::Build::new();
    if let Ok(os_version::OsVersion::MacOS(v)) = os_version::detect() {
        let v = v.version;
        if v.contains("10.14") {
            b.flag("-DNO_InputMonitoringAuthStatus=1");
        }
    }
    b.flag("-std=c++17").file(file).compile("macos");
    println!("cargo:rerun-if-changed={}", file);
}

#[cfg(all(windows, feature = "inline"))]
fn build_manifest() {
    use std::io::Write;
    if std::env::var("PROFILE").unwrap() == "release" {
        let mut res = winres::WindowsResource::new();
        res.set_icon("res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("res/manifest.xml");
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}

fn install_android_deps() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os != "android" {
        return;
    }
    let mut target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if target_arch == "x86_64" {
        target_arch = "x64".to_owned();
    } else if target_arch == "x86" {
        target_arch = "x86".to_owned();
    } else if target_arch == "aarch64" {
        target_arch = "arm64".to_owned();
    } else {
        target_arch = "arm".to_owned();
    }
    let target = format!("{}-android", target_arch);
    let vcpkg_root = std::env::var("VCPKG_ROOT").unwrap();
    let mut path: std::path::PathBuf = vcpkg_root.into();
    if let Ok(vcpkg_root) = std::env::var("VCPKG_INSTALLED_ROOT") {
        path = vcpkg_root.into();
    } else {
        path.push("installed");
    }
    path.push(target);
    println!(
        "cargo:rustc-link-search={}",
        path.join("lib").to_str().unwrap()
    );
    println!("cargo:rustc-link-lib=ndk_compat");
    println!("cargo:rustc-link-lib=oboe");
    println!("cargo:rustc-link-lib=c++");
    println!("cargo:rustc-link-lib=OpenSLES");
}

fn main() {
    hbb_common::gen_version();
    install_android_deps();
    #[cfg(all(windows, feature = "inline"))]
    build_manifest();
    #[cfg(windows)]
    build_windows();
    #[cfg(windows)]
    ensure_sciter_dll();
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os == "macos" {
        #[cfg(target_os = "macos")]
        build_mac();
        println!("cargo:rustc-link-lib=framework=ApplicationServices");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
