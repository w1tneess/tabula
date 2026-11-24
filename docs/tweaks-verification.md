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
