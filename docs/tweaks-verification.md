# Tweaks verification

Status 2026-11-24: **no tweak is verified.** There is no VM or Windows Sandbox available, and the rules forbid applying an unverified tweak on a real system. Every tweak in `config/tweaks.json` therefore ships with `verified: false`, `defaultOn: false` and an empty `testedBuilds`. The preset rule "unverified tweaks are held" means a run reports them as skipped (unverified, experimental) and changes nothing.

`intendedDefaultOn` records what the starter catalog wanted. When a tweak is verified, set `verified: true`, fill `testedBuilds`, and set `defaultOn` to its `intendedDefaultOn`.

## What was and was not checked
- **Source consulted:** none yet. Registry paths and values were written from knowledge (see `docs/07-tweaks-catalog.md`). Checking each against Microsoft documentation or a known working source is still to do.
- **Applied and undone in a VM:** nothing.
- **Read-only observation on this PC** (Windows 11 Pro build 26300, 2026-11-24): the engine read each registry path through `Get-TabulaRegistryState` and wrote nothing. A value name being present on one machine is weak evidence that the name exists on that build. It does not show the value does what the tweak says, or that writing it has any effect. It is not verification.
- The engine and the apply, undo and round-trip mechanics are tested separately (see `docs/m1-notes.md`), on a scratch key only.

## Per tweak
"Seen" = whether the value name exists on this PC's build 26300 right now.

| id | Hive | Source consulted | VM build tested | Apply | Undo | Verified | Seen on 26300 |
|---|---|---|---|---|---|---|---|
| file-extensions | HKCU | none yet | not tested | not tested | not tested | no | yes |
| hidden-files | HKCU | none yet | not tested | not tested | not tested | no | yes |
| classic-context-menu | HKCU | none yet | not tested | not tested | not tested | no | key present |
| taskbar-left | HKCU | none yet | not tested | not tested | not tested | no | value absent (key present) |
| dark-mode | HKCU | none yet | not tested | not tested | not tested | no | yes (both) |
| this-pc-launch | HKCU | none yet | not tested | not tested | not tested | no | yes |
| disable-search-web | HKCU | none yet | not tested | not tested | not tested | no | yes |
| disable-ad-id | HKCU | none yet | not tested | not tested | not tested | no | yes |
| disable-suggestions | HKCU | none yet | not tested | not tested | not tested | no | partly: 2 of 6 values present, the four SubscribedContent values absent |
| disable-activity-history | HKLM | none yet | not tested | not tested | not tested | no | yes (all 3) |
| telemetry-minimum | HKLM | none yet | not tested | not tested | not tested | no | value absent (key present) |
| disable-tailored-experiences | HKCU | none yet | not tested | not tested | not tested | no | yes |
| disable-game-dvr | HKCU | none yet | not tested | not tested | not tested | no | yes (both) |
| startup-delay | HKCU | none yet | not tested | not tested | not tested | no | key absent |
| delivery-optimization-off | HKLM | none yet | not tested | not tested | not tested | no | key absent |
| visual-effects-balanced | HKCU | none yet | not tested | not tested | not tested | no | yes (incomplete tweak, see below) |
| ultimate-performance-plan | powercfg | none yet | not tested | not tested | not tested | no | not applicable |
| balanced-plan | powercfg | none yet | not tested | not tested | not tested | no | not applicable |
| hibernate-off | powercfg | none yet | not tested | not tested | not tested | no | not applicable |
| hide-widgets | HKCU | none yet | not tested | not tested | not tested | no | value absent (key present) |
| hide-task-view | HKCU | none yet | not tested | not tested | not tested | no | yes |

