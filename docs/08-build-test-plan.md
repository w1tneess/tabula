# 08 Build and test plan

## Honest constraint
Tabula changes Windows. It must be tested on Windows. If the session running Claude Code is not on Windows, you can lint, parse, run schema checks and Pester tests that mock the OS, but you **cannot** claim the tool works. State that in every report. If you are on Wit's Windows PC, use VMs or Windows Sandbox, **never run unverified tweaks on his real system**.

## Test environments
1. **Windows Sandbox** (Pro/Enterprise): disposable, quick, good for the install flow. Does not persist restore points, so restore-point behaviour needs a VM.
2. **Hyper-V or VirtualBox VMs** with snapshots:
   - Windows 11 current stable (Pro), clean
   - Windows 11 previous major build (Pro)
   - Windows 11 Home
   - Windows 10 22H2 (Pro)
3. A clean snapshot before each test, revert after.
4. Laptop behaviour (battery, chassis) cannot be reproduced in most VMs: unit-test the profile logic with mocked CIM data and have Wit run a final check on his own laptop with `-DryRun`.

## Automated checks
- **Parse check** of `dist/tabula.ps1` with the PowerShell parser under Windows PowerShell 5.1.
- **PSScriptAnalyzer** with rules: no errors; warnings reviewed. Specifically flag PS7-only syntax.
- **Schema validation** of `apps.json`, `tweaks.json`, `presets.json`.
- **Pester 5 unit tests**
  - Profile detection with mocked `Get-CimInstance` (Win10, Win11, laptop, desktop, HDD, SSD, VM, Home, Pro).
  - Preset resolution against profiles (laptop excludes Ultimate Performance, Win10 excludes Win11-only tweaks).
  - Registry wrapper: apply then undo restores prior state (use a scratch key under `HKCU:\Software\TabulaTest`).
  - Undo when key or value did not exist beforehand.
  - State write-ahead and crash recovery (simulate a thrown exception mid-run).
  - Protected list guard rejects a forbidden tweak.
  - Winget wrapper: command construction, exit-code mapping (mock the process).
  - Config validation rules in `03-config-schemas.md`.
- **Dry-run golden test**: `-Mode Auto -DryRun` output on mocked profiles compared with stored expected plans.

## Manual test script (per VM)
1. Snapshot clean.
2. Run the one-liner from an elevated PowerShell 5.1 console. Expect the GUI to open (STA works through `iex`).
3. Confirm the machine summary matches the VM.
4. Setup page: review plan, verify items marked not applicable show reasons.
5. Dry run: nothing changes (check registry, `winget list`, restore points).
6. Apply the Standard preset. During the run: window stays responsive, status updates live, cancel works between items.
7. After: log exists, summary counts match reality, restart prompts correct.
8. Spot-check each applied tweak's effect.
9. Undo this run. Compare registry/service/task state to the pre-run export. They must match.
10. Re-run Apply (idempotency): everything reports `skipped (already set)`, apps report skipped.
11. Run `-Mode Auto -Yes` unattended from a script block. No prompts, correct exit code (0 ok, 1 partial failures, 2 fatal).
12. Failure injection: block winget network (offline), uninstall winget, rename a package ID in a test config. Run continues, failures logged per item.
13. Scaling: 100, 150, 200 %. No clipped text. Keyboard-only run through all pages.
14. Light-theme OS setting: UI remains legible.

## Exit codes
`0` all good, `1` completed with failures, `2` fatal (unsupported OS, not admin, config invalid), `3` user cancelled.

## Milestone acceptance criteria

| M | Accept when |
|---|---|
| M0 | `build.ps1` produces a `dist/tabula.ps1` that parses on 5.1 and prints version. Lint and (empty) tests pass in CI. |
| M1 | CLI modes work on a VM; apply/undo round-trip for 3 sample tweaks; restore point created; logs and state written; dry run changes nothing. |
| M2 | All catalog items verified or flagged; verification reports written; schema + validation tests pass. |
| M3 | Window opens through `iex` on a VM, all pages render, theme applied to all controls (no default-looking WPF controls), UI stays responsive during a fake long task. |
| M4 | Full GUI flow applies, shows live status, summary, undo. Cancel works. |
| M5 | Spec compliance review against `04-ui-design-spec.md` with screenshots, accessibility pass, scaling pass. |
| M6 | Clean-VM matrix passed. Release tagged. README one-liner and checksum documented. |

## CI (GitHub Actions)
- Runner: `windows-latest`.
- Steps: checkout, install Pester and PSScriptAnalyzer, run `build.ps1`, lint, tests, parse the dist under `powershell.exe` (5.1), upload `dist/` as an artefact, attach to a release on tag.
- CI cannot do the full VM flow. Say so in the README ("CI checks syntax and logic, not Windows behaviour").

## Release checklist
- Version bump, changelog entry.
- `dist/tabula.ps1` + `.sha256` attached to the release.
- README table of tweaks regenerated from `tweaks.json`.
- Tested-builds list updated.
- Manual script above completed and signed off by Wit on at least one real machine using `-DryRun`.

## Report format after each milestone
```
Milestone: M#
Done: ...
Tested (how, where): ...
Not tested: ...
Deviations from docs: ...
Questions for Wit (max 1-2): ...
Next: ...
```
