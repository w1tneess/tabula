# Config loading, preset resolution and the plan runner (tweaks first, then apps).

$script:TabulaRoot = $null      # repo root, set by the dev entry point; bundled builds embed the config instead
$script:TabulaCancel = $false   # checked between items. A running winget package is left to finish.

function Get-TabulaConfig {
    [CmdletBinding()]
    param([string]$ConfigRoot)
    $embedded = Get-Variable -Name TabulaConfig -Scope Script -ErrorAction SilentlyContinue
    $cfg = @{}
    foreach ($n in 'apps', 'tweaks', 'presets') {
        if (-not $ConfigRoot -and $embedded) { $text = $embedded.Value["$n.json"] }
        else {
            $root = if ($ConfigRoot) { $ConfigRoot } else { Join-Path $script:TabulaRoot 'config' }
            $text = [IO.File]::ReadAllText((Join-Path $root "$n.json"))
        }
        $obj = ConvertTo-TabulaData ($text | ConvertFrom-Json)
        if ($obj['schemaVersion'] -ne 1) { throw "$n.json: unsupported schemaVersion" }
        $cfg[$n] = @($obj[$n] | Where-Object { $null -ne $_ })
    }
    $cfg
}

function Get-TabulaProfileTraits {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)
    $t = New-Object System.Collections.Generic.List[string]
    if ($Profile.Chassis -in 'laptop', 'desktop') { $t.Add([string]$Profile.Chassis) }
    if ($Profile.Os.Build -is [int]) { $t.Add($(if ($Profile.Os.Is11) { 'win11' } else { 'win10' })) }
    if ($Profile.Storage.SystemDiskType -in 'ssd', 'hdd') { $t.Add([string]$Profile.Storage.SystemDiskType) }
    , $t.ToArray()
}

