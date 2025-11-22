# OpenCloud Desktop Windows Builder

This mini project lets any developer build the official [opencloud-eu/desktop](https://github.com/opencloud-eu/desktop) repository on Windows with minimal setup.

## Contents
- `build-opencloud.ps1` – automates Craft setup, dependency installation, build, and packaging (NSIS + 7z)
- `README.md` – this guide

## Requirements
- Windows 11/10 x64
- Visual Studio 2022 Build Tools  
  When running the VS Installer, select the **Desktop development with C++** workload (MSVC v143 + Windows 11 SDK).
- Git
- PowerShell (≥ 5) with internet access

## Usage
1. Clone the upstream repo:
 ```powershell
  git clone https://github.com/opencloud-eu/desktop.git
  cd desktop
  ```
2. Copy or download the `build-helper` folder into this repo (the same directory that contains the `.github` folder).
3. Run PowerShell with execution rights:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build-opencloud.ps1 -BuildNumber 1
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
├─ build-opencloud.ps1
│─ README.md
└─ (upstream repo)
```

## 🐍 Making Python3 Available on Windows (The Fix)

If you encounter the **"python3 not found"** error in build systems like Craft, Make, or CI pipelines, it's because most standard Python installations on Windows register the executable only as **`python.exe`**, while Unix-like systems (Linux/macOS) explicitly use **`python3`**.

The simplest and cleanest solution is to create a small batch file (`.bat`) that redirects the **`python3`** command to your existing **`python`** executable.

### 1\. 🔍 Find Your Python Installation Path

To place the redirection file (`python3.bat`) in the correct location, you first need to find the exact path to your **`python.exe`**.

Open **Command Prompt (CMD)** or **PowerShell** and run:

```powershell
where python
```

The output will show you the full path. For example:

> `C:\Users\YourName\AppData\Local\Programs\Python\Python310\python.exe`

### 2\. 📝 Create the `python3.bat` File

1.  Navigate to the **folder** containing the executable you just found (in the example: `C:\Users\YourName\AppData\Local\Programs\Python\Python310\`).

2.  In this folder, create a new text file and name it **`python3.bat`**.

3.  Open the file with a text editor (like Notepad) and paste the following **single command** into it:

    ```batch
    @echo off
    python %*
    ```

    *Explanation: This script tells the system that when the command `python3` is called (which Windows resolves as `python3.bat`), it should execute `python` instead, passing along all arguments (`%*`) that were originally provided.*

### 3\. ✅ Verify the Fix

Since the folder containing your `python.exe` is already in the system's **PATH** environment variable, the **`python3.bat`** file is immediately available system-wide.

  * Open a **new** console window (CMD or PowerShell).

  * Test the new command:

    ```powershell
    python3 --version
    ```

If the correct Python version is displayed, the issue is resolved, and your build script should now run without the "Python3 not found" error.

## Notes
- The first run downloads several GB of toolchains; subsequent builds reuse the cache.
- The script must reside inside the OpenCloud Desktop repo (so `.github/workflows/.craft.ps1` is available). If you zip/share `build-helper`, always drop it into the freshly cloned repo before running it.
- If Craft complains about `${Env:HOME}` (common on fresh Windows installs), set it once via `setx HOME "%USERPROFILE%"` and open a new PowerShell window.
- Installer output: `opencloud-desktop-latest-<BuildNumber>-windows-cl-msvc2022-x86_64.exe`
- Portable archive: `opencloud-desktop-latest-<BuildNumber>-windows-cl-msvc2022-x86_64.7z`



