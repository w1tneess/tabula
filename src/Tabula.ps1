[CmdletBinding()]
param(
    [ValidateSet('Gui', 'Auto', 'Apps', 'Tweaks', 'Undo', 'Export')]
    [string]$Mode = 'Gui',
    [string]$Preset = 'Standard',
    [switch]$DryRun,
    [switch]$NoRestorePoint,
    [string[]]$Apps,
    [string[]]$Skip,
    [switch]$Yes,
    [switch]$IncludeHighRisk,
    [string]$LogPath,
    [switch]$Version
)

# Everything above the marker is the script's param block; build.ps1 swaps the
# marker line for the bundled modules and embedded config. Keep it on its own line.
# @@BUNDLE@@

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TabulaBuild -Scope Script -ErrorAction SilentlyContinue)) {
    # Dev run from src/: load the modules from disk instead of a bundle.
    $script:TabulaBuild = @{ Version = 'dev'; Built = 'n/a'; Commit = 'n/a' }
    $srcRoot = Split-Path -Parent $PSCommandPath
    $script:TabulaRoot = Split-Path -Parent $srcRoot
    foreach ($file in (Get-ChildItem (Join-Path $srcRoot 'Core') -Filter *.ps1 | Sort-Object Name)) { . $file.FullName }
    . (Join-Path $srcRoot 'UI\UI.ps1')
}

if ($Version) {
    'Tabula {0} (built {1}, commit {2})' -f $script:TabulaBuild.Version, $script:TabulaBuild.Built, $script:TabulaBuild.Commit
    return
}

$exitCode = Invoke-TabulaMain -Mode $Mode -Preset $Preset -DryRun:$DryRun -NoRestorePoint:$NoRestorePoint `
    -Apps $Apps -Skip $Skip -Yes:$Yes -IncludeHighRisk:$IncludeHighRisk -LogPath $LogPath

# `exit` would close the user's console when this runs through iex, so only exit when run as a file.
if ($PSCommandPath) { exit $exitCode } else { $global:LASTEXITCODE = $exitCode }
