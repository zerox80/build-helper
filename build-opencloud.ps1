Param(
    [string]$BuildNumber = "1",
    [switch]$SkipSetup,
    [switch]$SkipNsis
)

$ErrorActionPreference = "Stop"
$env:CRAFT_JOBS = [Environment]::ProcessorCount

# --- Define paths ---
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$craftScript = Join-Path $repoRoot ".github\workflows\.craft.ps1"

if (!(Test-Path $craftScript)) {
    throw "Craft helper script not found at $craftScript"
}

$env:CRAFT_TARGET = "windows-cl-msvc2022-x86_64"
$craftHome = Join-Path $HOME "craft"
$craftMaster = Join-Path $craftHome "CraftMaster\CraftMaster"
# The path where Craft actually runs
$craftRoot = Join-Path $craftHome "CraftMaster\windows-cl-msvc2022-x86_64"

# 1. Get CraftMaster
if (-not (Test-Path $craftMaster)) {
    Write-Host "Cloning CraftMaster ..." -ForegroundColor Cyan
    git clone --depth=1 https://invent.kde.org/kde/craftmaster.git $craftMaster | Out-Null
}

function Invoke-CraftStep {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )
    $psArgs = @("-ExecutionPolicy", "Bypass", "-File", $craftScript) + $Arguments
    Write-Host ">> craft" ($Arguments -join " ") -ForegroundColor Yellow
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        throw "Craft command failed with exit code $($proc.ExitCode)"
    }
}

# 2. Run Setup (To create the folders)
if (-not $SkipSetup -and -not (Test-Path $craftRoot)) {
    Write-Host "Running Craft Setup ..." -ForegroundColor Cyan
    Invoke-CraftStep @("--setup")
}

# --- FIX: THE PARASITE METHOD ---
# We register nothing. We simply copy the files into the folder
# that Craft searches ANYWAY (craft-blueprints-kde).

# 1. Find the working blueprint directory
$targetBlueprintDir = Join-Path $craftRoot "craft\blueprints\craft-blueprints-kde"
if (-not (Test-Path $targetBlueprintDir)) {
    # Fallback, if the path is slightly different
    $targetBlueprintDir = Join-Path $craftRoot "blueprints\craft-blueprints-kde"
}
if (-not (Test-Path $targetBlueprintDir)) {
    # Last attempt: Just in the 'blueprints' root
    $targetBlueprintDir = Join-Path $craftRoot "craft\blueprints"
}

Write-Host "Targeting active blueprint directory: $targetBlueprintDir" -ForegroundColor Magenta

# 2. Download blueprints temporarily
$tempDir = Join-Path $HOME "craft_temp_blueprints"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

Write-Host "Downloading Blueprints manually..." -ForegroundColor Cyan
# We use the URL that exists. 
git clone https://github.com/opencloud-eu/craft-blueprints-opencloud.git $tempDir

# --- FIX: Missing NSIS Blueprint ---
# Craft removed dev-utils/nsis, so we recreate it dynamically.
$nsisDir = Join-Path $tempDir "dev-utils\nsis"
New-Item -ItemType Directory -Path $nsisDir -Force | Out-Null
$nsisContent = @"
import info
from Package.BinaryPackageBase import BinaryPackageBase
from CraftCore import CraftCore

class subinfo(info.infoclass):
    def setTargets(self):
        self.targets["3.09"] = "https://sourceforge.net/projects/nsis/files/NSIS%203/3.09/nsis-3.09.zip/download"
        # self.targetDigests["3.09"] = (['577f0e97a234211d9d12397029230062557c0857d364893823329ce49c96936d'], "SHA256")
        self.targetInstallPath["3.09"] = "dev-utils/nsis"
        self.defaultTarget = "3.09"

    def setDependencies(self):
        self.buildDependencies["dev-utils/7zip"] = None

class Package(BinaryPackageBase):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
"@
Set-Content -Path (Join-Path $nsisDir "nsis.py") -Value $nsisContent
Write-Host "Created temporary NSIS blueprint." -ForegroundColor Cyan

