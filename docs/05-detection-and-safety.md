# 05 Detection and safety

## Machine profile (`Get-TabulaProfile`)
Returns one object, used by presets and `appliesTo` rules. Use CIM (`Get-CimInstance`), not the deprecated WMI cmdlets.

| Field | Source | Notes |
|---|---|---|
| `Os.Caption` | `Win32_OperatingSystem.Caption` | e.g. "Microsoft Windows 11 Pro" |
| `Os.Build` | `[Environment]::OSVersion.Version.Build` or `Win32_OperatingSystem.BuildNumber` | Windows 11 is build 22000 or higher. Windows 10 is 19041 to 19045. |
| `Os.DisplayVersion` | registry `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` value `DisplayVersion` (e.g. 24H2), fall back to `ReleaseId` | |
| `Os.Edition` | `Win32_OperatingSystem.OperatingSystemSKU` or `EditionID` registry value | Normalise to Home, Pro, Enterprise, Education, Other |
| `Os.Is11` | Build >= 22000 | |
| `Chassis` | `Win32_SystemEnclosure.ChassisTypes` (8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 = portable) and presence of `Win32_Battery` | Prefer "battery present" as the tiebreaker. Values: `laptop`, `desktop`, `unknown` |
| `Storage.SystemDiskType` | `Get-PhysicalDisk` mapped to the disk holding `C:` (`MediaType`: SSD, HDD, Unspecified) | NVMe may report Unspecified on some VMs, treat as `ssd` if `BusType` is NVMe |
| `Ram.GB` | `Win32_ComputerSystem.TotalPhysicalMemory` | rounded |
| `Cpu.Name` | `Win32_Processor.Name` | |
| `Gpu[]` | `Win32_VideoController` (Name, vendor guess from name) | Vendors: NVIDIA, AMD, Intel, Other. Used only for suggestions, never to install drivers in v1. |
| `IsVm` | `Win32_ComputerSystem.Model` / `Manufacturer` match common hypervisors | In a VM, skip power-plan and hibernation tweaks |
| `IsAdmin` | `WindowsPrincipal.IsInRole(Administrator)` | |
| `User` | `[Security.Principal.WindowsIdentity]::GetCurrent().Name` and the interactive user (via `Win32_ComputerSystem.UserName`) | Warn if different |
| `WingetPresent` | `Get-Command winget` + version | |
| `PendingReboot` | CBS RebootPending, WU RebootRequired, PendingFileRenameOperations | Warn, do not block |

Unsupported systems: Windows older than 10 version 2004, or Server SKUs. Show a clear message and exit (GUI shows the message, does not crash).

Detection must never throw. Wrap each probe, log failures, and set the field to `unknown`.

## How the profile drives choices
- `Chassis=laptop`: do not set Ultimate Performance; prefer Balanced; keep hibernation (battery safety); skip "disable power throttling".
- `Chassis=desktop`: allow Ultimate or High Performance plan; hibernation off is a low-risk option.
- `Storage=ssd`: no defrag tweaks; keep TRIM defaults. `hdd`: leave Superfetch/SysMain alone.
- `Os.Is11`: allow Windows 11 interface tweaks (classic context menu, taskbar alignment). Skip them on 10.
- `Edition=Home`: skip tweaks that rely on Group Policy keys honoured only on Pro or higher, or mark them "may not take effect on Home".
- `IsVm`: skip power tweaks.
- Everything unsupported is **shown greyed with the reason**, not hidden. Transparent behaviour.

## Safety model

### 1. Restore point
- `Checkpoint-Computer -Description "Tabula <runId>" -RestorePointType MODIFY_SETTINGS`.
- Requires System Protection on for `C:`. If it is off: offer to enable it (`Enable-ComputerRestore -Drive "C:\"`) with a confirmation, or continue without it with a warning. In `-Mode Auto -Yes`, enabling it is allowed; log it.
- Windows throttles restore points (default one per 24 hours). Handle that: catch the failure, log "restore point skipped: throttled", and continue. Do not edit `SystemRestorePointCreationFrequency` in v1 unless the user opts in.
- Record result in `state.json`.

