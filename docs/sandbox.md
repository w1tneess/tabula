# Verifying in Windows Sandbox

Windows Sandbox is a disposable Windows 11 session. Everything inside is gone when it closes. Use it to try tweaks and a real apply without touching your PC.

## One-time setup (needs administrator and a restart)
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

## Each time
```powershell
./sandbox/Start-TabulaSandbox.ps1
```
It builds `dist/tabula.ps1`, writes a `.wsb` file and opens the sandbox. `dist` and `sandbox` are mapped read-only; `sandbox-out` (git-ignored) is the only writable folder. Inside, a script records the OS build, whether App Installer (winget) exists, and a dry run to `sandbox-out\probe.txt` and `dryrun.log`. `tabula.ps1` is on the Desktop. The sandbox user is an administrator, so applying works.

## Limits
- One image: the Windows 11 build of this PC. It cannot test Windows 10, other editions, a laptop, or 125 to 200 % scaling on a second monitor.
- It may not have winget registered. That is itself a useful result: record it.
- Status: the launcher and the `.wsb` file were generated and parsed here. Windows Sandbox is not enabled on this PC, so nothing has run inside it yet.