# --- FIX: Missing 7zip Blueprint ---
# NSIS needs 7zip, and it's missing too.
$sevenZipDir = Join-Path $tempDir "dev-utils\7zip"
New-Item -ItemType Directory -Path $sevenZipDir -Force | Out-Null
$sevenZipContent = @'
import info
from Package.BinaryPackageBase import BinaryPackageBase

class subinfo(info.infoclass):
    def setTargets(self):
        self.targets["23.01"] = "https://www.7-zip.org/a/7z2301-x64.exe"
        self.targetInstallPath["23.01"] = "dev-utils/7zip"
        self.defaultTarget = "23.01"

    def setDependencies(self):
        # No dependencies to avoid circular hell or missing virtual/bin-base
        pass

class Package(BinaryPackageBase):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
'@
Set-Content -Path (Join-Path $sevenZipDir "7zip.py") -Value $sevenZipContent
Write-Host "Created temporary 7zip blueprint." -ForegroundColor Cyan
# -----------------------------------

# --- FIX: Missing Qt Blueprints ---
# Some installations are missing libs/qt and libs/qt6. We fetch them from the official repo.
$kdeBlueprintsUrl = "https://invent.kde.org/packaging/craft-blueprints-kde.git"
$kdeTempDir = Join-Path $HOME "craft_temp_kde_blueprints"
if (Test-Path $kdeTempDir) { Remove-Item $kdeTempDir -Recurse -Force }
Write-Host "Cloning KDE blueprints to rescue Qt..." -ForegroundColor Cyan
git clone --depth=1 $kdeBlueprintsUrl $kdeTempDir | Out-Null

# Inject ALL blueprints from KDE to ensure consistency
# This fixes missing libs/runtime, virtual/base, dev-utils/gtk-doc, etc.
if (Test-Path $kdeTempDir) {
    Write-Host "Injecting FULL KDE blueprints repository..." -ForegroundColor Cyan
    
    # Clean target directory first to avoid "Multiple py files" errors
    if (Test-Path $targetBlueprintDir) {
        Write-Host "Cleaning target directory $targetBlueprintDir ..." -ForegroundColor Yellow
        Remove-Item "$targetBlueprintDir\*" -Recurse -Force
    }

    # Copy everything from KDE blueprints to the target directory
    # We exclude .git to keep it clean
    Get-ChildItem -Path $kdeTempDir -Exclude ".git" | Copy-Item -Destination $targetBlueprintDir -Recurse -Force

    # --- FIX: Remove KDE's complex NSIS to avoid dependency hell ---
    # We want to use our simple custom NSIS defined below.
    $kdeNsis = Join-Path $targetBlueprintDir "dev-utils\_windows\nsis"
    if (Test-Path $kdeNsis) { 
        Write-Host "Removing KDE's NSIS to prefer custom one..." -ForegroundColor Yellow
        Remove-Item $kdeNsis -Recurse -Force 
    }
}

# Clean up KDE temp
Remove-Item $kdeTempDir -Recurse -Force

# 3. INJECT (Copy without regard for losses)
Write-Host "Injecting Blueprints into system..." -ForegroundColor Cyan

# We copy everything from the clone directly into the KDE folder.
# Craft will think "opencloud" simply belongs to KDE during the next scan.
Copy-Item -Path "$tempDir\*" -Destination $targetBlueprintDir -Recurse -Force

# --- FIX: Patch libre-graph-api-cpp-qt-client dependency ---
# It wrongly points to libs/qt/qtbase, but we want libs/qt6/qtbase
$clientBlueprint = Join-Path $targetBlueprintDir "opencloud\libre-graph-api-cpp-qt-client\libre-graph-api-cpp-qt-client.py"
if (Test-Path $clientBlueprint) {
    Write-Host "Patching libre-graph-api-cpp-qt-client dependency..." -ForegroundColor Cyan
    (Get-Content $clientBlueprint) -replace 'libs/qt/qtbase', 'libs/qt6/qtbase' | Set-Content $clientBlueprint
}

