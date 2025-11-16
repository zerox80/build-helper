# OpenCloud Desktop Windows Builder

Dieses Mini-Projekt erleichtert jedem Entwickler den lokalen Build des offiziellen [opencloud-eu/desktop](https://github.com/opencloud-eu/desktop) Repos.

## Inhalt
- `build-opencloud.ps1` – automatisiert Craft-Setup, Dependency-Installation, Build und Packaging (NSIS + 7z)
- `README.md` – diese Anleitung

## Voraussetzungen
- Windows 11/10 x64
- Visual Studio 2022 Build Tools (Desktop C++ workload)
- Git
- PowerShell (>=5) mit Internetzugang

## Verwendung
1. Offizielles Repo klonen:
   ```powershell
   git clone https://github.com/opencloud-eu/desktop.git
   cd desktop
   ```
2. Ordner `build-helper` in das Repo kopieren oder herunterladen.
3. PowerShell mit Ausführrechten starten:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build-helper\build-opencloud.ps1 -BuildNumber 1
   ```

Das Skript erledigt:
- CraftMaster klonen/initialisieren
- `srcDir` & Build-Number setzen
- NSIS installieren (optional via `-SkipNsis`)
- Dependencies laden/aktualisieren
- Projekt bauen (`CRAFT_JOBS` = Anzahl CPU-Kerne)
- Installer + 7z unter `%USERPROFILE%\craft\binaries` ablegen

## Optionen
- `-BuildNumber <n>` – Eindeutige Build-ID (landet in Version / RC-Dateien)
- `-SkipSetup` – Überspringt Craft-Setup wenn Umgebung bereits existiert
- `-SkipNsis` – Nur 7z-Paket erzeugen

## Verzeichnisstruktur
```
opencloud-desktop/
├─ build-helper/
│  ├─ build-opencloud.ps1
│  └─ README.md
└─ (Upstream-Repo)
```

## Hinweise
- Erstlauf lädt viele GB an Toolchains; Folge-Builds nutzen Cache.
- Installer-Output: `opencloud-desktop-latest-<BuildNumber>-windows-cl-msvc2022-x86_64.exe`
- Portable Archiv: `opencloud-desktop-latest-<BuildNumber>-windows-cl-msvc2022-x86_64.7z`

