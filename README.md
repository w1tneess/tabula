# Tabula

*Clean slate, on demand.*

A personal Windows 10/11 setup tool: detect the machine, apply reversible tweaks, reinstall apps from official sources, undo anything. Windows PowerShell 5.1 and WPF, shipped as a single file.

**Status: M3 (GUI shell).** The CLI works (`-Mode Auto|Apps|Tweaks|Undo|Export`, `-DryRun`) and `-Mode Gui` (the default) opens a window with the Setup, Apps, Tweaks, Tools and About pages. The window reads state but does not apply anything yet; applying from the window is M4. The app catalog is verified against winget. The tweak catalog is not verified, so every tweak is off and held back; a run installs apps only. See `docs/m1-notes.md`, `docs/m2-notes.md`, `docs/m3-notes.md`, `docs/apps-verification.md` and `docs/tweaks-verification.md` for what was and was not tested. Screenshots are in `docs/screens/`.

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

Install one-liner and a "what it changes" table arrive with M6.
