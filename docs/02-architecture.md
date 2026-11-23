# 02 Architecture

## Stack
- **Windows PowerShell 5.1** (present on every Windows 10/11).
- **WPF** via `PresentationFramework` for the GUI, XAML embedded as here-strings.
- **winget** for installs. Bootstrap it if missing.
- **Pester 5** for tests, **PSScriptAnalyzer** for lint. Dev-time only, never required at runtime.
- No other dependencies.

## Repo layout
```
tabula/
  src/
    Tabula.ps1              # entry: param block, mode dispatch
    Core/
      Logging.ps1           # Write-TabulaLog, log file, in-memory sink for UI
      State.ps1             # state.json read/write (prior values, applied tweaks)
      Detect.ps1            # Get-TabulaProfile
      RestorePoint.ps1      # New-TabulaRestorePoint
      Registry.ps1          # safe get/set/remove wrappers that record prior state
      Tweaks.ps1            # Invoke-TabulaTweak (apply|undo|detect)
      Winget.ps1            # winget bootstrap, install, detect, export
      Tools.ps1             # cleanup, DNS flush, SFC/DISM, update controls
    UI/
      Window.xaml           # main window shell
      Theme.xaml            # ResourceDictionary: colours, fonts, control styles
      Pages/*.xaml          # Setup, Apps, Tweaks, Tools, About
      UI.ps1                # load XAML, bind events, runspace pool, dispatcher helpers
  config/
    apps.json
    tweaks.json
    presets.json
    schema/                 # JSON schema files for validation
  tests/                    # Pester tests
  docs/
  build.ps1                 # bundles src + config into dist/tabula.ps1
  PSScriptAnalyzerSettings.psd1
  CLAUDE.md
  MASTER_PROMPT.md
  README.md
  LICENSE                   # MIT
```

## Build
`build.ps1`:
1. Validates `config/*.json` against `config/schema/*`.
2. Concatenates `src/Core/*.ps1`, `src/UI/UI.ps1`, then `src/Tabula.ps1` in a fixed order.
3. Embeds XAML and JSON as here-strings (single-quoted `@'...'@` to avoid expansion). If a here-string could contain `'@` at line start, escape or base64 it.
4. Writes `dist/tabula.ps1` and a `dist/tabula.ps1.sha256`.
5. Adds a header comment: version, build time, commit hash.

The shipped file must parse under 5.1: verify with `[System.Management.Automation.Language.Parser]::ParseFile`.

## Launch
Interactive, GUI:
```powershell
irm https://raw.githubusercontent.com/<user>/tabula/main/dist/tabula.ps1 | iex
```
Unattended (parameters cannot go through a bare `| iex`, so use a script block):
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/<user>/tabula/main/dist/tabula.ps1))) -Mode Auto
```
Plan to also offer a short link on his own domain that redirects to the raw file. Do not set up hosting in this project, just document it.

## Parameters (`Tabula.ps1`)
| Param | Values | Meaning |
|---|---|---|
| `-Mode` | `Gui` (default), `Auto`, `Apps`, `Tweaks`, `Undo`, `Export` | What to run |
| `-Preset` | name from `presets.json` | Which selection to use (default `Standard`) |
| `-DryRun` | switch | Print what would change, change nothing |
| `-NoRestorePoint` | switch | Skip restore point (logged) |
| `-Apps` / `-Skip` | string[] | Include or exclude app IDs |
| `-Yes` | switch | Skip confirmation prompts in unattended modes |
| `-LogPath` | path | Override log location |

Self-elevation: if not admin, show a clear message and the exact command to relaunch elevated. Do not auto-spawn UAC loops. (A one-time `Start-Process powershell -Verb RunAs` relaunch with the same args is acceptable if it works with `iex`; if it does not, just message the user.)

## Runtime flow
```
Start
 -> check admin, PS version, OS support
 -> Get-TabulaProfile  (detect)
 -> load config, resolve preset against profile
 -> Mode dispatch
      Gui:   build window, pages bound to engine
      Auto:  plan -> (dry run? print) -> restore point -> tweaks -> apps -> summary
      Undo:  read state.json -> revert in reverse order
```

## Concurrency (important for WPF)
- The UI thread must never block. Run installs and tweaks in a **runspace** (`[runspacefactory]::CreateRunspacePool`), report progress through a synchronised queue, and update controls via `$window.Dispatcher.Invoke/BeginInvoke`.
- The window must start in an **STA** thread. When launched via `iex` in a console that is MTA, re-run the GUI in a new STA runspace or use `powershell -STA`. Verify this early (M3), it is a known trap.
- One install at a time (winget does not like parallel runs). Tweaks are fast and sequential.
- Cancellation: a cancel flag checked between items. A running winget process is allowed to finish its current package.

## Error handling
- Failures are per item. One failed app or tweak never aborts the run.
- Every item ends in one of: `applied`, `skipped` (not applicable or already set), `failed` (with reason), `dryrun`.
- Summary at the end lists counts and failed items with log line references.

## Data locations
- State: `%ProgramData%\Tabula\state.json` (so it survives user switches; admin-only write).
- Logs: `%LOCALAPPDATA%\Tabula\logs\tabula-YYYYMMDD-HHmmss.log`. Keep the last 10.
- Never write inside the script's own directory (it may be in memory only).

## Security notes
- Fetched only: the script itself, winget packages, nothing else.
- Verify `dist/tabula.ps1.sha256` is published with each release. Document how to check it for people who do not want to blind-pipe to `iex`.
- Never execute strings from JSON as code. Tweak actions are structured data (registry, service, scheduled task, powercfg args), not script blocks. The only free-form escape hatch is a named, in-repo function referenced by name from an allow-list.
