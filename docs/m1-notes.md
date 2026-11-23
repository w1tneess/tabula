# M1 notes

Checked on Windows 11 Pro (build 26300, reported as 26H2), Windows PowerShell 5.1, winget 1.29.380, not elevated. Not checked on Windows 10 or any VM.

## What exists
Core engine in `src/Core/`: logging, state (write-ahead, atomic save), detection, restore point, registry wrapper, tweak runner (apply, undo, detect, protected-list guard, applicability), winget wrapper, plan resolution and runner, CLI dispatch. Modes `Auto|Apps|Tweaks|Undo|Export` with `-DryRun`, `-Yes`, `-NoRestorePoint`, `-IncludeHighRisk`, `-Apps`, `-Skip`, `-Preset`, `-LogPath`. Exit codes 0 / 1 / 2 / 3. `Tools.ps1` is still a stub (Tools page, M4).

`config/apps.json` and `config/tweaks.json` are empty. Only the `Standard` preset exists. Data is M2.

## Tested
- 123 Pester tests pass; PSScriptAnalyzer clean (including 5.1 parse errors). Tests run in a mix of: the scratch key `HKCU:\Software\TabulaTest` (real registry, removed afterwards), Pester's TestDrive for state and logs, and mocks for winget, powercfg, services, tasks, CIM and restore points.
- Apply then undo for three sample tweaks (DWord, `(Default)` string with key creation, two-action tweak): registry returns to the prior state, created keys removed, existing keys kept.
- Write-ahead: the prior values are on disk before the first change. A change left `pending` by a simulated crash is reverted by `-Mode Undo`.
- Rollback when a later action in a tweak throws; run continues after a failed item; exit code 1.
- Protected-list guard rejects 14 cases (Defender, Windows Update, firewall, UAC, Store, secure boot, protected tasks, unlisted functions, unknown action types, unsupported powercfg op).
- Real machine, read-only: detection (Windows 11 Pro 26H2, desktop, SSD, 16 GB, winget 1.29.380); dry run of five sample tweaks against the live registry, powercfg and service state (including a refusal of a Defender service tweak); `winget list` and `winget show` through `Install-TabulaApp -DryRun` for an installed, a missing and a non-existent package; `-Mode Export` (47 installed apps written to a scratch folder). No state file was created.
- `-Mode Auto|Apps|Tweaks|Undo -DryRun` with the empty catalog exit 0; a real run without elevation exits 2.

## Not tested
- Any real tweak apply or undo outside the scratch key. No Windows Sandbox, Hyper-V or VirtualBox here, and the brief forbids running unverified tweaks on this PC.
- A real `Checkpoint-Computer` (only mocked). Throttling, System Protection off, Home edition.
- A real winget install, a real timeout, the registration step of the winget bootstrap.
- Service and scheduled-task actions against real services (read paths ran in the dry run; writes are mocked).
- Laptop chassis and HDD detection (unit-tested with mocked CIM only), Windows 10.
- `-Mode Undo` and `-Mode Auto` elevated, end to end.

## Decisions and deviations
- `--scope` is passed to winget only when an app sets `scope`. The brief defaults to machine scope, but not every installer supports it.
- Winget bootstrap does step one only (register App Installer). Fetching the bundle from aka.ms/getwinget with dependencies and a signature check is not built; without winget, apps are reported as failed and tweaks still run.
- Winget exit codes mapped: `0x8A150061` already installed, `0x8A15002B` no applicable update, `0x8A150109` restart needed (applied, with a reboot hint). Checked with `winget error --input`. Everything else is a failure with the code in the reason.
- Unverified tweaks (`verified: false`) are held in the plan with the reason "unverified (experimental)". The Experimental toggle belongs to the GUI (M3).
- Hibernation state is read from `HibernateEnabled`, falling back to `HibernateEnabledDefault` (the former is absent on this PC). Unverified; the hibernate tweak stays Experimental until tested in a VM.
- Export writes `apps.export.json` in the current folder. Entries not already in `apps.json` get `officialUrl: null`, so they fail validation (M2) until reviewed.
- The registry wrapper uses `RegistryKey` with the 64-bit view, not the provider, to handle `(Default)`, value kinds and 32-bit hosts.
- Undo revert order is reverse of apply; keys are removed only if Tabula created them and they are still empty.
- Cancellation exists as `$script:TabulaCancel` (checked between items); nothing sets it yet, the GUI will.
- Pester 6 rejects `BeforeEach` at file root, so test setup lives inside `Describe`.
