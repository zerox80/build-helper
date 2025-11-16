# OpenCloud Desktop Windows Builder

This mini project lets any developer build the official [opencloud-eu/desktop](https://github.com/opencloud-eu/desktop) repository on Windows with minimal setup.

## Contents
- `build-opencloud.ps1` – automates Craft setup, dependency installation, build, and packaging (NSIS + 7z)
- `README.md` – this guide

## Requirements
- Windows 11/10 x64
- Visual Studio 2022 Build Tools (Desktop C++ workload)
- Git
- PowerShell (≥ 5) with internet access

## Usage
1. Clone the upstream repo:
   ```powershell
   git clone https://github.com/opencloud-eu/desktop.git
   cd desktop
   ```
2. Copy or download the `build-helper` folder into the repo.
3. Run PowerShell with execution rights:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build-helper\build-opencloud.ps1 -BuildNumber 1
   ```

The script will:
- clone/initialize CraftMaster
- set `srcDir` & build number
- install NSIS (optional via `-SkipNsis`)
- download/update dependencies
- build the project (`CRAFT_JOBS` = number of CPU cores)
- drop installer + 7z into `%USERPROFILE%\craft\binaries`

## Options
- `-BuildNumber <n>` – unique build ID (used in version/RC files)
- `-SkipSetup` – skip Craft setup if the environment already exists
- `-SkipNsis` – generate only the 7z package

## Directory layout
```
opencloud-desktop/
├─ build-helper/
│  ├─ build-opencloud.ps1
│  └─ README.md
└─ (upstream repo)
```

## Notes
- The first run downloads several GB of toolchains; subsequent builds reuse the cache.
- Installer output: `opencloud-desktop-latest-<BuildNumber>-windows-cl-msvc2022-x86_64.exe`
- Portable archive: `opencloud-desktop-latest-<BuildNumber>-windows-cl-msvc2022-x86_64.7z`