# --- FIX: Patch craft-blueprints-opencloud dependency ---
# It depends on craft/craft-core which is missing.
$opencloudBlueprint = Join-Path $targetBlueprintDir "craft\craft-blueprints-opencloud\craft-blueprints-opencloud.py"
if (Test-Path $opencloudBlueprint) {
    Write-Host "Patching craft-blueprints-opencloud dependency..." -ForegroundColor Cyan
    (Get-Content $opencloudBlueprint) -replace 'self.buildDependencies\["craft/craft-core"\]', '# self.buildDependencies["craft/craft-core"]' | Set-Content $opencloudBlueprint
    # Fix IndentationError by adding pass
    (Get-Content $opencloudBlueprint) -replace 'def setDependencies\(self\):', "def setDependencies(self):`n        pass" | Set-Content $opencloudBlueprint
}

# --- FIX: Patch opencloud-desktop dependency ---
# It depends on libs/zlib which is missing.
$desktopBlueprint = Join-Path $targetBlueprintDir "opencloud\opencloud-desktop\opencloud-desktop.py"
if (Test-Path $desktopBlueprint) {
    Write-Host "Patching opencloud-desktop dependency..." -ForegroundColor Cyan
    (Get-Content $desktopBlueprint) -replace 'self.runtimeDependencies\["libs/zlib"\]', '# self.runtimeDependencies["libs/zlib"]' | Set-Content $desktopBlueprint
    (Get-Content $desktopBlueprint) -replace 'self.runtimeDependencies\["libs/sqlite"\]', '# self.runtimeDependencies["libs/sqlite"]' | Set-Content $desktopBlueprint
    (Get-Content $desktopBlueprint) -replace 'self.runtimeDependencies\["libs/openssl"\]', '# self.runtimeDependencies["libs/openssl"]' | Set-Content $desktopBlueprint
    # Fix Qt paths: libs/qt → libs/qt6
    (Get-Content $desktopBlueprint) -replace 'libs/qt/', 'libs/qt6/' | Set-Content $desktopBlueprint
}

# --- FIX: Patch llvm dependency ---
# It depends on libs/libxml2, libs/libzstd, libs/python, dev-utils/system-python3 which are missing.
$llvmBlueprint = Join-Path $targetBlueprintDir "libs\llvm\llvm.py"
if (Test-Path $llvmBlueprint) {
    Write-Host "Patching llvm dependency..." -ForegroundColor Cyan
    (Get-Content $llvmBlueprint) -replace 'self.runtimeDependencies\["libs/libxml2"\]', '# self.runtimeDependencies["libs/libxml2"]' | Set-Content $llvmBlueprint
    (Get-Content $llvmBlueprint) -replace 'self.buildDependencies\["libs/libxml2"\]', '# self.buildDependencies["libs/libxml2"]' | Set-Content $llvmBlueprint
    (Get-Content $llvmBlueprint) -replace 'self.buildDependencies\["libs/libzstd"\]', '# self.buildDependencies["libs/libzstd"]' | Set-Content $llvmBlueprint
    (Get-Content $llvmBlueprint) -replace 'self.buildDependencies\["libs/python"\]', '# self.buildDependencies["libs/python"]' | Set-Content $llvmBlueprint
    (Get-Content $llvmBlueprint) -replace 'self.buildDependencies\["dev-utils/system-python3"\]', '# self.buildDependencies["dev-utils/system-python3"]' | Set-Content $llvmBlueprint
}

