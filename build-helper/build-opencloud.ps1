Param(
    [string]$BuildNumber = "1",
    [switch]$SkipSetup,
    [switch]$SkipNsis
)

$ErrorActionPreference = "Stop"

$env:CRAFT_JOBS = [Environment]::ProcessorCount

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$craftScript = Join-Path $repoRoot ".github\workflows\.craft.ps1"
if (!(Test-Path $craftScript)) {
    throw "Craft helper script not found at $craftScript"
}

$env:CRAFT_TARGET = "windows-cl-msvc2022-x86_64"
$craftHome = Join-Path $HOME "craft"
$craftMaster = Join-Path $craftHome "CraftMaster\CraftMaster"

if (-not (Test-Path $craftMaster)) {
    Write-Host "Cloning CraftMaster …"
    git clone --depth=1 https://invent.kde.org/kde/craftmaster.git $craftMaster | Out-Null
}

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

if (-not $SkipSetup -and -not (Test-Path (Join-Path $craftHome "CraftMaster\$env:CRAFT_TARGET"))) {
    Invoke-CraftStep @("--setup")
}

Invoke-CraftStep @("-c", "--set", "srcDir=$repoRoot", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--set", "buildNumber=$BuildNumber", "opencloud/opencloud-desktop")

if (-not $SkipNsis) {
    Invoke-CraftStep @("-c", "dev-utils/nsis")
}

Invoke-CraftStep @("-c", "--install-deps", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--no-cache", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--install", "opencloud/opencloud-desktop")
Invoke-CraftStep @("-c", "--no-cache", "--package", "opencloud/opencloud-desktop")

$binaryDir = Join-Path $craftHome "binaries"
Write-Host ""
Write-Host "Installer artifacts are available in $binaryDir" -ForegroundColor Green
