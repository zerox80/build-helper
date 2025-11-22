Param(
    [string]$BuildNumber = "1",
    [switch]$SkipSetup,
    [switch]$SkipNsis
)

$ErrorActionPreference = "Stop"
$env:CRAFT_JOBS = [Environment]::ProcessorCount

# --- Pfade definieren ---
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$craftScript = Join-Path $repoRoot ".github\workflows\.craft.ps1"

if (!(Test-Path $craftScript)) {
    throw "Craft helper script not found at $craftScript"
}

$env:CRAFT_TARGET = "windows-cl-msvc2022-x86_64"
$craftHome = Join-Path $HOME "craft"
$craftMaster = Join-Path $craftHome "CraftMaster\CraftMaster"
# Der Pfad, in dem Craft tatsächlich läuft
$craftRoot = Join-Path $craftHome "CraftMaster\windows-cl-msvc2022-x86_64"

# 1. CraftMaster holen
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

# 2. Setup ausführen (Damit die Ordner erstellt werden)
if (-not $SkipSetup -and -not (Test-Path $craftRoot)) {
    Write-Host "Running Craft Setup ..." -ForegroundColor Cyan
    Invoke-CraftStep @("--setup")
}

# --- FIX: DIE PARASITEN-METHODE ---
# Wir registrieren nichts. Wir kopieren die Dateien einfach in den Ordner, 
# den Craft SOWIESO durchsucht (craft-blueprints-kde).

# 1. Den funktionierenden Blueprint-Ordner finden
$targetBlueprintDir = Join-Path $craftRoot "craft\blueprints\craft-blueprints-kde"
if (-not (Test-Path $targetBlueprintDir)) {
    # Fallback, falls der Pfad leicht anders ist
    $targetBlueprintDir = Join-Path $craftRoot "blueprints\craft-blueprints-kde"
}
if (-not (Test-Path $targetBlueprintDir)) {
    # Letzter Versuch: Einfach in den 'blueprints' root
    $targetBlueprintDir = Join-Path $craftRoot "craft\blueprints"
}

Write-Host "Targeting active blueprint directory: $targetBlueprintDir" -ForegroundColor Magenta

# 2. Blueprints temporär herunterladen
$tempDir = Join-Path $HOME "craft_temp_blueprints"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

Write-Host "Downloading Blueprints manually..." -ForegroundColor Cyan
# Wir benutzen die URL, die existiert. 
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

# 3. INJIZIEREN (Kopieren ohne Rücksicht auf Verluste)
Write-Host "Injecting Blueprints into system..." -ForegroundColor Cyan

# Wir kopieren alles aus dem Clone direkt in den KDE-Ordner.
# Craft wird beim nächsten Scan denken, "opencloud" gehört einfach zu KDE dazu.
Copy-Item -Path "$tempDir\*" -Destination $targetBlueprintDir -Recurse -Force

# Temp aufräumen
Remove-Item $tempDir -Recurse -Force

# 4. Cache löschen, damit Craft neu scannt
$blueprintCache = Join-Path $craftRoot "etc\blueprints.json"
if (Test-Path $blueprintCache) { Remove-Item $blueprintCache -Force }

Write-Host "Injection complete. Craft currently believes opencloud is part of the system." -ForegroundColor Green
# -----------------------------------------------------------------------

# 3. Quellcode-Pfad setzen
Write-Host "Setting source directory to $repoRoot ..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--set", "srcDir=$repoRoot", "opencloud/opencloud-desktop")

# 4. Build-Nummer setzen
Invoke-CraftStep @("-c", "--set", "buildNumber=$BuildNumber", "opencloud/opencloud-desktop")

# 5. NSIS installieren
if (-not $SkipNsis) {
    Invoke-CraftStep @("-c", "dev-utils/nsis")
}

# 6. Abhängigkeiten installieren
Write-Host "Installing dependencies..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--install-deps", "opencloud/opencloud-desktop")

# 7. Konfigurieren & Bauen
Write-Host "Configuring & Building ..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--no-cache", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--install", "opencloud/opencloud-desktop")

# 8. Paket erstellen
Write-Host "Creating Installer Package ..." -ForegroundColor Cyan
Invoke-CraftStep @("-c", "--no-cache", "--package", "opencloud/opencloud-desktop")

$binaryDir = Join-Path $craftHome "binaries"
Write-Host ""
Write-Host "SUCCESS! Installer artifacts are available in $binaryDir" -ForegroundColor Green