function Resolve-TabulaPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config, [Parameter(Mandatory)]$Profile,
        [string]$Preset = 'Standard',
        [ValidateSet('Both', 'Tweaks', 'Apps')][string]$Scope = 'Both',
        [string[]]$Apps = @(), [string[]]$Skip = @(), [string[]]$Tweaks = @(),
        [switch]$IncludeHighRisk, [switch]$Yes,
        [switch]$Exact   # use only -Tweaks and -Apps, not the preset's lists (the window plans from ticked rows)
    )
    $p = @($Config['presets'] | Where-Object { $_['id'] -eq $Preset }) | Select-Object -First 1
    if (-not $p) { throw "Unknown preset '$Preset'" }

    $tweakIds = New-Object System.Collections.Generic.List[string]
    $appIds = New-Object System.Collections.Generic.List[string]
    if ($p['tweaks'] -is [string] -and $p['tweaks'] -eq 'defaultOn') {
        foreach ($t in $Config['tweaks']) { if ($t['defaultOn']) { $tweakIds.Add([string]$t['id']) } }
    }
    else { foreach ($i in @($p['tweaks'] | Where-Object { $null -ne $_ })) { $tweakIds.Add([string]$i) } }
    if ($p['apps'] -is [string] -and $p['apps'] -eq 'defaultSelected') {
        foreach ($a in $Config['apps']) { if ($a['defaultSelected']) { $appIds.Add([string]$a['id']) } }
    }
    else { foreach ($i in @($p['apps'] | Where-Object { $null -ne $_ })) { $appIds.Add([string]$i) } }

    # Overrides are keyed by machine traits and add or remove IDs, so one preset adapts per machine.
    if ($p['overrides']) {
        foreach ($trait in (Get-TabulaProfileTraits -Profile $Profile)) {
            $o = $p['overrides'][$trait]
            if (-not $o) { continue }
            foreach ($i in @($o['addTweaks'] | Where-Object { $null -ne $_ })) { if (-not $tweakIds.Contains([string]$i)) { $tweakIds.Add([string]$i) } }
            foreach ($i in @($o['excludeTweaks'] | Where-Object { $null -ne $_ })) { [void]$tweakIds.Remove([string]$i) }
            foreach ($i in @($o['addApps'] | Where-Object { $null -ne $_ })) { if (-not $appIds.Contains([string]$i)) { $appIds.Add([string]$i) } }
            foreach ($i in @($o['excludeApps'] | Where-Object { $null -ne $_ })) { [void]$appIds.Remove([string]$i) }
        }
    }
    if ($Exact) { $tweakIds.Clear(); $appIds.Clear() }
    foreach ($i in $Tweaks) { if (-not $tweakIds.Contains($i)) { $tweakIds.Add($i) } }
    foreach ($i in $Apps) { if (-not $appIds.Contains($i)) { $appIds.Add($i) } }
    foreach ($i in $Skip) { [void]$appIds.Remove($i) }

    $plan = New-Object System.Collections.Generic.List[object]

    if ($Scope -ne 'Apps') {
        $known = @($Config['tweaks'] | ForEach-Object { [string]$_['id'] })
        foreach ($i in $tweakIds) { if ($known -notcontains $i) { Write-TabulaLog "preset '$Preset' names unknown tweak '$i'" -Level WARN } }
        foreach ($t in $Config['tweaks']) {
            if (-not $tweakIds.Contains([string]$t['id'])) { continue }
            $hold = $null
            if (-not $t['verified']) { $hold = 'unverified (experimental)' }
            elseif ($t['risk'] -eq 'high' -and $Yes -and -not $IncludeHighRisk) { $hold = 'high risk, needs -IncludeHighRisk' }
            $plan.Add([pscustomobject]@{ Kind = 'tweak'; Id = [string]$t['id']; Name = [string]$t['name']; Risk = [string]$t['risk']; Item = $t; Hold = $hold })
        }
    }

    if ($Scope -ne 'Tweaks') {
        $byId = @{}
        foreach ($a in $Config['apps']) { $byId[[string]$a['id']] = $a }
        $seen = New-Object System.Collections.Generic.HashSet[string]
        $addApp = {
            param($id)
            if (-not $seen.Add($id)) { return }
            if (-not $byId.ContainsKey($id)) { Write-TabulaLog "unknown app '$id'" -Level WARN; return }
            $a = $byId[$id]
            # Dependencies go in first (a runtime before the app that needs it).
            foreach ($r in @($a['requires'] | Where-Object { $null -ne $_ })) { & $addApp ([string]$r) }
            $applies = Test-TabulaApplies -Tweak $a -Profile $Profile
            $hold = if ($applies.Applies) { $null } else { 'not applicable: ' + $applies.Reason }
            $plan.Add([pscustomobject]@{ Kind = 'app'; Id = $id; Name = [string]$a['name']; Risk = 'low'; Item = $a; Hold = $hold })
        }
        foreach ($i in $appIds) { & $addApp $i }
    }
    , $plan.ToArray()
}

function Confirm-TabulaPlan {
    # Medium and high risk items need a yes. -Yes skips every prompt (high risk is already held without -IncludeHighRisk).
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan, [switch]$Yes)
    $risky = @($Plan | Where-Object { -not $_.Hold -and $_.Risk -in 'medium', 'high' })
    if ($Yes -or $risky.Count -eq 0) { return $true }
    Write-Host ('{0} item(s) carry medium or high risk: {1}' -f $risky.Count, (($risky | ForEach-Object { $_.Id }) -join ', '))
    try { $answer = Read-Host 'Apply the plan? [y/N]' }
    catch { return $false }   # no console to ask on: do not guess
    $answer -match '^(y|yes)$'
}

function Send-TabulaProgress {
    # Progress is a courtesy to the window. A callback that throws must never stop a run that is changing the system.
    [CmdletBinding()]
    param($Callback, [Parameter(Mandatory)][hashtable]$Event)
    if (-not $Callback) { return }
    try { & $Callback $Event }
    catch { Write-TabulaLog ('progress callback failed: ' + $_.Exception.Message) -Level WARN }
}