## Decisions and open points
- **hide-copilot-button dropped.** The brief says to drop it if no stable key exists. None was verified, so it is not in the catalog.
- **visual-effects-balanced** writes only `MinAnimate`. The brief says to verify which values the Visual Effects UI writes; that is not done, so the tweak is incomplete and stays off.
- **ultimate-performance-plan** duplicates the scheme template `e9a42b02-d5df-448d-aa00-03f14749eb61` into a fixed GUID chosen for Tabula so the action is idempotent. Neither the template GUID nor the behaviour on laptops and other SKUs has been tested.
- **telemetry-minimum** states in its description that Home and Pro treat 0 as the required minimum, as the brief requires. The policy behaviour itself is untested.
- **disable-activity-history, telemetry-minimum, delivery-optimization-off** write to HKLM and need an elevated run. Policy keys under `Policies\` may not take effect on Home. Unchecked.
- **hibernate-off** reads the current state from `HibernateEnabled` with a fallback to `HibernateEnabledDefault`, because the first is absent on this PC. Unverified.
- To verify a tweak, in a VM: apply, check the effect, undo, check the revert, record the build in `testedBuilds`, then set `verified: true` and `defaultOn` per `intendedDefaultOn`.

## Windows Sandbox run, 2026-11-24 (build 26100, Windows 11 Enterprise 24H2, clean image)
Script: `sandbox/verify-tweaks.ps1`. Raw output: `docs/sandbox-results/verify-tweaks.json`. For each tweak the real engine read the state, applied it, read the state, undid it, read the state. **This checks the apply and undo mechanics and that the key exists on a clean build. It does not check that Windows behaves as the description says, and no source was consulted, so `verified` stays `false` for every tweak.**

| Result | Tweaks |
|---|---|
| Applied, state became Set, undo reverted, state back to Unset | file-extensions, hidden-files, classic-context-menu, taskbar-left, dark-mode, this-pc-launch, disable-search-web, disable-suggestions, disable-activity-history, telemetry-minimum, disable-tailored-experiences, disable-game-dvr, startup-delay, delivery-optimization-off, visual-effects-balanced, hide-task-view  |
| **Failed**: Windows refused the write ("unauthorized operation"), engine rolled back cleanly | hide-widgets (`TaskbarDa` is protected on this build; the catalog already warned newer builds may block it) |
| Inconclusive: already Set before the test | disable-ad-id |
| Inconclusive: not applicable in a virtual machine | ultimate-performance-plan, balanced-plan, hibernate-off (need real hardware) |

Counts from the json: 16 pass, 4 inconclusive, 1 error (the error is hide-widgets, a real failure; the script mislabelled it because of a strict-mode bug in the script, since fixed).

Still to do before any `verified: true`: check each key against Microsoft or another reliable source, observe the visible effect (for example Explorer actually showing extensions), and test the power-plan tweaks on real hardware. Nothing was changed in `config/tweaks.json`.

## Apps on a clean machine (same Sandbox run, after the documented winget bootstrap)
A dry run against real winget on the clean image resolved all 17 applicable app IDs (`winget show`): 17 would install, 1 skipped (Windows Terminal, Windows 10 only). `docs/sandbox-results/probe.txt` has the probe.

## Source check, 2026-11-24
Searched Microsoft Learn (Policy CSP pages, "Reference for Windows 11 and Windows 10 settings", Win32 docs) for each key. "Documented" means Microsoft states the registry key, the value and what it does. The Sandbox run was repeated after the two corrections below: 16 pass, 4 inconclusive, 1 fail (hide-widgets), now labelled correctly.

| Tweak | Microsoft source | Finding |
|---|---|---|
| dark-mode | Reference for Windows 11 and 10 settings, Personalization - colors | **Documented**: `AppsUseLightTheme` and `SystemUsesLightTheme`, REG_DWORD, 0/1. |
| disable-activity-history | Policy CSP - Privacy | **Documented**: `EnableActivityFeed`, `PublishUserActivities`, `UploadUserActivities` under `HKLM\Software\Policies\Microsoft\Windows\System`, 0 = disabled. The CSP lists Pro, Enterprise, Education, not Home. |
| telemetry-minimum | Policy CSP - System, "Manage connections" | **Documented**: `AllowTelemetry` under `HKLM\...\Policies\Microsoft\Windows\DataCollection`. 0 (Security) only takes effect on Enterprise, Education and Server; on other editions it equals 1. |
| taskbar-left, hide-task-view | Reference for Windows 11 settings, Taskbar | Meaning documented (`TaskbarAl` 0 = left, `ShowTaskViewButton` 0/1; policy `HideTaskViewButton` exists). The page lists the values as REG_SZ under a differently laid out path than the DWord we write, so type and location are not confirmed. |
| visual-effects-balanced | `ANIMATIONINFO` / `SPI_SETANIMATION` | The effect (minimize and restore animation) is documented for the API. The `WindowMetrics\MinAnimate` registry value is not documented. |
| delivery-optimization-off | Policy CSP - DeliveryOptimization | `DODownloadMode` 0 = HTTP only, no peering is documented, but under `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization`. **The catalog used another path. Corrected.** |
| disable-search-web | Policy CSP - ADMX_WindowsExplorer | `DisableSearchBoxSuggestions` is documented for the **File Explorer** search box (recent searches), not Start web results. **Name and description corrected to what Microsoft documents.** A real "no web results in Start" tweak needs a different, documented setting and is not in the catalog. |
| hide-widgets | Reference for Windows 11 settings; Taskbar policy settings | `TaskbarDa` is documented, but Windows 24H2 refused the write in the Sandbox. The documented route is the "Allow widgets" policy (`AllowNewsAndInterests`), not tried. |
| disable-ad-id | Policy CSP - Privacy | Microsoft documents the policy (`HKLM\Software\Policies\Microsoft\Windows\AdvertisingInfo\DisabledByGroupPolicy`), not the per-user `Enabled` value the tweak writes. |
| disable-tailored-experiences | Policy CSP - Experience, "Manage connections" | Microsoft documents the policy (`HKCU\Software\Policies\Microsoft\Windows\CloudContent\DisableTailoredExperiencesWithDiagnosticData` = 1), not the Settings toggle value the tweak writes. |
| disable-game-dvr | Policy CSP - ApplicationManagement | Microsoft documents the `AllowGameDVR` policy, not the `GameDVR_Enabled` and `AppCaptureEnabled` user values the tweak writes. |
| file-extensions, hidden-files, this-pc-launch, classic-context-menu, startup-delay, disable-suggestions | none found | No Microsoft page found for these values. They are widely used, but that is not a Microsoft source. |
| ultimate-performance-plan, balanced-plan, hibernate-off | not searched | Need real hardware first. |

Nothing was marked `verified`. The three tweaks that are fully documented and passed in the Sandbox (dark-mode, disable-activity-history, telemetry-minimum) are the candidates, with the caveats above. What was observed in the Sandbox is the registry state, not the visible effect.
