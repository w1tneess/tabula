# M6 notes (so far): verification in Windows Sandbox

Date 2026-11-24. Sandbox image: Windows 11 Enterprise 24H2, build 26100, 4 GB, virtual disk, no winget until bootstrapped with Microsoft's documented method (`-Winget`). This is one clean build. Not covered: Windows 10, Home or Pro, real hardware, laptops, scaling on a second monitor.

## Real run through the window (`sandbox/gui-run.ps1`, `./sandbox/Start-TabulaSandbox.ps1 -Gui`)
Real engine, real elevated process, real HKLM, real winget installs, real restore point. Evidence: `docs/sandbox-results/gui-run.json`, `docs/screens/Sandbox-*.png`.

| Step | Result |
|---|---|
| Apply plan (2 verified tweaks + 7-Zip) | 3 applied. HKLM values written (`EnableActivityFeed`, `PublishUserActivities`, `UploadUserActivities`, `AllowTelemetry` all 0). 7-Zip installed. |
| Restore point | Created (System Protection was off; Tabula turned it on, as the confirmation says). |
| Undo this run | Both tweaks reverted, all four HKLM values absent again. 7-Zip stayed, as the text says. |
| Second apply (2 tweaks + Notepad++ + VLC), Cancel while Notepad++ installs | Notepad++ finished, VLC "Not run", title "Cancelled", summary "1 not run (cancelled)". |
| Undo after cancel | Reverted cleanly. |

The confirmation dialog was bypassed by the test flag (`AutoConfirm`), so it has still not been clicked by a person.

## Bugs the Sandbox found, and fixes
1. **Detection failure on a virtual disk.** A harmless storage-probe error made the window treat all machine detection as failed (nothing usable). The probe now uses `-ErrorAction Stop` so it is caught, and the window only treats a missing profile as failure.
2. **Every install failed with `0x8A15003B` ("Rest API internal error") when another winget source (msstore) was unreachable.** Installs and `show` now pin `--source winget`. The same install then succeeded. A machine with a broken Store source would have hit this.
3. Dry run with no winget no longer reports every app as failed (earlier fix).
4. A winget-missing run now says what to do.

## Not done in M6
- Windows 10 and Home/Pro on real hardware, the power-plan and hibernate tweaks, 125 to 200 % scaling.
- Release: tag, checksum publication, README one-liner (needs the GitHub username), install-from-URL check on a clean machine.
- `docs/screens/` still shows which apps are installed on this PC (M3 screenshots).
- The "System Protection is off. Enabling it." path was exercised only in the Sandbox.
