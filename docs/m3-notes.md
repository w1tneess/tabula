# M3 notes

Date 2026-11-24, Windows 11 Pro build 26300, Windows PowerShell 5.1, not elevated, 100 % display scaling.

## What exists
- `src/UI/`: `Window.xaml` (rail, content host, status bar), five pages (`Pages/Setup|Apps|Tweaks|Tools|About.xaml`), `Theme.Dark.xaml` and `Theme.Light.xaml` (palettes only), `Theme.xaml` (every control style), `UI.ps1` (window, jobs, page logic). The build embeds the XAML in `dist/tabula.ps1`; a dev run reads it from disk.
- `-Mode Gui` (the default) opens the window. Detection, installed-app checks and tweak-state checks run in background runspaces; the window opens first and fills in.
- The window follows the OS light or dark setting.
- Screenshots: `docs/screens/` (every page, dark and light, plus the Plan view and the expanded Experimental list).

## What the pages do now
- **Setup:** machine summary, preset chips, "N tweaks, M apps, restore point on" line, and the Plan view (every planned item with its risk, held items greyed with the reason). An elevation banner with a copy button shows when not elevated.
- **Apps:** search (Ctrl+F), category chips, rows with checkbox, publisher, official site link, and a live Installed / Not installed pill (one `winget list --id` per app, off the UI thread). "Select preset", "Export installed apps" (save dialog, background export) and "Refresh" work.
- **Tweaks:** switches show the current state of this PC through `Get-TabulaTweakState`. Toggling stages a change and shows the Apply / Discard bar. All 21 tweaks are unverified, so they sit under the collapsed "Experimental" section with the warning, and the main list shows the empty-state line.
- **Tools:** the four "open" buttons work (restore points, startup apps, optional features, uninstall programs). The maintenance cards are present and disabled.
- **About:** version, build, log folder, Open logs. "Undo last run" is disabled.
- **Not wired (M4):** Apply plan, Dry run, Install selected, Apply staged tweak changes, the maintenance tools, Undo from the window. Each is disabled with a tooltip, not hidden.

## Tested
- 187 Pester tests pass (12 new in `tests/UI.Tests.ps1`), lint clean.
- Window opened off-screen in a separate STA process, dark and light: all five pages lay out; a scan of the visual tree found 0 of the checked controls (buttons, check boxes, radio buttons, text boxes, progress bars, scroll bars, expanders) using WPF's default template; more than 40 were checked per run.
- Responsiveness: during a 3.5 s fake background task a 40 ms UI timer ticked 66 times with a longest gap of 94 ms (limit in the test: 400 ms). The task finished and called back on the UI thread.
- Contrast: every text pairing in both palettes meets 4.5:1 (computed in the test from the XAML values), so no palette value had to change.
- The shipped script opens and closes the window from a file in an STA console, through `iex`, and from a console started with `-MTA` (it moves onto its own STA runspace and logs that). Each exits 0.
- I looked at the dark and light screenshots of the Setup, Plan, Apps, Tweaks (expanded), Tools and About pages.

## Not tested
- Windows 10, other builds, a clean VM.
- 125 to 200 % scaling (screenshots are 100 % only; the brief wants 100 and 150 % at M3 and M5, scaling is on the M5 list). Window open time against the 2 s target was not measured.
- Keyboard-only navigation and screen readers. Tab order, `AutomationProperties.Name` and visible focus states are in place but only the Ctrl+F handler and style triggers were exercised indirectly.
- "Reduce motion" (the page transition checks `ClientAreaAnimation`; not exercised).
- Real clicks on Export, Select preset, the Tools "open" buttons and the Copy command button (code paths exist, none were clicked).
- CI: the GUI tests have not run on GitHub's `windows-latest`, which is a Server SKU, and may behave differently there.

## Deviations from `docs/04-ui-design-spec.md`
- **Preset picker** is a row of chips, not a drop-down; restyling `ComboBox` fully was not worth it for two presets.
- **Elevation:** a banner on Setup, not a full-window gate, so the plan can be reviewed without admin.
- **Risk badges** are plain labelled pills, not colour-coded.
- **Progress bar** is determinate only; there is no indeterminate state yet.
- **Screenshots** are 100 % only (see above).
- Standard window chrome, as the spec allows for v1.

## Decisions
- Resource lookups in the window and pages are all `DynamicResource`, so the palette can be swapped as a dictionary and the XAML parses before any resources exist. Only `BasedOn` and the local data templates use static references.
- `Foreground` is set explicitly on `Expander`, `ItemsControl` and `ScrollViewer` styles because their default styles colour everything inside black, and implicit `TextBlock` styles do not cross some template boundaries.
- UI state is one hashtable, `$script:TabulaUi`; event handlers read it instead of function locals.
- `TabulaRow` is a small C# class compiled with `Add-Type`, because PowerShell objects cannot raise the change notifications WPF bindings need.
- Test hooks: `TABULA_UI_AUTOCLOSE_MS` closes the window after N ms, and `TABULA_UI_DEMO=1` shows a "Responsiveness check" card on Tools. Neither is a user setting.
- The screenshots show which apps are installed on this PC (the Installed / Not installed pills). The About screenshots show a neutral log path. Delete `docs/screens/` or regenerate them if you do not want that in a public repository.
