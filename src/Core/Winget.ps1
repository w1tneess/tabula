# winget wrapper: detect, install, export. Official package IDs only; the command line is built here, never taken from JSON.

# Exit codes checked against winget 1.29 with `winget error --input <code>`. Keys are the 8-digit hex of the Int32 exit code.
# Anything not listed is a failure. Re-check on new winget releases rather than trusting this table.
$script:TabulaWingetCodes = @{
    '00000000' = @{ Status = 'applied'; Reason = ''; Reboot = $false }
    '8A150061' = @{ Status = 'skipped'; Reason = 'already installed'; Reboot = $false }          # PACKAGE_ALREADY_INSTALLED
    '8A15002B' = @{ Status = 'skipped'; Reason = 'already installed, no applicable update'; Reboot = $false }  # UPDATE_NOT_APPLICABLE
    '8A150109' = @{ Status = 'applied'; Reason = 'restart needed to finish'; Reboot = $true }      # INSTALL_REBOOT_REQUIRED_TO_FINISH
}

# Flags an app may add through extraArgs. --override is deliberately absent in v1. Each takes one value.
$script:TabulaWingetExtraFlags = @('--architecture', '--locale', '--version')

$script:TabulaWingetPathCache = $null

function Test-TabulaMicrosoftSigned {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        ($s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -match '(^|, )O=Microsoft Corporation(,|$)')
    }
    catch { $false }
}

function Get-TabulaWingetPath {
    # Found through the installed App Installer package, not PATH: this runs elevated, and a winget.exe earlier on
    # PATH (or in the current folder) would run with admin rights. The exe must also be signed by Microsoft.
    # The per-user alias in WindowsApps cannot be signature-checked, so it is not used.
    [CmdletBinding()]
    param()
    if ($script:TabulaWingetPathCache -and (Test-Path -LiteralPath $script:TabulaWingetPathCache)) { return $script:TabulaWingetPathCache }
    $pkg = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (-not $pkg) { return $null }
    $exe = Join-Path $pkg.InstallLocation 'winget.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $null }
    if (-not (Test-TabulaMicrosoftSigned -Path $exe)) {
        Write-TabulaLog "winget.exe at $exe is not signed by Microsoft. Not using it." -Level ERROR
        return $null
    }
    $script:TabulaWingetPathCache = $exe
    $exe
}

function Get-TabulaWingetVersion {
    [CmdletBinding()]
    param()
    $path = Get-TabulaWingetPath
    if (-not $path) { return $null }
    $r = Invoke-TabulaNative -FilePath $path -ArgumentList @('--version') -TimeoutSec 30 -Utf8
    if ($r.ExitCode -eq 0) { $r.Output.Trim() } else { $null }
}

function Register-TabulaWinget {
    # Step one of the bootstrap: register App Installer if it is present but not registered for this user.
    # Fetching the bundle from aka.ms/getwinget (with dependencies and a signature check) is not built yet.
    [CmdletBinding()]
    param()
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
    }
    catch { Write-TabulaLog "App Installer registration failed: $($_.Exception.Message)" -Level WARN }
    [bool](Get-TabulaWingetPath)
}

function Assert-TabulaWinget {
    # Ensures winget exists and refreshes sources once. Returns $true when apps can be installed.
    [CmdletBinding()]
    param()
    if (-not (Get-TabulaWingetPath)) {
        Write-TabulaLog 'winget not found. Trying to register App Installer.' -Level WARN
        if (-not (Register-TabulaWinget)) {
            Write-TabulaLog 'winget is not available. Apps will be skipped.' -Level ERROR
            return $false
        }
    }
    Write-TabulaLog ('winget {0}' -f (Get-TabulaWingetVersion))
    $r = Invoke-TabulaNative -FilePath (Get-TabulaWingetPath) -ArgumentList @('source', 'update') -TimeoutSec 120 -Utf8
    if ($r.ExitCode -ne 0) { Write-TabulaLog ('winget source update exited {0}' -f $r.ExitCode) -Level WARN }
    $true
}