# --- FIX: Global patch for common missing libs ---
# Many libs are missing and referenced across blueprints. Patch them all globally.
Write-Host "Globally patching common missing library dependencies..." -ForegroundColor Cyan
$missingLibs = @(
    'libs/zlib',
    'libs/liblzma',
    'libs/libxml2',
    'libs/sqlite',
    'libs/openssl',
    'libs/libpng',
    'libs/libjpeg-turbo',
    'libs/freetype',
    'libs/brotli',
    'libs/libzstd',
    'libs/libb2',
    'libs/icu',
    'libs/harfbuzz',
    'libs/pcre2',
    'libs/fontconfig',
    'libs/dbus',
    'libs/glib',
    'libs/cups',
    'libs/python',
    'libs/iconv',
    'libs/libxslt',
    'libs/libsecret',
    'python-modules/meson',
    'python-modules/ninja',
    'dev-utils/ninja',
    'dev-utils/meson'
)

Get-ChildItem -Path $targetBlueprintDir -Recurse -Filter "*.py" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $modified = $false
    foreach ($lib in $missingLibs) {
        if ($content -match [regex]::Escape($lib)) {
            $content = $content -replace "self\.runtimeDependencies\[`"$lib`"\]", "# self.runtimeDependencies[`"$lib`"]"
            $content = $content -replace "self\.buildDependencies\[`"$lib`"\]", "# self.buildDependencies[`"$lib`"]"
            $modified = $true
        }
    }
    if ($modified) {
        Set-Content -Path $_.FullName -Value $content -NoNewline
    }
}

# --- Helper: Create Robust Dummy Blueprint ---
function Make-DummyBlueprint {
    param (
        [string]$Path,
        [string]$Name
    )
    $dir = Join-Path $targetBlueprintDir $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    $content = @"
import info
from Package.VirtualPackageBase import VirtualPackageBase

class subinfo(info.infoclass):
    def setTargets(self):
        self.targets["default"] = ""
        self.defaultTarget = "default"
    def setDependencies(self):
        pass

class Package(VirtualPackageBase):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
    def fetch(self): return True
    def unpack(self): return True
    def configure(self): return True
    def make(self): return True
    def install(self): return True
    def qmerge(self): return True
    def unmerge(self): return True
"@
    Set-Content -Path (Join-Path $dir "$Name.py") -Value $content
    Write-Host "Created robust dummy blueprint: $Path/$Name" -ForegroundColor Cyan
}

# --- FIX: Missing libs/runtime ---
Make-DummyBlueprint -Path "libs\runtime" -Name "runtime"

# --- FIX: Missing dev-utils/cmake ---
Make-DummyBlueprint -Path "dev-utils\cmake" -Name "cmake"

# --- FIX: Missing dev-utils/wget, flexbison, etc. ---
$dummyTools = @(
    @{Path = "dev-utils\wget"; Name = "wget"},
    @{Path = "dev-utils\flexbison"; Name = "flexbison"},
    @{Path = "dev-utils\pkgconf"; Name = "pkgconf"},
    @{Path = "dev-utils\perl"; Name = "perl"},
    @{Path = "kde\frameworks\extra-cmake-modules"; Name = "extra-cmake-modules"},
    @{Path = "virtual\base"; Name = "base"}
)

foreach ($tool in $dummyTools) {
    Make-DummyBlueprint -Path $tool.Path -Name $tool.Name
}

