# Runs inside Windows Sandbox at logon (mapped read-only as C:\TabulaSetup). Records facts about the clean machine,
# then does a dry run so the first thing you see is what Tabula would do there. Nothing here changes the system.
param([switch]$Winget, [switch]$Verify, [switch]$Gui)
$out = 'C:\Out'
$probe = Join-Path $out 'probe.txt'
$os = Get-CimInstance Win32_OperatingSystem
$winget = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
@(
    'os: {0} build {1}' -f $os.Caption, $os.BuildNumber
    'user: {0}' -f [Environment]::UserName
    'app installer: {0}' -f $(if ($winget) { $winget.Version } else { 'not installed' })
    'edition: {0}' -f (Get-CimInstance Win32_OperatingSystem).OperatingSystemSKU
) | Set-Content -Encoding UTF8 $probe
if ($Winget) {
    # Windows Sandbox has no winget. This is Microsoft's documented bootstrap (learn.microsoft.com/windows/package-manager/winget).
    $progressPreference = 'silentlyContinue'
    try {
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
        Repair-WinGetPackageManager -AllUsers
        'winget bootstrap: ok' | Add-Content -Encoding UTF8 $probe
    }
    catch { ('winget bootstrap failed: ' + $_.Exception.Message) | Add-Content -Encoding UTF8 $probe }
    $winget = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    ('app installer after bootstrap: {0}' -f $(if ($winget) { $winget.Version } else { 'not installed' })) | Add-Content -Encoding UTF8 $probe
}
Copy-Item 'C:\Tabula\tabula.ps1' (Join-Path $env:USERPROFILE 'Desktop\tabula.ps1') -Force
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Tabula\tabula.ps1' -Mode Auto -DryRun -LogPath (Join-Path $out 'dryrun.log') | Out-Null
('dry run exit code: {0}' -f $LASTEXITCODE) | Add-Content -Encoding UTF8 $probe
if ($Verify) { & 'C:\TabulaSetup\verify-tweaks.ps1' }
# -Gui really applies, cancels and undoes through the window. Only ever in the sandbox.
if ($Gui) { & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File 'C:\TabulaSetup\gui-run.ps1' }
Write-Host 'Tabula Sandbox is ready. tabula.ps1 is on the Desktop.'
Write-Host 'Window:  powershell -STA -ExecutionPolicy Bypass -File $env:USERPROFILE\Desktop\tabula.ps1'
Write-Host 'Logs and the probe are in C:\Out, which is the sandbox-out folder on the host.'
