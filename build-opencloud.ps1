Param(
    [string]$BuildNumber = "1",
    [switch]$SkipSetup,
    [switch]$SkipNsis
)

$ErrorActionPreference = "Stop"

# Anzahl der CPU-Kerne für schnelleres Kompilieren nutzen
$env:CRAFT_JOBS = [Environment]::ProcessorCount

# Pfade bestimmen
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$craftScript = Join-Path $repoRoot ".github\workflows\.craft.ps1"

if (!(Test-Path $craftScript)) {
    throw "Craft helper script not found at $craftScript"
}

# Ziel-Umgebung festlegen (Visual Studio 2022)
$env:CRAFT_TARGET = "windows-cl-msvc2022-x86_64"
$craftHome = Join-Path $HOME "craft"
$craftMaster = Join-Path $craftHome "CraftMaster\CraftMaster"

# 1. CraftMaster holen, falls nicht vorhanden
if (-not (Test-Path $craftMaster)) {
    Write-Host "Cloning CraftMaster …"
    git clone --depth=1 https://invent.kde.org/kde/craftmaster.git $craftMaster | Out-Null
}

# Funktion zum Ausführen von Craft-Befehlen
function Invoke-CraftStep {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $psArgs = @("-ExecutionPolicy", "Bypass", "-File", $craftScript) + $Arguments
    Write-Host ">> craft" ($Arguments -join " ")
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        throw "Craft command failed with exit code $($proc.ExitCode)"
    }
}

# 2. Setup ausführen (Tools wie CMake/Python laden)
if (-not $SkipSetup -and -not (Test-Path (Join-Path $craftHome "CraftMaster\$env:CRAFT_TARGET"))) {
    Invoke-CraftStep @("--setup")
}

# --- NEU: Automatische Registrierung der Blueprints ---
# Das Skript sucht nun automatisch nach dem Ordner 'blueprints' oder '.craft'
$blueprintDir = Join-Path $repoRoot "blueprints"
if (-not (Test-Path $blueprintDir)) {
    # Fallback: Manchmal heißt der Ordner auch .craft
    $blueprintDir = Join-Path $repoRoot ".craft"
}

if (Test-Path $blueprintDir) {
    Write-Host "Registering blueprint repository at $blueprintDir ..." -ForegroundColor Cyan
    Invoke-CraftStep @("-c", "--add-blueprint-repository", $blueprintDir)
} else {
    Write-Warning "Kein 'blueprints' Ordner gefunden! Wenn der Build fehlschlägt, fehlt das Rezept."
}
# -----------------------------------------------------

# 3. Pfade und Version setzen
Invoke-CraftStep @("-c", "--set", "srcDir=$repoRoot", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--set", "buildNumber=$BuildNumber", "opencloud/opencloud-desktop")

# 4. NSIS (Installer-Tool) installieren
if (-not $SkipNsis) {
    Invoke-CraftStep @("-c", "dev-utils/nsis")
}

# 5. Abhängigkeiten installieren (Qt, OpenSSL etc.) - DAS DAUERT LANGE
Invoke-CraftStep @("-c", "--install-deps", "opencloud/opencloud-desktop")

# 6. Konfigurieren (CMake)
Invoke-CraftStep @("-c", "--no-cache", "opencloud/opencloud-desktop")

# 7. Kompilieren
Invoke-CraftStep @("-c", "--install", "opencloud/opencloud-desktop")

# 8. Paketieren (EXE erstellen)
Invoke-CraftStep @("-c", "--no-cache", "--package", "opencloud/opencloud-desktop")

$binaryDir = Join-Path $craftHome "binaries"
Write-Host ""
Write-Host "SUCCESS! Installer artifacts are available in $binaryDir" -ForegroundColor Green