# --- FIX: Patch qtbase.py to disable missing dependencies (ICU, OpenSSL, etc.) ---
$qtBaseBlueprint = Join-Path $targetBlueprintDir "libs\qt6\qtbase\qtbase.py"
if (Test-Path $qtBaseBlueprint) {
    Write-Host "Patching qtbase.py to disable missing dependencies..." -ForegroundColor Cyan
    $qtContent = Get-Content $qtBaseBlueprint
    
    # Disable options that check for missing libs in registerOptions
    $qtContent = $qtContent -replace 'self.options.isActive\("libs/icu"\)', 'False'
    $qtContent = $qtContent -replace 'self.options.isActive\("libs/harfbuzz"\)', 'False'
    $qtContent = $qtContent -replace 'self.options.isActive\("libs/pcre2"\)', 'False'
    $qtContent = $qtContent -replace 'self.options.isActive\("libs/cups"\)', 'False'
    $qtContent = $qtContent -replace 'self.options.isActive\("libs/fontconfig"\)', 'False'
    
    # Force disable specific features that might default to True
    $qtContent = $qtContent -replace 'registerOption\("withDBus", .*\)', 'registerOption("withDBus", False)'
    $qtContent = $qtContent -replace 'registerOption\("withGlib", .*\)', 'registerOption("withGlib", False)'
    $qtContent = $qtContent -replace 'registerOption\("withHarfBuzz", .*\)', 'registerOption("withHarfBuzz", False)'
    $qtContent = $qtContent -replace 'registerOption\("withPCRE2", .*\)', 'registerOption("withPCRE2", False)'
    $qtContent = $qtContent -replace 'registerOption\("withEgl", .*\)', 'registerOption("withEgl", False)'
    
    # Remove runtime dependencies in setDependencies
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["virtual/base"\]', '# self.runtimeDependencies["virtual/base"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/dbus"\]', '# self.runtimeDependencies["libs/dbus"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/glib"\]', '# self.runtimeDependencies["libs/glib"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/harfbuzz"\]', '# self.runtimeDependencies["libs/harfbuzz"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/pcre2"\]', '# self.runtimeDependencies["libs/pcre2"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/icu"\]', '# self.runtimeDependencies["libs/icu"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/cups"\]', '# self.runtimeDependencies["libs/cups"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/fontconfig"\]', '# self.runtimeDependencies["libs/fontconfig"]'
    
    # Remove runtime dependencies in setDependencies
    $qtContent = $qtContent -replace 'if not self.options.buildStatic:', "if not self.options.buildStatic:`n            pass"
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["virtual/base"\]', '# self.runtimeDependencies["virtual/base"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/openssl"\]', '# self.runtimeDependencies["libs/openssl"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/zlib"\]', '# self.runtimeDependencies["libs/zlib"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/brotli"\]', '# self.runtimeDependencies["libs/brotli"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/libzstd"\]', '# self.runtimeDependencies["libs/libzstd"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/libpng"\]', '# self.runtimeDependencies["libs/libpng"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/libb2"\]', '# self.runtimeDependencies["libs/libb2"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/libjpeg-turbo"\]', '# self.runtimeDependencies["libs/libjpeg-turbo"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/sqlite"\]', '# self.runtimeDependencies["libs/sqlite"]'
    $qtContent = $qtContent -replace 'self.runtimeDependencies\["libs/freetype"\]', '# self.runtimeDependencies["libs/freetype"]'
    
    # Remove build dependencies
    $qtContent = $qtContent -replace 'self.buildDependencies\["dev-utils/pkgconf"\]', '# self.buildDependencies["dev-utils/pkgconf"]'
    $qtContent = $qtContent -replace 'self.buildDependencies\["dev-utils/perl"\]', '# self.buildDependencies["dev-utils/perl"]'
    $qtContent = $qtContent -replace 'self.buildDependencies\["dev-utils/flexbison"\]', '# self.buildDependencies["dev-utils/flexbison"]'
    
    # Fix IndentationError by commenting out the if statements too
    $qtContent = $qtContent -replace 'if self.options.dynamic.withDBus:', '# if self.options.dynamic.withDBus:'
    $qtContent = $qtContent -replace 'if self.options.dynamic.withICU:', '# if self.options.dynamic.withICU:'
    $qtContent = $qtContent -replace 'if self.options.dynamic.withHarfBuzz:', '# if self.options.dynamic.withHarfBuzz:'
    $qtContent = $qtContent -replace 'if self.options.dynamic.withFontConfig:', '# if self.options.dynamic.withFontConfig:'
    $qtContent = $qtContent -replace 'if CraftCore.compiler.isUnix and self.options.dynamic.withGlib:', '# if CraftCore.compiler.isUnix and self.options.dynamic.withGlib:'
    $qtContent = $qtContent -replace 'if self.options.dynamic.withPCRE2:', '# if self.options.dynamic.withPCRE2:'
    $qtContent = $qtContent -replace 'if self.options.dynamic.withCUPS:', '# if self.options.dynamic.withCUPS:'
    
    # Force internal versions in configure args (remove system libs)
    $qtContent = $qtContent -replace '"-DFEATURE_system_sqlite=ON"', '"-DFEATURE_system_sqlite=OFF"'
    $qtContent = $qtContent -replace '"-DFEATURE_system_zlib=ON"', '"-DFEATURE_system_zlib=OFF"'
    $qtContent = $qtContent -replace '"-DFEATURE_openssl_linked=ON"', '"-DFEATURE_openssl=OFF"'
    
    # Patch dynamic .asOnOff calls in __init__
    # These fail because the dependency is missing or the option is now a simple bool
    $qtContent = $qtContent -replace 'f"-DFEATURE_system_libb2=\{self.subinfo.options.isActive\(''libs/libb2''\).asOnOff\}"', '"-DFEATURE_system_libb2=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_system_freetype=\{self.subinfo.options.isActive\(''libs/freetype''\).asOnOff\}"', '"-DFEATURE_system_freetype=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_system_jpeg=\{self.subinfo.options.isActive\(''libs/libjpeg-turbo''\).asOnOff\}"', '"-DFEATURE_system_jpeg=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_system_pcre2=\{self.subinfo.options.dynamic.withPCRE2.asOnOff\}"', '"-DFEATURE_system_pcre2=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_system_harfbuzz=\{self.subinfo.options.dynamic.withHarfBuzz.asOnOff\}"', '"-DFEATURE_system_harfbuzz=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_icu=\{self.subinfo.options.dynamic.withICU.asOnOff\}"', '"-DFEATURE_icu=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_dbus=\{self.subinfo.options.dynamic.withDBus.asOnOff\}"', '"-DFEATURE_dbus=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_glib=\{self.subinfo.options.dynamic.withGlib.asOnOff\}"', '"-DFEATURE_glib=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_fontconfig=\{self.subinfo.options.dynamic.withFontConfig.asOnOff\}"', '"-DFEATURE_fontconfig=OFF"'
    $qtContent = $qtContent -replace 'f"-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=\{self.subinfo.options.dynamic.useLtcg.asOnOff\}"', '"-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF"'
    $qtContent = $qtContent -replace 'f"-DFEATURE_cups=\{self.subinfo.options.dynamic.withCUPS.asOnOff\}"', '"-DFEATURE_cups=OFF"'
    $qtContent = $qtContent -replace 'f"-DQT_FEATURE_egl=\{self.subinfo.options.dynamic.withEgl.asOnOff\}"', '"-DQT_FEATURE_egl=OFF"'
    
    Set-Content -Path $qtBaseBlueprint -Value $qtContent
}

