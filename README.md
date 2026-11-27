# Tabula

*Clean slate, on demand.*

A personal Windows 10/11 setup tool: detect the machine, apply reversible tweaks, reinstall apps from official sources, undo anything. Windows PowerShell 5.1 and WPF, shipped as a single file.

**Status: M5 (polish).** The CLI works (`-Mode Auto|Apps|Tweaks|Undo|Export`, `-DryRun`) and `-Mode Gui` (the default) opens a window that can dry run, apply, install selected apps, cancel and undo, with live status per item. The app catalog is verified against winget. Only 3 of 21 tweaks are verified (dark-mode, disable-activity-history, telemetry-minimum); the rest are held back, so a run installs apps and applies the two verified default-on privacy tweaks (needs an elevated run). Applying from the window has only been run against a stubbed fixture, not on a real machine; the Tools page actions are not built. See `docs/m1-notes.md` to `docs/m5-notes.md`, `docs/apps-verification.md` and `docs/tweaks-verification.md` for what was and was not tested. Screenshots are in `docs/screens/`.

## Build

```powershell
./build.ps1                      # writes dist/tabula.ps1 and dist/tabula.ps1.sha256
./dist/tabula.ps1 -Version
```

Lint and tests (dev-time only, needs Pester 5 and PSScriptAnalyzer):

```powershell
Invoke-ScriptAnalyzer -Path src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester ./tests
```

CI checks syntax and logic, not Windows behaviour.

## Docs

`MASTER_PROMPT.md` and `docs/` hold the full brief. `ANALYSIS.md` records the review of that brief and its open points.

## Install

Tabula is one file, attached to each GitHub release together with its SHA-256. Releases are at `github.com/w1tneess/tabula/releases`.

Look first, run second. Download, check the hash, preview with a dry run, then run it:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   # older Windows PowerShell 5.1 setups otherwise fail with "connection closed unexpectedly"
$u = 'https://github.com/w1tneess/tabula/releases/latest/download'
Invoke-WebRequest "$u/tabula.ps1" -OutFile tabula.ps1
Invoke-WebRequest "$u/tabula.ps1.sha256" -OutFile tabula.ps1.sha256
(Get-FileHash tabula.ps1 -Algorithm SHA256).Hash.ToLower() -eq (Get-Content tabula.ps1.sha256).Split(' ')[0]   # must print True
powershell -STA -ExecutionPolicy Bypass -File .\tabula.ps1 -Mode Auto -DryRun
powershell -STA -ExecutionPolicy Bypass -File .\tabula.ps1
```

One-liner, which runs the script without reading it first:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://github.com/w1tneess/tabula/releases/latest/download/tabula.ps1 | iex
```

Changing the PC needs an elevated Windows PowerShell. A dry run and the window's read-only views do not.

## What it changes

Everything is data in `config/`. A run applies, in this order: a restore point, the verified tweaks in the chosen preset, then the ticked apps through winget from official sources. Every change is recorded before it is made, so **Undo last run** puts tweaks back (installed apps stay installed).

Tweaks verified so far (Microsoft documents the key, and each was applied and undone on Windows 11 build 26100 in Windows Sandbox; see `docs/tweaks-verification.md`):

| Tweak | Registry | On by default | Note |
|---|---|---|---|
| No activity history upload | `HKLM\SOFTWARE\Policies\Microsoft\Windows\System`: `EnableActivityFeed`, `PublishUserActivities`, `UploadUserActivities` = 0 | yes | Documented for Pro, Enterprise and Education, not Home. |
| Lowest telemetry level for this edition | `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection`: `AllowTelemetry` = 0 | yes | Only Enterprise and Education honour 0. On Home and Pro it equals the required minimum. |
| Dark theme | `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`: `AppsUseLightTheme`, `SystemUsesLightTheme` = 0 | no | Per user. |

The other 18 tweaks are unverified, off, and held back from every run. Tabula never touches the protected list in `docs/07-tweaks-catalog.md` (Defender, Windows Update service enablement, firewall, Store, UAC, boot settings, activation).

Not tested yet: Windows 10, Home and Pro, laptops and other hardware, and display scaling above 100 %.
