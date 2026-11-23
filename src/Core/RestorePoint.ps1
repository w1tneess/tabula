# System Restore point before a run that changes the system.

function New-TabulaRestorePoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunId, [switch]$AllowEnable)

    $result = @{ created = $false; sequence = $null; reason = $null }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $warn = $null
        try {
            Checkpoint-Computer -Description "Tabula $RunId" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable warn -WarningAction SilentlyContinue
            if ($warn) {
                # Windows allows one restore point per 24 hours by default and only warns when it skips one.
                $result['reason'] = 'restore point skipped: ' + (@($warn) -join ' ')
                Write-TabulaLog $result['reason'] -Level WARN
                return $result
            }
            $last = Get-ComputerRestorePoint | Select-Object -Last 1
            $result['created'] = $true
            if ($last) { $result['sequence'] = [int]$last.SequenceNumber }
            Write-TabulaLog ('restore point created (sequence {0})' -f $result['sequence'])
            return $result
        }
        catch {
            $msg = $_.Exception.Message
            if ($attempt -eq 1 -and $AllowEnable -and $msg -match 'disabled|turned off|not enabled|System Protection') {
                Write-TabulaLog 'System Protection is off for C:. Enabling it.' -Level WARN
                try { Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop; continue }
                catch { $msg = 'could not enable System Protection: ' + $_.Exception.Message }
            }
            $result['reason'] = 'restore point failed: ' + $msg
            Write-TabulaLog $result['reason'] -Level WARN
            return $result
        }
    }
    $result
}
