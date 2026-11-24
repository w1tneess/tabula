# M4 notes

Date 2026-11-24, Windows 11 Pro build 26300, Windows PowerShell 5.1, not elevated, 100 % display scaling.

## What exists
- **Apply plan, Dry run, Install selected and Apply changes (staged tweaks) work from the window.** Each one builds a plan, asks for confirmation when it changes the system, and runs the engine in a background job.
- **Run view** (Setup page): one row per item with Waiting, Running, Applied, Skipped, Failed or Not run, a log panel fed live from the job, Cancel run, and afterwards a summary, Back and Undo this run.
- **Undo last run** (About page) and **Undo this run** (Run view) revert the recorded run, newest change first, with the same Run view. Apps stay installed and the copy says so.
- **Cancel** stops between items. An app that is already installing is left to finish, as in M1. A cancelled undo leaves the rest applied and the run revertible, so it can be resumed.
- **Closing the window during a real run** asks the engine to stop and closes when the current item has finished. A dry run closes at once.
- Engine changes: `Invoke-TabulaPlan` and `Invoke-TabulaUndo` take `-OnProgress` (start and done per item) and `-Control` (a hashtable whose `Cancel` the window flips); `Resolve-TabulaPlan` takes `-Tweaks` and `-Exact` so the window can plan from ticked rows without the preset adding anything.
- Job log lines go through the job queue to the UI thread, which is the only writer of the log file. Before this a job's lines never reached the file.

## Rules the window enforces
- Apply, Install selected, Apply changes and Undo need an elevated PowerShell. Without it they are disabled with the reason as the tooltip. Dry run does not need it.
- Medium and high risk items, the restore point and System Protection are named in the confirmation. Yes allows Tabula to turn System Protection on for C: if it is off.
- One engine job at a time. Starting a run stops the installed-app check first (two winget processes never overlap) and refreshes installed state and tweak state afterwards.
- Unverified tweaks show their state but their switch is disabled, so the Tweaks page stages nothing in this build. If one is staged anyway, the plan holds it and the result is Skipped (tested in `Engine.Tests.ps1`).
- A tweak that is already on cannot be switched off from the Tweaks page: Tabula only knows how to put back what it changed itself, which is Undo.
- A non-elevated process cannot read the state folder, so "No run to undo" is only shown when elevated; otherwise the tooltip says it needs administrator.

## Tested
- 202 Pester tests pass (15 new), lint clean.
- `Engine.Tests.ps1`: `-Exact` planning, unverified tweaks held under `-Exact`, progress events in order, a throwing callback does not stop a run, `-Control` cancel stops between items, a cancelled undo stays resumable.
- `UiRunHarness.ps1` opens the real window off-screen and clicks the real buttons (`RaiseEvent` on the click event) against a fixture catalog (two verified tweaks, one unverified, two apps). Everything the engine changes is under `HKCU:\Software\TabulaTest`; state and log are in a temp folder; winget, the restore point and the elevation flag are stubbed. It covers button gating with and without admin, dry run, apply, cancel after the running item, live log panel and log file, undo order, staging, install of the ticked app only, and closing the window mid-run.
- The Run view uses themed templates (scan of the visual tree after a dry run).
- A dry run clicked in the window against the real catalog, real winget and real machine profile, not elevated: 18 plan rows, 9 would apply, 8 skipped, no state file created, nothing changed. Screenshots: `docs/screens/Run-dry-*.png` and `Run-cancelled-*.png` (fixture items).

## Not tested
- **No real apply, install or undo was run through the window.** The elevated path has only run against the stubbed fixture. The engine itself was exercised elevated in M1.
- The confirmation dialogs (the harness bypasses them with a test flag, `AutoConfirm`), the real restore point from the window, and real winget installs and cancel during a real download.
- Windows 10, a clean VM, 125 to 200 % scaling, keyboard-only use and screen readers (the Run summary is a polite live region, not verified with a reader).
- Closing the window with a real long install running (the harness uses an 800 ms stub).
- CI on GitHub `windows-latest`.

## Not built
- **Tools page actions** (cleanup, DNS flush, network reset, SFC and DISM, update controls). Not part of the M4 test line in `docs/08-build-test-plan.md`, they delete or reset things and cannot be checked without a VM. The cards stay disabled and say "Not built yet."
- **Restart actions** (restart Explorer from the summary). The summary only says what needs a restart.
- Turning a tweak off without Undo, and per-tweak undo.

## Decisions
- Results are collected from the progress messages, not from the job's return value, so a job that dies half way still leaves a true record of what ran. Rows left unfinished are marked Not run.
- `@($list)` on the generic results list threw "Argument types do not match" in this runspace, and an `if` expression unrolled a one-item array. The code uses `.ToArray()` into a plain assignment.
- The Cancel button label on the Plan view is now Back. Cancel belongs to a run.
- `AutoConfirm` is a key in the window state set by the test harness. It is not a setting and not reachable from the command line.
