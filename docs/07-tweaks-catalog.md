# 07 Tweaks catalog (starter list)

**Status: all unverified.** Registry paths and values were written from knowledge, not tested on Windows. Rules for M2:
1. Check each against Microsoft documentation or a reliable source.
2. Apply it in a Windows VM, observe the effect, undo it, observe the revert.
3. Only then set `verified: true` and list the build in `testedBuilds`.
4. Unverified or failed ones ship hidden under Experimental, off by default.

Legend: Risk L/M/H. Restart: none, explorer (restart Explorer), signout, reboot. `W11` means Windows 11 only.

## Interface
| id | What | Action | Risk | Restart | Default |
|---|---|---|---|---|---|
| file-extensions | Show file extensions | HKCU `Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` `HideFileExt` = 0 (DWord) | L | explorer | on |
| hidden-files | Show hidden files | same key, `Hidden` = 1 | L | explorer | on |
| classic-context-menu (W11) | Full right-click menu | HKCU `Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32`, `(Default)` = empty string, create key. Undo: delete the `{86ca...}` key if it did not exist before | L | explorer | on |
| taskbar-left (W11) | Align taskbar left | HKCU `...\Explorer\Advanced` `TaskbarAl` = 0 | L | explorer | off (taste) |
| dark-mode | Dark theme | HKCU `Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` `AppsUseLightTheme` = 0 and `SystemUsesLightTheme` = 0 | L | none | off (taste) |
| this-pc-launch | Explorer opens to This PC | HKCU `...\Explorer\Advanced` `LaunchTo` = 1 | L | explorer | on |
| disable-search-web | No web results in Start search | HKCU `Software\Policies\Microsoft\Windows\Explorer` `DisableSearchBoxSuggestions` = 1 | L | explorer | on |

## Privacy
| id | What | Action | Risk | Restart | Default |
|---|---|---|---|---|---|
| disable-ad-id | Turn off advertising ID | HKCU `Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` `Enabled` = 0 | L | none | on |
| disable-suggestions | Stop Start/lock-screen suggestions and tips | HKCU `Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`: `SystemPaneSuggestionsEnabled` = 0, `SubscribedContent-338388Value` = 0, `SubscribedContent-338389Value` = 0, `SubscribedContent-353694Value` = 0, `SubscribedContent-353696Value` = 0, `SoftLandingEnabled` = 0 | L | none | on |
| disable-activity-history | No activity history upload | HKLM `SOFTWARE\Policies\Microsoft\Windows\System`: `EnableActivityFeed` = 0, `PublishUserActivities` = 0, `UploadUserActivities` = 0 | L | none | on |
| telemetry-minimum | Lowest telemetry level allowed by the edition | HKLM `SOFTWARE\Policies\Microsoft\Windows\DataCollection` `AllowTelemetry` = 0 on Enterprise/Education; on Home/Pro Windows treats it as the required minimum. **UI text must say this plainly.** | L | none | on |
| disable-tailored-experiences | Tailored experiences off | HKCU `Software\Microsoft\Windows\CurrentVersion\Privacy` `TailoredExperiencesWithDiagnosticDataEnabled` = 0 | L | none | on |

## Performance and Gaming
| id | What | Action | Risk | Restart | Default |
|---|---|---|---|---|---|
| disable-game-dvr | Turn off Game DVR background capture | HKCU `System\GameConfigStore` `GameDVR_Enabled` = 0; HKCU `Software\Microsoft\Windows\CurrentVersion\GameDVR` `AppCaptureEnabled` = 0 | L | none | on |
| startup-delay | Remove the startup app delay | HKCU `Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize` `StartupDelayInMSec` = 0 (create key) | L | signout | on |
| delivery-optimization-off | Don't upload updates to other PCs | HKLM `SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config` `DODownloadMode` = 0 (HTTP only) | L | none | on |
| visual-effects-balanced | Fewer animations (optional) | HKCU `Control Panel\Desktop\WindowMetrics` `MinAnimate` = "0" and related; verify exactly which values the UI toggle writes before shipping | M | signout | off |

## Power
| id | What | Action | Risk | Restart | Default |
|---|---|---|---|---|---|
| ultimate-performance-plan | Ultimate Performance plan (desktop only) | `powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61` then set active; record prior active scheme. Not available on some systems/SKUs, handle the failure | M | none | desktop: on, laptop: skip |
| balanced-plan | Ensure Balanced plan (laptop) | `powercfg /setactive SCHEME_BALANCED` | L | none | laptop: on |
| hibernate-off | Disable hibernation (desktop, frees disk space; breaks Fast Startup) | `powercfg /hibernate off`. Undo: `on` | M | reboot | off |

## Network
| id | What | Action | Risk | Restart | Default |
|---|---|---|---|---|---|
| (none by default) | Do not ship DNS or TCP "boosters". Tools page has Flush DNS and Reset network only | | | | |

## Windows 11 extras (verify each, they changed across builds)
| id | What | Action | Risk | Default |
|---|---|---|---|---|
| hide-widgets | Remove the Widgets button | HKCU `...\Explorer\Advanced` `TaskbarDa` = 0. May be blocked by newer builds, check | L | off |
| hide-task-view | Hide Task View button | HKCU `...\Explorer\Advanced` `ShowTaskViewButton` = 0 | L | off |
| hide-copilot-button | Hide Copilot button | verify current key for the installed build; the old `TurnOffWindowsCopilot` policy was deprecated. If no stable key exists, drop this tweak | L | off |

## Windows Update controls (Tools, not default tweaks)
- Pause updates for N days using documented settings only.
- Set active hours.
- Never disable the update service.

## Protected list (engine refuses these)
Mirror of `05-detection-and-safety.md`: Defender, Windows Update service enablement, Firewall, Microsoft Store, Edge, `Microsoft.DesktopAppInstaller`, core shell packages and services, UAC level, `bcdedit`/boot config, Secure Boot/TPM, licensing or activation.

Protected Appx packages (never remove): `Microsoft.WindowsStore`, `Microsoft.DesktopAppInstaller`, `Microsoft.StorePurchaseApp`, `Microsoft.Windows.ShellExperienceHost`, `Microsoft.Windows.StartMenuExperienceHost`, `Microsoft.SecHealthUI`, `Microsoft.WindowsTerminal` (do not remove if present), `MicrosoftWindows.Client.*`, `Microsoft.UI.Xaml.*`, `Microsoft.VCLibs.*`.

## Deliberately not included
- "Disable Windows Defender", "disable updates", "disable UAC", "disable SmartScreen".
- Registry "cleaners", RAM "boosters", prefetch/superfetch removal on HDD systems.
- Removal of preinstalled Appx apps in v1. (Phase 2 candidate: a short, conservative, user-picked list, each restorable by reinstall from the Store. Needs Wit's decision.)
- Anything that edits boot settings.

## Verification report (M2 deliverable)
`docs/tweaks-verification.md`: id, source consulted, VM build tested, apply result, undo result, date, `verified` flag set.
