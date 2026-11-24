# M2 notes

Date 2026-11-24, Windows 11 Pro build 26300, winget v1.29.380, not elevated.

## What exists
- `config/apps.json`: 22 apps from the starter list, every winget ID checked with `winget show` (report: `docs/apps-verification.md`).
- `config/tweaks.json`: 21 tweaks from the starter catalog, all `verified: false`, all `defaultOn: false` (report: `docs/tweaks-verification.md`).
- `config/presets.json`: `Standard` and `Minimal`.
- `src/Core/Config.ps1`: `Test-TabulaConfig`, the validation rules from `docs/03-config-schemas.md`. It runs in `build.ps1` (a bad catalog fails the build) and at start-up of the shipped script (exit 2 with each problem logged).
- `config/schema/*.json`: real draft-07 schemas for editors and other tools. They are not executed; the validator is the source of truth, because `Test-Json` does not exist on 5.1.
- App-level `appliesTo`, so Windows Terminal is held on Windows 11.

## Tested
- 175 Pester tests pass (27 new), lint clean. The validator is tested with 20 mutations of a good config, the shipped catalog, and a build that must fail on an invalid catalog.
- Real read-only runs against the shipped catalog: `-Mode Auto -DryRun` (19 s; 9 apps would install, 8 already installed, Windows Terminal held as Windows 10 only, no tweaks) and `-Mode Tweaks -Preset Minimal -DryRun` (four tweaks held as unverified). Both exit 0.
- All 22 winget IDs exist and the publisher fits, except Node.js, where winget reports "Node.js Foundation" rather than the brief's guess.

## Not tested
- Any tweak: none was applied or undone anywhere except the scratch key. Registry paths and values have no source consulted yet.
- Any real app install, silent install behaviour, elevated install of per-user apps, or `--scope machine`.
- `officialUrl` values were not fetched.
- Windows 10, Home, laptops.

## Decisions and deviations
- All tweaks ship unverified and off, hidden by the plan as "unverified (experimental)". The Standard preset therefore applies no tweaks yet, and `-Mode Auto` installs apps only.
- `hide-copilot-button` dropped (no verified key, brief says to drop it).
- `visual-effects-balanced` writes only `MinAnimate` and is marked incomplete.
- Python uses `Python.Python.3.15`. The catalog's 3.13 is not the newest any more.
- `intendedDefaultOn` is a new optional tweak field so the starter defaults are not lost.
- Validator rejects `detect` other than `actions` and `undo` other than `restore-prior`, since the engine implements only those.
- Chrome and Brave are both default-selected, as in the starter list. That is a taste question for you.