### 2. Prior-state capture and undo
- Before each action, read and store the prior state (registry value, service start type, task state, power scheme).
- State written before the change (write-ahead). See `03-config-schemas.md`.
- Undo reverses in reverse order. If a key did not exist before, undo deletes it. If a value did not exist, undo deletes the value.
- If prior state is missing (state file lost), the UI still offers "Reset this tweak to Windows default" only where a documented default exists in the tweak's `undoActions`. Otherwise it says it cannot, and points to the restore point.

### 3. Dry run
`-DryRun` goes through detection, planning and every action's "would change" computation and prints a table: item, current value, target value, result (`would apply`, `already set`, `not applicable`). Nothing is written, no restore point, no installs. Winget in dry run: show the command that would run, check availability with `winget show` only.

### 4. Logging
- Format: `2026-11-23 20:15:03 [INFO] tweak:classic-context-menu applied`.
- Levels: INFO, WARN, ERROR, DEBUG (DEBUG only with `-Verbose`).
- Log every command line run (winget args) and every registry change (path, name, old, new).
- UI log panel reads from the same stream. "Copy log" button.
- No personal data beyond the Windows user name and machine name. Do not log tokens or full environment dumps.

### 5. Winget handling
- Detect with `Get-Command winget -ErrorAction SilentlyContinue`. If missing, bootstrap: try registering App Installer (`Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe`). If that fails, fetch the official `https://aka.ms/getwinget` bundle (and its dependencies per Microsoft's docs) and install. Verify the file's Authenticode signature is Microsoft before installing. If bootstrap fails, tell the user plainly and run tweaks only.
- Accept source agreements non-interactively (`--accept-source-agreements`). Refresh sources once at start (`winget source update`).
- Per-app: install, capture exit code and last lines of output. Map known exit codes (already installed, no applicable upgrade, reboot required) to statuses. Unknown non-zero = failed with output excerpt in the log.
- Timeout per package (default 15 min) so a hung installer does not freeze the run. Log and continue.
- Installers that need a reboot: record, continue, show in summary.

### 6. Protected list
The engine **refuses** (build-time test and runtime guard) any tweak that touches:
- Windows Defender / Microsoft Defender services, real-time protection, or its policy keys
- Windows Update service enablement (`wuauserv`, `UsoSvc`, `bits` set to Disabled) (scheduling and pause are allowed)
- Windows Firewall
- Microsoft Store, Edge (installation or removal), `Microsoft.DesktopAppInstaller`
- Core shell packages and services (Explorer shell, Start menu host, `ShellExperienceHost`, `StartMenuExperienceHost`)
- User Account Control level
- Boot configuration (`bcdedit`), secure boot, TPM
- Windows licensing or activation in any form

### 7. Confirmation points
- Before applying any plan with a `medium` or `high` risk item.
- Before Tools that delete (temp cleanup), reset (network), or take long (DISM).
- Never prompt in `-Yes` mode, but `high` risk items are skipped in `-Yes` mode unless `-IncludeHighRisk` is passed. (Add that param.)

### 8. Failure handling
- A failure in one item never stops the run.
- If the restore point fails and the user did not opt out, ask (GUI) or warn and continue (unattended).
- Crash mid-run: next launch reads `state.json`, sees an incomplete run, and offers "Finish undo of incomplete run".

## Things that need careful verification (do not skip)
- `Checkpoint-Computer` behaviour on Windows 10 vs 11 and when System Protection is off.
- HKCU writes when the elevated account is not the interactive user.
- `winget` exit codes (they change between versions; test on the current stable release rather than trusting a table).
- Telemetry policy values: `AllowTelemetry=0` is honoured only on Enterprise/Education; on Home/Pro the effective minimum is 1 (Required). The tweak must say so and not promise more than it delivers.
