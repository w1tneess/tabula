# Builds Tabula and opens it in a disposable Windows Sandbox. Run from the repo root in Windows PowerShell 5.1.
# -NoLaunch writes the .wsb file and stops (used by the tests).
[CmdletBinding()]
param([switch]$NoLaunch, [switch]$Winget, [switch]$Verify)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
& (Join-Path $repo 'build.ps1') | Out-Null
$outDir = Join-Path $repo 'sandbox-out'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Dist and the setup script go in read-only. Only sandbox-out is writable from inside.
$map = {
    param($host_, $guest, $ro)
    '<MappedFolder><HostFolder>{0}</HostFolder><SandboxFolder>{1}</SandboxFolder><ReadOnly>{2}</ReadOnly></MappedFolder>' -f [Security.SecurityElement]::Escape($host_), $guest, $ro
}
$xml = @(
    '<Configuration>'
    '<vGPU>Default</vGPU><Networking>Default</Networking><ClipboardRedirection>Enable</ClipboardRedirection>'
    '<MappedFolders>'
    (& $map (Join-Path $repo 'dist') 'C:\Tabula' 'true')
    (& $map (Join-Path $repo 'sandbox') 'C:\TabulaSetup' 'true')
    (& $map (Join-Path $repo 'src') 'C:\TabulaRepo\src' 'true')
    (& $map (Join-Path $repo 'config') 'C:\TabulaRepo\config' 'true')
    (& $map $outDir 'C:\Out' 'false')
    '</MappedFolders>'
    ('<LogonCommand><Command>powershell.exe -NoExit -ExecutionPolicy Bypass -File C:\TabulaSetup\inside.ps1' + $(if ($Winget) { ' -Winget' }) + $(if ($Verify) { ' -Verify' }) + '</Command></LogonCommand>')
    '</Configuration>'
) -join "`n"
$wsb = Join-Path $env:TEMP 'tabula.wsb'
[IO.File]::WriteAllText($wsb, $xml)
Write-Host "Wrote $wsb"
if ($NoLaunch) { return $wsb }

$feature = Get-CimInstance Win32_OptionalFeature -Filter "Name='Containers-DisposableClientVM'"
if (-not $feature -or $feature.InstallState -ne 1) {
    Write-Host 'Windows Sandbox is not turned on. In an elevated PowerShell run:'
    Write-Host '  Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
    Write-Host 'Restart when asked, then run this script again.'
    exit 1
}
Start-Process $wsb
