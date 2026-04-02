# Windows 빌드 가이드

이 문서는 이 저장소에서 네이티브 Rust 데스크톱 빌드로 검증한 Windows 빌드 경로를 설명합니다.

## 범위

- 대상: Windows 데스크톱 빌드
- 산출물: `target/release/rustdesk.exe`
- 빌드 경로: Rust + vcpkg
- UI 경로: `cargo build --release`로 만드는 네이티브 데스크톱 빌드

이 가이드는 `python build.py --flutter`에 의존하지 않습니다.

## 사전 준비

먼저 아래 도구를 설치합니다.

### 필수

- Rust MSVC toolchain
- Visual Studio 2022 Community 또는 MSVC C++ toolchain이 포함된 Build Tools
- Git
- `winget`

### 필수 보조 도구

아래 명령으로 설치합니다.

```powershell
winget install --source winget --id LLVM.LLVM --accept-package-agreements --accept-source-agreements
winget install --source winget --id Kitware.CMake --accept-package-agreements --accept-source-agreements
winget install --source winget --id 7zip.7zip --accept-package-agreements --accept-source-agreements
winget install --source winget --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements
```

이 도구들이 필요한 이유는 다음과 같습니다.

- `LLVM`은 `bindgen`이 사용하는 `libclang.dll`을 제공합니다.
- `CMake`, `7-Zip`, `PowerShell 7`은 `vcpkg`에 필요합니다.

## 1. 저장소 클론

RustDesk와 vcpkg를 클론합니다.

```powershell
git clone https://github.com/rustdesk/rustdesk.git
git clone https://github.com/microsoft/vcpkg.git C:\Users\myjul\vcpkg
```

그다음 `vcpkg`를 bootstrap 합니다.

```powershell
& 'C:\Users\myjul\vcpkg\bootstrap-vcpkg.bat'
```

## 2. ASCII 전용 작업 경로 사용

저장소 경로에 비 ASCII 문자가 포함되어 있으면, 일부 네이티브 빌드 단계가 실패할 수 있습니다. 특히 AOM port 내부에서 문제가 날 수 있습니다.

ASCII 문자만 포함된 junction을 만들어 그 경로에서 빌드합니다.

```powershell
cmd /c mklink /J C:\rustdesk-build "C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk"
```

이후 단계에서는 `C:\rustdesk-build`를 작업 디렉터리로 사용합니다.

## 3. 빌드 환경 변수 설정

PowerShell에서 아래 값을 설정합니다.

```powershell
$env:VCPKG_ROOT='C:\Users\myjul\vcpkg'
$env:VCPKG_INSTALLED_ROOT='C:\rustdesk-build\vcpkg_installed'
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
```

중요한 변수는 다음과 같습니다.

- `VCPKG_ROOT`: 빌드 스크립트가 의존성 경로를 해석할 때 사용합니다.
- `VCPKG_INSTALLED_ROOT`: 저장소 로컬 manifest install 출력 경로를 빌드 스크립트에 알려줍니다.
- `LIBCLANG_PATH`: `bindgen`이 `libclang.dll`을 찾을 수 있게 합니다.

## 4. vcpkg로 네이티브 의존성 설치

ASCII 경로에서 아래 명령을 실행합니다.

```powershell
Set-Location C:\rustdesk-build
& 'C:\Users\myjul\vcpkg\vcpkg.exe' install
```

이 저장소는 manifest mode를 사용하므로 패키지 이름을 수동으로 넘기지 않습니다.

필요한 Windows 정적 라이브러리는 `vcpkg.json`에서 해결되며, 예를 들면 다음이 포함됩니다.

- `aom`
- `libvpx`
- `libyuv`
- `opus`

## 5. `vcpkg\installed` 경로 연결

의존성 체인 안의 일부 빌드 스크립트는 manifest mode가 패키지를 저장소 안에 설치하더라도 `VCPKG_ROOT\installed\...` 경로를 기대합니다.

아래 junction을 한 번 생성합니다.

```powershell
cmd /c mklink /J C:\Users\myjul\vcpkg\installed C:\rustdesk-build\vcpkg_installed
```

## 6. RustDesk 빌드

환경 변수를 설정한 상태에서 ASCII 경로에서 release 빌드를 실행합니다.