function Test-TabulaCancelled {
    # $Control is a hashtable the caller flips from another thread (the window's Cancel button).
    [CmdletBinding()]
    param($Control)
    [bool]($script:TabulaCancel -or ($Control -and $Control['Cancel']))
}

function Invoke-TabulaPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Profile, [switch]$DryRun, [switch]$NoRestorePoint, [switch]$Yes,
        [scriptblock]$OnProgress, $Control
    )
    $script:TabulaCancel = $false
    $results = New-Object System.Collections.Generic.List[object]
    $runnable = @($Plan | Where-Object { -not $_.Hold })
    $state = $null; $run = $null
    $total = @($Plan).Count; $index = 0

    if (-not $DryRun -and $runnable.Count -gt 0) {
        $state = Get-TabulaState
        $run = New-TabulaRun -State $state -Profile $Profile
        if ($NoRestorePoint) { Write-TabulaLog 'restore point skipped by request (-NoRestorePoint)' -Level WARN }
        else {
            Send-TabulaProgress $OnProgress @{ Phase = 'prepare'; Text = 'Creating a restore point.' }
            $rp = New-TabulaRestorePoint -RunId $run['runId'] -AllowEnable:$Yes
            $run['restorePoint'] = $rp
            Save-TabulaState $state
            if (-not $rp['created']) { Write-TabulaLog 'continuing without a restore point' -Level WARN }
        }
    }
    if ($DryRun) { Write-TabulaLog 'dry run: nothing will be changed' }

    $wingetReady = $null
    foreach ($item in $Plan) {
        $index++
        if (Test-TabulaCancelled $Control) {
            $r = New-TabulaResult -Kind $item.Kind -Id $item.Id -Name $item.Name -Status cancelled -Reason 'run cancelled'
            $results.Add($r)
            Send-TabulaProgress $OnProgress @{ Phase = 'done'; Index = $index; Total = $total; Kind = $item.Kind; Id = $item.Id; Result = $r }
            continue
        }
        Send-TabulaProgress $OnProgress @{ Phase = 'start'; Index = $index; Total = $total; Kind = $item.Kind; Id = $item.Id; Name = $item.Name }
        if ($item.Hold) {
            $r = New-TabulaResult -Kind $item.Kind -Id $item.Id -Name $item.Name -Status skipped -Reason $item.Hold
        }
        elseif ($item.Kind -eq 'tweak') {
            try { $r = Invoke-TabulaTweakApply -Tweak $item.Item -Profile $Profile -State $state -Run $run -DryRun:$DryRun }
            catch {
                Write-TabulaLog ('tweak:{0} failed: {1}' -f $item.Id, $_.Exception.Message) -Level ERROR
                $r = New-TabulaResult -Kind tweak -Id $item.Id -Name $item.Name -Status failed -Reason $_.Exception.Message
            }
        }
        else {
            if (-not $DryRun -and $null -eq $wingetReady) { $wingetReady = Assert-TabulaWinget }
            if (-not $DryRun -and -not $wingetReady) {
                $r = New-TabulaResult -Kind app -Id $item.Id -Name $item.Name -Status failed -Reason 'winget is not available. Install App Installer from the Microsoft Store, then run again.'
            }
            else { $r = Install-TabulaApp -App $item.Item -DryRun:$DryRun }
        }
        if ($r.Status -in 'skipped', 'dryrun', 'cancelled') {
            Write-TabulaLog ('{0}:{1} {2}{3}' -f $r.Kind, $r.Id, $r.Status, $(if ($r.Reason) { " ($($r.Reason))" } else { '' }))
        }
        $results.Add($r)
        Send-TabulaProgress $OnProgress @{ Phase = 'done'; Index = $index; Total = $total; Kind = $item.Kind; Id = $item.Id; Result = $r }
    }
    if ($run) { Complete-TabulaRun -State $state -Run $run }
    , $results.ToArray()
}