function New-TabulaWingetInstallArgs {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App)
    $id = [string]$App['wingetId']
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { throw "Invalid winget ID '$id'" }
    $a = New-Object System.Collections.Generic.List[string]
    $a.AddRange([string[]]@('install', '--id', $id, '-e', '--accept-package-agreements', '--accept-source-agreements', '--silent'))
    # --scope only when the app asks for it: not every installer supports machine scope.
    if ($App['scope']) {
        if ($App['scope'] -notin 'machine', 'user') { throw "Invalid scope '$($App['scope'])'" }
        $a.AddRange([string[]]@('--scope', [string]$App['scope']))
    }
    $extra = @($App['extraArgs'] | Where-Object { $null -ne $_ })
    for ($i = 0; $i -lt $extra.Count; $i += 2) {
        if ($script:TabulaWingetExtraFlags -notcontains $extra[$i]) { throw "winget flag '$($extra[$i])' is not allowed" }
        if ($i + 1 -ge $extra.Count -or ([string]$extra[$i + 1]).StartsWith('-')) { throw "winget flag '$($extra[$i])' needs a value" }
        $a.Add([string]$extra[$i]); $a.Add([string]$extra[$i + 1])
    }
    , $a.ToArray()
}

function ConvertTo-TabulaWingetStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ExitCode)
    $key = '{0:X8}' -f $ExitCode
    if ($script:TabulaWingetCodes.ContainsKey($key)) { return $script:TabulaWingetCodes[$key] }
    @{ Status = 'failed'; Reason = ('winget exit code 0x{0}' -f $key); Reboot = $false }
}

function Test-TabulaAppInstalled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WingetId)
    $r = Invoke-TabulaNative -FilePath (Get-TabulaWingetPath) -ArgumentList @('list', '--id', $WingetId, '-e', '--accept-source-agreements') -TimeoutSec 120 -Utf8
    # Exit 0 with the ID in the table means installed; "no packages" is a non-zero exit (0x8A150014).
    ($r.ExitCode -eq 0 -and $r.Output -match [regex]::Escape($WingetId))
}

function New-TabulaResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$Id, [string]$Name = '',
        [Parameter(Mandatory)][ValidateSet('applied', 'skipped', 'failed', 'dryrun', 'reverted', 'cancelled')][string]$Status,
        [string]$Reason = '', [string]$Detail = '', [string]$Restart = 'none'
    )
    [pscustomobject]@{ Kind = $Kind; Id = $Id; Name = $Name; Status = $Status; Reason = $Reason; Detail = $Detail; Restart = $Restart }
}

