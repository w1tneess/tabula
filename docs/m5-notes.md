# M5 notes

Date 2026-11-24, Windows 11 Pro build 26300, Windows PowerShell 5.1, not elevated, 100 % display scaling.

## Changed
- **DPI awareness.** powershell.exe is not DPI aware, so Windows would bitmap-scale the window at 125 % and up. `Set-TabulaDpiAwareness` asks for per-monitor v2 before the first window. If the host already fixed a mode it keeps that and the log says so at debug level.
- **Keyboard and screen reader names.** The Expander header showed as a type name to automation (`System.Windows.Controls.ContentPresenter`); it now uses the header text. Each app's Site button is named "Official site of <app>" instead of 22 identical names.
- **Copy.** The Tweaks warning still said applying was not wired up; it now says every run holds those tweaks back. A missing winget now says what to do ("Install App Installer from the Microsoft Store, then run again"), and the Apps page says installed state is unknown.

## Tested
- 208 Pester tests pass (6 new), lint clean.
- Per-monitor awareness is in effect for the process (read back with `GetThreadDpiAwarenessContext`).
- Tab order on all five pages: every stop has a name, none is a type name. Walked with logical focus in the off-screen window.
- At the smallest allowed size (860 x 560) no control extends past the right edge on any page, the Plan view or the Run view. Screenshots: `Small-Apps-dark.png`, `Small-Plan-dark.png`.
- Error states: unsupported machine (Setup and Review disabled, reason shown), winget missing (status per app, failed rows with a reason, "Finished with problems"). Screenshots: `Unsupported-dark.png`, `Run-problems-dark.png`.
- Copy rules: no exclamation marks, hype words or non-ASCII in window text (a test over the XAML and UI.ps1 literals).

## Not tested
- **Real scaling.** This PC is at 100 %. Per-monitor awareness is confirmed, but layout and sharpness at 125, 150 and 200 % have not been seen, and moving the window between monitors of different scale has not been tried. The brief asks for screenshots at 150 %; there are none.
- Reduce motion (the page transition checks `ClientAreaAnimation`), real key presses (Space, Enter, Ctrl+F with a real keyboard), a screen reader, high contrast mode.
- Windows 10, a clean VM, a Server SKU for real (the unsupported state uses a stubbed profile).
- Window open time against the 2 s target.
- The light theme at minimum size and in the error states (dark only).

## Not done
- Tab order is five stops through the rail radio buttons before each page. Arrow-key navigation inside the rail would be shorter; not changed.
- "Light fallback" in the brief was read as the light theme following the OS setting, which exists since M3.
- Tools page actions and restart buttons (see `m4-notes.md`).