```powershell
Set-Location C:\rustdesk-build
$env:VCPKG_ROOT='C:\Users\myjul\vcpkg'
$env:VCPKG_INSTALLED_ROOT='C:\rustdesk-build\vcpkg_installed'
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
cargo build --release
```

## 산출물

예상되는 실행 파일은 다음과 같습니다.

- `C:\rustdesk-build\target\release\rustdesk.exe`
- `C:\rustdesk-build\target\release\service.exe`
- `C:\rustdesk-build\target\release\naming.exe`

junction이 아닌 원래 저장소 경로에서 작업 중이라면 동일한 파일이 아래 위치에서도 보입니다.

- `C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk\target\release\rustdesk.exe`
- `C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk\target\release\service.exe`
- `C:\Users\myjul\OneDrive\ドキュメント\workspace\rustdesk\target\release\naming.exe`

## 웹 링크를 통한 앱 실행 및 연결

Windows 설치본은 URL Protocol을 등록하므로, 브라우저나 웹 페이지에서 `rustdesk://...` 링크를 클릭해 앱을 실행할 수 있습니다.

이 기능은 설치된 Windows 앱을 기준으로 동작합니다. 일반 `cargo build` 산출물을 임의 폴더에서 직접 실행하는 경우에는 프로토콜 등록이 되어 있지 않을 수 있습니다.

### 기본 형식

- `rustdesk://connect/<REMOTE_ID>`
- `rustdesk://control/<REMOTE_ID>`
- `rustdesk://<REMOTE_ID>`

`control`과 ID만 있는 형식은 내부적으로 `connect`로 처리됩니다.

예:

```html
<a href="rustdesk://connect/123456789">RustDesk로 연결</a>
```

### 지원되는 authority

- `connect`
- `control`
- `file-transfer`
- `port-forward`
- `rdp`
- ID만 지정한 형식

예:

- `rustdesk://connect/123456789`
- `rustdesk://file-transfer/123456789`
- `rustdesk://rdp/123456789`
- `rustdesk://123456789`

### 지원되는 쿼리 파라미터

- `password`: 연결 암호를 전달합니다.
- `relay=true`: 강제로 relay 연결을 사용합니다.
- `switch_uuid`: 내부 세션 전환용 값을 전달합니다.

예:

```text
rustdesk://connect/123456789?password=abcd&relay=true
```

### 동작 규칙

- 웹 링크로 전달된 원격 ID는 기존 `--connect <REMOTE_ID>` 흐름으로 변환됩니다.
- 전달된 원격 ID는 앱의 최근 원격 ID 설정에도 저장됩니다.
- `password`가 있으면 기존 인자 규칙에 따라 연결 인자로 전달됩니다.
- `relay=true`가 있으면 `--relay` 인자가 추가됩니다.

## 자주 발생하는 실패

### `Unable to find libclang`

LLVM을 설치하고 아래 값을 설정합니다.

```powershell
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
```

### `Couldn't find VCPKG_ROOT`

아래 값을 설정합니다.

```powershell
$env:VCPKG_ROOT='C:\Users\myjul\vcpkg'
```

### `fatal error: 'opus/opus_multistream.h' file not found`

### `fatal error: 'vpx/vp8.h' file not found`

보통 아래 항목 중 하나가 빠졌다는 뜻입니다.

- `vcpkg install`이 정상적으로 끝나지 않았습니다.
- `VCPKG_INSTALLED_ROOT`가 설정되지 않았습니다.
- `C:\Users\myjul\vcpkg\installed`가 `C:\rustdesk-build\vcpkg_installed`에 연결되어 있지 않습니다.

### Unicode 경로에서 AOM 빌드 실패

`C:\rustdesk-build` 같은 ASCII 전용 경로에서 빌드합니다.

## 현재 저장소 상태에 대한 참고

이 저장소에는 현재 환경에서 검증된 Windows 빌드를 완료하기 위해 필요했던 로컬 수정이 포함되어 있습니다.

- `res/vcpkg/aom/portfile.cmake`
- `libs/scrap/build.rs`

이 수정은 다음 문제를 처리합니다.

- 현재 Windows toolchain/NASM 조합에서의 AOM 설정 문제
- 일부 VPX/AOM 설정 구조체가 `bindgen`에서 opaque type으로 생성되는 문제

이 파일들이 나중에 변경되면 이 가이드를 다시 검증해야 합니다.