function Install-TabulaApp {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App, [switch]$DryRun, [int]$TimeoutSec = 900)
    $id = [string]$App['id']; $name = [string]$App['name']

    if ($App['source'] -ne 'winget') {
        return New-TabulaResult -Kind app -Id $id -Name $name -Status skipped -Reason ('manual install: ' + $App['officialUrl'])
    }
    $winget = Get-TabulaWingetPath
    if (-not $winget -and $DryRun) { return New-TabulaResult -Kind app -Id $id -Name $name -Status dryrun -Reason 'winget not found; a real run would try to register App Installer first' }
    if (-not $winget) { return New-TabulaResult -Kind app -Id $id -Name $name -Status failed -Reason 'winget is not available' }

    try {
        $wingetId = [string]$App['wingetId']
        $installArgs = New-TabulaWingetInstallArgs -App $App
        if (Test-TabulaAppInstalled -WingetId $wingetId) {
            return New-TabulaResult -Kind app -Id $id -Name $name -Status skipped -Reason 'already installed'
        }
        if ($DryRun) {
            # Availability check only. Nothing is installed.
            $show = Invoke-TabulaNative -FilePath $winget -ArgumentList @('show', '--id', $wingetId, '-e', '--accept-source-agreements') -TimeoutSec 120 -Utf8
            $detail = 'winget ' + (ConvertTo-TabulaArgString $installArgs)
            $reason = if ($show.ExitCode -eq 0) { 'would install' } else { 'would install, but winget show did not find the package' }
            return New-TabulaResult -Kind app -Id $id -Name $name -Status dryrun -Reason $reason -Detail $detail
        }
        $r = Invoke-TabulaNative -FilePath $winget -ArgumentList $installArgs -TimeoutSec $TimeoutSec -Utf8
        if ($r.TimedOut) {
            Write-TabulaLog ("app:{0} timed out after {1}s. {2}" -f $id, $TimeoutSec, (Get-TabulaOutputTail $r.Output)) -Level ERROR
            return New-TabulaResult -Kind app -Id $id -Name $name -Status failed -Reason "timed out after $TimeoutSec s"
        }
        $map = ConvertTo-TabulaWingetStatus -ExitCode $r.ExitCode
        $restart = if ($map.Reboot) { 'reboot' } else { 'none' }
        if ($map.Status -eq 'failed') {
            Write-TabulaLog ('app:{0} failed ({1}). {2}' -f $id, $map.Reason, (Get-TabulaOutputTail $r.Output)) -Level ERROR
        }
        else { Write-TabulaLog ('app:{0} {1}' -f $id, $map.Status) }
        New-TabulaResult -Kind app -Id $id -Name $name -Status $map.Status -Reason $map.Reason -Restart $restart
    }
    catch {
        Write-TabulaLog ('app:{0} failed: {1}' -f $id, $_.Exception.Message) -Level ERROR
        New-TabulaResult -Kind app -Id $id -Name $name -Status failed -Reason $_.Exception.Message
    }
}

function ConvertTo-TabulaAppId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WingetId)
    ($WingetId.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Export-TabulaApps {
    # Writes installed winget packages as an apps.json-shaped file. Entries already in the app list keep
    # their metadata; new ones are marked for review because winget export has no vendor URL or category.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputPath, $ExistingApps = @())
    $winget = Get-TabulaWingetPath
    if (-not $winget) { throw 'winget is not available' }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('tabula-export-{0}.json' -f [guid]::NewGuid().ToString('N'))
    try {
        $r = Invoke-TabulaNative -FilePath $winget -ArgumentList @('export', '-o', $tmp, '--accept-source-agreements') -TimeoutSec 300 -Utf8
        if (-not (Test-Path -LiteralPath $tmp)) { throw ('winget export produced no file (exit {0}). {1}' -f $r.ExitCode, (Get-TabulaOutputTail $r.Output)) }
        $export = ConvertTo-TabulaData ([IO.File]::ReadAllText($tmp) | ConvertFrom-Json)
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    $byWingetId = @{}
    foreach ($a in $ExistingApps) { if ($a['wingetId']) { $byWingetId[([string]$a['wingetId']).ToLower()] = $a } }

    $apps = New-Object System.Collections.ArrayList
    $new = 0; $kept = 0
    foreach ($src in @($export['Sources'] | Where-Object { $null -ne $_ })) {
        foreach ($pkg in @($src['Packages'] | Where-Object { $null -ne $_ })) {
            $wid = [string]$pkg['PackageIdentifier']
            if (-not $wid) { continue }
            if ($byWingetId.ContainsKey($wid.ToLower())) { [void]$apps.Add($byWingetId[$wid.ToLower()]); $kept++; continue }
            [void]$apps.Add([ordered]@{
                    id = (ConvertTo-TabulaAppId $wid); name = $wid; category = 'Utilities'; source = 'winget'
                    wingetId = $wid; officialUrl = $null; defaultSelected = $false
                    notes = 'Exported. Review name, category and officialUrl before use.'
                })
            $new++
        }
    }
    $json = ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; apps = $apps }) -Depth 6
    [IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
    Write-TabulaLog ('exported {0} apps ({1} already in the list, {2} new) to {3}' -f $apps.Count, $kept, $new, $OutputPath)
    [pscustomobject]@{ Path = $OutputPath; Total = $apps.Count; New = $new; Known = $kept }
}