function Invoke-TabulaUndo {
    [CmdletBinding()]
    param([switch]$DryRun, $Tweaks = @(), [scriptblock]$OnProgress, $Control)
    $script:TabulaCancel = $false
    $state = Get-TabulaState
    $run = Get-TabulaRevertibleRun -State $state
    if (-not $run) { return , @() }
    $names = @{}
    foreach ($t in $Tweaks) { $names[[string]$t['id']] = [string]$t['name'] }
    Write-TabulaLog ('undoing run {0} ({1})' -f $run['runId'], $run['status'])

    $results = New-Object System.Collections.Generic.List[object]
    $changes = @($run['changes'])
    $todo = @($changes | Where-Object { $_['status'] -in 'applied', 'pending' })   # skipped and failed changes are not touched
    $index = 0
    for ($i = $changes.Count - 1; $i -ge 0; $i--) {
        $c = $changes[$i]
        if ($c['status'] -notin 'applied', 'pending') { continue }
        $index++
        $id = [string]$c['tweakId']
        $name = if ($names.ContainsKey($id)) { $names[$id] } else { '' }
        # Cancelling an undo leaves the rest applied and the run revertible, so it can be resumed.
        if (Test-TabulaCancelled $Control) {
            $r = New-TabulaResult -Kind tweak -Id $id -Name $name -Status cancelled -Reason 'undo cancelled'
        }
        else {
            Send-TabulaProgress $OnProgress @{ Phase = 'start'; Index = $index; Total = $todo.Count; Kind = 'tweak'; Id = $id; Name = $name }
            $r = Invoke-TabulaTweakUndo -Change $c -State $state -DryRun:$DryRun -Name $name
        }
        $results.Add($r)
        Send-TabulaProgress $OnProgress @{ Phase = 'done'; Index = $index; Total = $todo.Count; Kind = 'tweak'; Id = $id; Result = $r }
    }
    if (-not $DryRun -and @($results | Where-Object { $_.Status -in 'failed', 'cancelled' }).Count -eq 0) {
        $run['status'] = 'reverted'
        Save-TabulaState $state
    }
    , $results.ToArray()
}

function Get-TabulaSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Results, [switch]$DryRun, [switch]$Undo)
    $r = @($Results)
    $count = { param($s) @($r | Where-Object { $_.Status -eq $s }).Count }
    $applied = & $count 'applied'; $skipped = & $count 'skipped'; $failed = & $count 'failed'
    $cancelled = & $count 'cancelled'; $dry = & $count 'dryrun'; $reverted = & $count 'reverted'

    if ($DryRun) { $text = '{0} changes ready. Nothing applied.' -f $dry }
    elseif ($Undo) { $text = if ($failed -eq 0) { 'Undo complete. Windows is as you left it.' } else { 'Undo finished. {0} reverted, {1} failed.' -f $reverted, $failed } }
    else { $text = 'Done. {0} applied, {1} skipped, {2} failed.' -f $applied, $skipped, $failed }
    if ($cancelled -gt 0) { $text += " $cancelled not run (cancelled)." }

    if (-not $DryRun -and -not $Undo) {
        $done = @($r | Where-Object { $_.Status -eq 'applied' })
        $exp = @($done | Where-Object { $_.Restart -eq 'explorer' }).Count
        $out = @($done | Where-Object { $_.Restart -eq 'signout' }).Count
        $boot = @($done | Where-Object { $_.Restart -eq 'reboot' }).Count
        if ($exp) { $text += " Restart Explorer to finish $exp change(s)." }
        if ($out) { $text += " Sign out to finish $out change(s)." }
        if ($boot) { $text += " Restart the PC to finish $boot change(s)." }
    }
    $code = if ($failed -gt 0) { 1 } elseif ($cancelled -gt 0) { 3 } else { 0 }
    [pscustomobject]@{ Text = $text; ExitCode = $code; Applied = $applied; Skipped = $skipped; Failed = $failed; DryRun = $dry; Reverted = $reverted }
}
