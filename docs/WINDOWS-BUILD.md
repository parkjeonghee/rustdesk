# Windows Build Guide

This document describes a Windows build path that was validated in this repository with the native Rust desktop build.

## Scope

- Target: Windows desktop build
- Output: `target/release/rustdesk.exe`
- Build path: Rust + vcpkg
- UI path: native desktop build from `cargo build --release`

This guide does not depend on `python build.py --flutter`.

## Prerequisites

Install these tools first.

### Required

- Rust MSVC toolchain
- Visual Studio 2022 Community or Build Tools with MSVC C++ toolchain
- Git
- `winget`

### Required helper tools

Install these with `winget`:

```powershell
winget install --source winget --id LLVM.LLVM --accept-package-agreements --accept-source-agreements
winget install --source winget --id Kitware.CMake --accept-package-agreements --accept-source-agreements
winget install --source winget --id 7zip.7zip --accept-package-agreements --accept-source-agreements
winget install --source winget --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements
```

These are needed because:

- `LLVM` provides `libclang.dll` for `bindgen`
- `CMake`, `7-Zip`, and `PowerShell 7` are required by `vcpkg`

## 1. Clone the repositories

Clone RustDesk and vcpkg.

```powershell
git clone https://github.com/rustdesk/rustdesk.git
git clone https://github.com/microsoft/vcpkg.git C:\Users\myjul\vcpkg
```

Bootstrap `vcpkg`.

```powershell
& 'C:\Users\myjul\vcpkg\bootstrap-vcpkg.bat'
```

## 2. Use an ASCII-only working path

If the repository lives under a path containing non-ASCII characters, some native build steps can fail, especially inside the AOM port.

Create an ASCII-only junction and build from there.

```powershell
cmd /c mklink /J C:\rustdesk-build "C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk"
```

Then use `C:\rustdesk-build` as the working directory for the rest of the steps.

## 3. Set build environment variables

In PowerShell:

```powershell
$env:VCPKG_ROOT='C:\Users\myjul\vcpkg'
$env:VCPKG_INSTALLED_ROOT='C:\rustdesk-build\vcpkg_installed'
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
```

These are the important ones:

- `VCPKG_ROOT`: used by build scripts to resolve dependency paths
- `VCPKG_INSTALLED_ROOT`: points build scripts at the repo-local manifest install output
- `LIBCLANG_PATH`: lets `bindgen` find `libclang.dll`

## 4. Install native dependencies with vcpkg

Run this from the ASCII path:

```powershell
Set-Location C:\rustdesk-build
& 'C:\Users\myjul\vcpkg\vcpkg.exe' install
```

This repository uses manifest mode, so do not pass package names manually.

The required Windows static libraries are resolved from `vcpkg.json`, including:

- `aom`
- `libvpx`
- `libyuv`
- `opus`

## 5. Make `vcpkg\installed` available at the expected location

Some build scripts in the dependency chain expect `VCPKG_ROOT\installed\...` even when manifest mode installs packages into the repository.

Create this junction once:

```powershell
cmd /c mklink /J C:\Users\myjul\vcpkg\installed C:\rustdesk-build\vcpkg_installed
```

## 6. Build RustDesk

Run the release build from the ASCII path with the environment variables set:

```powershell
Set-Location C:\rustdesk-build
$env:VCPKG_ROOT='C:\Users\myjul\vcpkg'
$env:VCPKG_INSTALLED_ROOT='C:\rustdesk-build\vcpkg_installed'
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
cargo build --release
```

## Output

Expected executables:

- `C:\rustdesk-build\target\release\rustdesk.exe`
- `C:\rustdesk-build\target\release\service.exe`
- `C:\rustdesk-build\target\release\naming.exe`

If you are working from the original repository path instead of the junction, the same files are also visible under:

- `C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk\target\release\rustdesk.exe`
- `C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk\target\release\service.exe`
- `C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk\target\release\naming.exe`

## Launch And Connect From Web Links

The installed Windows build registers a URL Protocol, so the application can be launched from a browser or web page by clicking a `rustdesk://...` link.

This behavior is intended for the installed Windows application. If you only run a raw `cargo build` output from an arbitrary folder, the protocol may not be registered.

### Basic format

- `rustdesk://connect/<REMOTE_ID>`
- `rustdesk://control/<REMOTE_ID>`
- `rustdesk://<REMOTE_ID>`

The `control` form and the bare-ID form are both treated internally as `connect`.

Example:

```html
<a href="rustdesk://connect/123456789">Connect with RustDesk</a>
```

### Supported authorities

- `connect`
- `control`
- `file-transfer`
- `port-forward`
- `rdp`
- bare ID form

Examples:

- `rustdesk://connect/123456789`
- `rustdesk://file-transfer/123456789`
- `rustdesk://rdp/123456789`
- `rustdesk://123456789`

### Supported query parameters

- `password`: passes a connection password
- `relay=true`: forces relay mode
- `switch_uuid`: passes an internal session switch value

Example:

```text
rustdesk://connect/123456789?password=abcd&relay=true
```

### Runtime behavior

- The remote ID from the web link is converted into the existing `--connect <REMOTE_ID>` flow.
- The received remote ID is also stored as the application's last remote ID.
- If `password` is present, it is forwarded using the existing argument convention.
- If `relay=true` is present, a `--relay` argument is added.

## Common failures

### `Unable to find libclang`

Install LLVM and set:

```powershell
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
```

### `Couldn't find VCPKG_ROOT`

Set:

```powershell
$env:VCPKG_ROOT='C:\Users\myjul\vcpkg'
```

### `fatal error: 'opus/opus_multistream.h' file not found`

### `fatal error: 'vpx/vp8.h' file not found`

This usually means one of these is missing:

- `vcpkg install` has not completed successfully
- `VCPKG_INSTALLED_ROOT` is not set
- `C:\Users\myjul\vcpkg\installed` is not linked to `C:\rustdesk-build\vcpkg_installed`

### AOM fails under a Unicode path

Build from an ASCII-only path such as `C:\rustdesk-build`.

## Notes about this repository state

This repository currently includes local fixes that were needed to make the validated Windows build complete in this environment:

- `res/vcpkg/aom/portfile.cmake`
- `libs/scrap/build.rs`

Those fixes handle:

- AOM configuration under the current Windows toolchain/NASM setup
- `bindgen` output where some VPX/AOM config structs were emitted as opaque types

If those files change later, revalidate this guide.