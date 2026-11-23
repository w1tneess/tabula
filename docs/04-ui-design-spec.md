# 04 UI design spec

Goal: minimal, calm, polished. It should look like a first-party Windows 11 utility made by someone with taste, not a hacker tool.

## Principles
1. **One obvious action** on the first screen.
2. **Show before change**: the user always sees the plan before anything is applied.
3. **Quiet by default**: lots of space, few colours, no icons that do not carry meaning.
4. **Honest states**: every item shows its true status (pending, running, applied, skipped, failed).
5. **Fast**: window opens in under 2 seconds on a modest laptop; no blocking calls on the UI thread.

## Window
- Size 980 x 640, min 860 x 560, resizable. Custom-free title bar is fine (standard chrome) for v1. If a custom title bar is attempted, it must keep snap layouts and keyboard shortcuts working; otherwise do not.
- Left navigation rail (200 px): app wordmark "Tabula" top, pages below, small machine summary at the bottom ("Windows 11 Pro 24H2 · Laptop · SSD").
- Content area on the right with generous padding (32 px).
- Bottom status bar: current action text on the left, progress on the right.

## Theme (dark first, light fallback follows OS)
Define in `Theme.xaml` as `ResourceDictionary` brushes so both themes swap by dictionary.

Dark:
| Token | Value | Use |
|---|---|---|
| `Bg` | `#0F1115` | window background |
| `Surface` | `#171A21` | cards, rail |
| `SurfaceHover` | `#1E222B` | hover |
| `Border` | `#262B36` | hairlines |
| `Text` | `#E6E8EC` | primary text |
| `TextDim` | `#8A91A0` | secondary text |
| `Accent` | `#7C9CFF` | primary action, selection (calm periwinkle) |
| `AccentText` | `#0B0D12` | text on accent |
| `Ok` | `#6FCF97` | applied |
| `Warn` | `#F2C94C` | skipped, caution |
| `Err` | `#EB5757` | failed |

Light fallback: mirror with `#F6F7F9` bg, `#FFFFFF` surface, `#14161B` text, accent `#3E63DD`.

Contrast: body text must meet WCAG AA against its background. Check and adjust the hex values if they do not.

## Type
- Font: `Segoe UI Variable Text` (Windows 11), fall back to `Segoe UI`. Mono for logs: `Cascadia Mono`, fall back to `Consolas`.
- Sizes: title 24 semi-bold, section 14 semi-bold uppercase with letter-spacing, body 13, caption 11.
- No more than two weights on screen.

## Shape and motion
- Corner radius 8 on cards and buttons, 6 on inputs, 4 on checkboxes.
- Hairline 1 px borders, no heavy shadows.
- Motion: 120 to 180 ms ease-out for hover, page transitions fade and 8 px slide. Progress is a thin 3 px bar. No spinners that spin forever without text.
- Respect "reduce motion" if detectable (`SystemParameters.ClientAreaAnimation`).

## Controls to restyle (so nothing looks default-WPF)
`Button` (primary, secondary, ghost), `CheckBox` (custom tick), `ToggleSwitch` (built from `CheckBox`), `ScrollBar` (thin, auto-hide look), `TextBox` (search), `ComboBox` if used, `ProgressBar`, `ToolTip`, `ListBoxItem`/card rows.

## Pages

### 1. Setup (home)
```
Clean slate, on demand.
Windows 11 Pro 24H2 · Laptop · SSD · 16 GB          [machine summary chip]

  [ Set up this PC ]        <- primary button
  Review plan first         <- ghost link (default behaviour: always shows the plan)

Preset  [ Standard v ]
  47 tweaks · 19 apps · restore point on
```
Flow: click "Set up this PC" opens the **Plan** view (list of tweaks and apps that will run, grouped, each with a checkbox, risk badge, and "why this machine"). Footer: `Apply plan` (primary), `Dry run` (secondary), `Cancel`. After apply: **Run** view with per-item live status, a collapsible log, then **Summary** (counts, failed items, restart actions, "Undo this run").

### 2. Apps
- Search box at top, category chips below.
- Grid of rows (not big tiles): checkbox, name, short description, small publisher text, official link icon, status pill (Installed / Not installed / Update available).
- Buttons: `Install selected`, `Select preset`, `Export installed apps` (writes `apps.export.json` next to a save dialog; explain it in a tooltip).
- Installed state is detected on page load in the background (cached, with a refresh button). Do not block the page while detecting.

### 3. Tweaks
- Grouped by category, collapsible, each tweak a row: toggle switch (reflects **current** system state via `detect`), name, description, risk badge, "Restart needed" hint.
- Toggling does not apply immediately. It stages a change. A bottom bar appears: `Apply 3 changes` / `Discard`.
- Greyed rows show why they do not apply ("Windows 11 only", "Laptop only").
- Experimental (unverified) tweaks sit behind a toggle at the bottom, collapsed by default, with a plain warning.

### 4. Tools
Simple action cards, each with a one-line description and a `Run` button, output goes to a log panel:
- Clean temporary files (user temp, Windows temp, optional recycle bin, shows size before deleting, asks to confirm)
- Flush DNS
- Reset network stack (confirm, needs restart)
- System file check (`sfc /scannow`) and `DISM /Online /Cleanup-Image /RestoreHealth` (long running, shows progress text, cancelable)
- Windows Update: pause for N days, resume, set active hours (uses documented settings only)
- Open: restore points, Startup apps, Optional features, Uninstall programs (just launch the OS UIs)

### 5. About
Version, build hash, log folder button, "Open logs", "Undo last run", link to the repo, licence, and one dry line, for example: "Does one job. Tries to do it quietly."

## Dialogs and states
- Confirmation dialogs: plain, state exactly what will change, default button is the safe one.
- Empty states: one short line, no illustrations.
- Errors: show what failed, why (from the log), and what the user can do. Never show raw stack traces in the main UI (put them in the log).
- Elevation missing: a calm full-window message with the exact command to run, plus a copy button.

## Accessibility
- Full keyboard navigation (Tab order, Space toggles, Enter activates, Ctrl+F focuses search).
- `AutomationProperties.Name` on all interactive controls.
- Respect system scaling (125 to 200 %), test at each.
- Not colour-only status: pair colour with a text or icon label.

## Copy rules
Dry, short, factual. Examples:
- Button: "Set up this PC", "Apply plan", "Dry run", "Undo this run"
- Status: "Applied", "Skipped (already set)", "Failed: <reason>"
- Summary: "Done. 44 applied, 3 skipped, 0 failed. Restart Explorer to finish 2 changes."
- No exclamation marks. No emojis. No "oops".

## Deliverables for M3 and M5
- Screenshots of each page at 100 % and 150 % scaling in `docs/screens/`.
- A short note on anything that deviates from this spec and why.
