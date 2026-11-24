# Mode dispatch. Returns an exit code: 0 ok, 1 completed with failures, 2 fatal, 3 cancelled.

function Format-TabulaResultTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Results, [switch]$ShowDetail)
    $cols = if ($ShowDetail) { 'Kind', 'Id', 'Status', 'Reason', 'Detail' } else { 'Kind', 'Id', 'Status', 'Reason' }
    (@($Results) | Select-Object $cols | Format-Table -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
}

function Invoke-TabulaMain {
    [CmdletBinding()]
    param(
        [string]$Mode = 'Gui', [string]$Preset = 'Standard',
        [switch]$DryRun, [switch]$NoRestorePoint,
        [string[]]$Apps = @(), [string[]]$Skip = @(),
        [switch]$Yes, [switch]$IncludeHighRisk, [string]$LogPath
    )
    try {
        $logFile = Initialize-TabulaLog -Path $LogPath -DebugEnabled:($VerbosePreference -eq 'Continue')
        Write-TabulaLog ('Tabula {0}, mode {1}{2}. Log: {3}' -f $script:TabulaBuild.Version, $Mode, $(if ($DryRun) { ', dry run' } else { '' }), $logFile)

        if ($Mode -eq 'Gui') {
            Write-TabulaLog 'The GUI is not built yet. Use -Mode Auto, Apps, Tweaks, Undo or Export.' -Level WARN
            return 0
        }

        Write-TabulaLog 'Detecting your machine.'
        $machine = Get-TabulaProfile
        Write-TabulaLog (Get-TabulaProfileSummary -Profile $machine)
        if (-not $machine.Supported) { Write-TabulaLog $machine.SupportReason -Level ERROR; return 2 }

        $config = Get-TabulaConfig
        $problems = @(Test-TabulaConfig -Config $config)
        if ($problems.Count -gt 0) {
            foreach ($p in $problems) { Write-TabulaLog "config: $p" -Level ERROR }
            return 2
        }
        $changesSystem = ($Mode -ne 'Export') -and -not $DryRun

        if ($Mode -eq 'Export') {
            $path = Join-Path (Get-Location).Path 'apps.export.json'
            [void](Export-TabulaApps -OutputPath $path -ExistingApps $config['apps'])
            return 0
        }

        if ($changesSystem -and -not $machine.IsAdmin) {
            Write-TabulaLog 'Tabula needs an elevated PowerShell to change this PC. Open Windows PowerShell as administrator and run the same command again. Add -DryRun to preview without elevation.' -Level ERROR
            return 2
        }
        if ($changesSystem -and $machine.User -ne 'unknown' -and $machine.InteractiveUser -and $machine.InteractiveUser -ne 'unknown' -and $machine.User -ne $machine.InteractiveUser) {
            Write-TabulaLog ('Running as {0} but the signed-in user is {1}. Per-user (HKCU) tweaks apply to {0}.' -f $machine.User, $machine.InteractiveUser) -Level WARN
        }
        if ($machine.PendingReboot -eq $true) { Write-TabulaLog 'A restart is pending. Continuing, but consider restarting first.' -Level WARN }

        $state = Get-TabulaState
        if ($changesSystem -and (Find-TabulaIncompleteRun -State $state)) {
            Write-TabulaLog 'A previous run did not finish. Run -Mode Undo to revert it.' -Level WARN
        }

        if ($Mode -eq 'Undo') {
            $results = Invoke-TabulaUndo -DryRun:$DryRun -Tweaks $config['tweaks']
            if (@($results).Count -eq 0) { Write-TabulaLog 'Nothing to undo.'; return 0 }
            Write-TabulaLog ("`n" + (Format-TabulaResultTable -Results $results))
            $sum = Get-TabulaSummary -Results $results -DryRun:$DryRun -Undo
            Write-TabulaLog $sum.Text
            return $sum.ExitCode
        }

        $scope = switch ($Mode) { 'Tweaks' { 'Tweaks' } 'Apps' { 'Apps' } default { 'Both' } }
        $plan = Resolve-TabulaPlan -Config $config -Profile $machine -Preset $Preset -Scope $scope -Apps $Apps -Skip $Skip -IncludeHighRisk:$IncludeHighRisk -Yes:$Yes
        $held = @($plan | Where-Object { $_.Hold }).Count
        Write-TabulaLog ('{0} change(s) planned, {1} held back. Preset {2}.' -f (@($plan).Count - $held), $held, $Preset)
        if (@($plan).Count -eq 0) { Write-TabulaLog 'Nothing to do.'; return 0 }

        if (-not $DryRun -and -not (Confirm-TabulaPlan -Plan $plan -Yes:$Yes)) {
            Write-TabulaLog 'Cancelled. Nothing applied.'
            return 3
        }

        $results = Invoke-TabulaPlan -Plan $plan -Profile $machine -DryRun:$DryRun -NoRestorePoint:$NoRestorePoint -Yes:$Yes
        Write-TabulaLog ("`n" + (Format-TabulaResultTable -Results $results -ShowDetail:$DryRun))
        $sum = Get-TabulaSummary -Results $results -DryRun:$DryRun
        Write-TabulaLog $sum.Text
        return $sum.ExitCode
    }
    catch {
        # Last resort. Per-item failures never get here; this is config, state or detection breaking outright.
        Write-TabulaLog ('fatal: {0}' -f $_.Exception.Message) -Level ERROR
        Write-TabulaLog ($_.ScriptStackTrace) -Level DEBUG
        return 2
    }
}
