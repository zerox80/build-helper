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
        self.targetDigests["3.09"] = (['577f0e97a234211d9d12397029230062557c0857d364893823329ce49c96936d'], "SHA256")
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
# -----------------------------------

# --- FIX: Missing Qt Blueprints ---
# Some installations are missing libs/qt and libs/qt6. We fetch them from the official repo.
$kdeBlueprintsUrl = "https://invent.kde.org/packaging/craft-blueprints-kde.git"
$kdeTempDir = Join-Path $HOME "craft_temp_kde_blueprints"
if (Test-Path $kdeTempDir) { Remove-Item $kdeTempDir -Recurse -Force }
Write-Host "Cloning KDE blueprints to rescue Qt..." -ForegroundColor Cyan
git clone --depth=1 $kdeBlueprintsUrl $kdeTempDir | Out-Null

$libsSource = Join-Path $kdeTempDir "libs"
$devUtilsSource = Join-Path $kdeTempDir "dev-utils"
$libsDest = Join-Path $targetBlueprintDir "libs"
$devUtilsDest = Join-Path $targetBlueprintDir "dev-utils"

if (-not (Test-Path $libsDest)) { New-Item -ItemType Directory -Path $libsDest | Out-Null }
if (-not (Test-Path $devUtilsDest)) { New-Item -ItemType Directory -Path $devUtilsDest | Out-Null }

if (Test-Path $libsSource) {
    Write-Host "Injecting all libraries from KDE blueprints..." -ForegroundColor Cyan
    # Clean destination first to avoid duplicates/conflicts
    if (Test-Path $libsDest) { Remove-Item $libsDest -Recurse -Force }
    Copy-Item -Path $libsSource -Destination $libsDest -Recurse -Force
}
if (Test-Path $devUtilsSource) {
    Write-Host "Injecting all dev-utils from KDE blueprints..." -ForegroundColor Cyan
    # Clean destination first to avoid duplicates/conflicts
    if (Test-Path $devUtilsDest) { Remove-Item $devUtilsDest -Recurse -Force }
    Copy-Item -Path $devUtilsSource -Destination $devUtilsDest -Recurse -Force
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