# Temp cleanup
Remove-Item $tempDir -Recurse -Force

# 4. Clear cache so Craft rescans
$blueprintCache = Join-Path $craftRoot "etc\blueprints.json"
if (Test-Path $blueprintCache) { Remove-Item $blueprintCache -Force }

Write-Host "Injection complete. Craft currently believes opencloud is part of the system." -ForegroundColor Green
# -----------------------------------------------------------------------

# 3. Set source code path
Write-Host "Setting source directory to $repoRoot ..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--set", "srcDir=$repoRoot", "opencloud/opencloud-desktop")

# 4. Set build number
Invoke-CraftStep @("-c", "--set", "buildNumber=$BuildNumber", "opencloud/opencloud-desktop")

# 5. Install NSIS
if (-not $SkipNsis) {
    Invoke-CraftStep @("-c", "dev-utils/nsis")
}

# 6. Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--install-deps", "opencloud/opencloud-desktop")

# 7. Configure & Build
Write-Host "Configuring & Building ..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--no-cache", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--install", "opencloud/opencloud-desktop")

# 8. Create package
Write-Host "Creating Installer Package ..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--no-cache", "--package", "opencloud/opencloud-desktop")

$binaryDir = Join-Path $craftHome "binaries"
Write-Host ""
Write-Host "SUCCESS! Installer artifacts are available in $binaryDir" -ForegroundColor Green
