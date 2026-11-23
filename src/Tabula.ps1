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
    foreach ($file in (Get-ChildItem (Join-Path $srcRoot 'Core') -Filter *.ps1 | Sort-Object Name)) { . $file.FullName }
    . (Join-Path $srcRoot 'UI\UI.ps1')
}

if ($Version) {
    'Tabula {0} (built {1}, commit {2})' -f $script:TabulaBuild.Version, $script:TabulaBuild.Built, $script:TabulaBuild.Commit
    return
}

# M0: dispatch exists, engines arrive in M1 (CLI) and M3 (GUI).
Write-Output ('Tabula {0}. Mode {1} is not implemented yet.' -f $script:TabulaBuild.Version, $Mode)
