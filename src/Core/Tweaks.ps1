# Tweak runner: protected-list guard, applicability, prior-state capture, apply, undo, detect.
# Tweaks and actions are hashtables (config is converted with ConvertTo-TabulaData). Actions are data,
# never code; the only escape hatch is a function named in $script:TabulaFunctionAllowList.

# name -> @{ Capture = 'Fn'; Apply = 'Fn'; Undo = 'Fn'; Detect = 'Fn' }. Empty in v1.
# Capture returns the prior state, Undo receives it, Detect returns $true when the tweak is already in place.
$script:TabulaFunctionAllowList = @{}

# Things the engine refuses to touch, matched against "HIVE\path" for registry actions.
$script:TabulaProtectedRegistry = @(
    'Windows Defender', 'Windows Advanced Threat Protection', 'Windows Security Health', 'Defender',
    'WindowsFirewall', 'Services\\(SharedAccess|mpssvc|BFE)\b',
    'Services\\(wuauserv|UsoSvc|bits|WaaSMedicSvc|WinDefend|WdNisSvc|WdFilter|WdBoot|Sense|SecurityHealthService|TrustedInstaller|TPM)\b',
    'Policies\\Microsoft\\Windows\\WindowsUpdate', 'WindowsUpdate\\Auto Update\\AU',
    'Policies\\Microsoft\\WindowsStore', 'EdgeUpdate', 'Control\\SecureBoot',
    'SoftwareProtectionPlatform', 'Policies\\Microsoft\\Windows NT\\CurrentVersion\\Software Protection'
)
# UAC lives in a shared key, so it is matched by value name.
$script:TabulaProtectedUacValues = 'EnableLUA|ConsentPromptBehavior(Admin|User)|PromptOnSecureDesktop|FilterAdministratorToken'
$script:TabulaProtectedServices = @(
    'wuauserv', 'UsoSvc', 'bits', 'WaaSMedicSvc', 'WinDefend', 'WdNisSvc', 'WdFilter', 'Sense', 'SecurityHealthService',
    'mpssvc', 'BFE', 'SharedAccess', 'TrustedInstaller', 'StateRepository', 'UserManager', 'ProfSvc', 'DcomLaunch', 'RpcSs', 'TPM'
)
$script:TabulaProtectedTaskPaths = @('\Microsoft\Windows\Windows Defender\', '\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\')

$script:TabulaPowerAliases = @{
    SCHEME_BALANCED = '381b4222-f694-41f0-9685-ff5bb260df2e'
    SCHEME_MIN      = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # High performance
    SCHEME_MAX      = 'a1841308-3541-4fab-bc81-f71556f20b4a'   # Power saver
}

function Get-TabulaActions {
    param($Tweak)
    @($Tweak['actions'] | Where-Object { $null -ne $_ })
}

function Test-TabulaProtected {
    # Returns the reason a tweak is refused, or $null when it is allowed.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tweak)
    foreach ($a in (Get-TabulaActions $Tweak)) {
        switch ($a['type']) {
            'registry' {
                $full = '{0}\{1}' -f $a['hive'], $a['path']
                foreach ($p in $script:TabulaProtectedRegistry) {
                    if ($full -match $p) { return "touches protected registry path ($full)" }
                }
                if ($full -match 'Policies\\System$' -and ([string]$a['name']) -match "^($script:TabulaProtectedUacValues)$") {
                    return "touches UAC setting ($($a['name']))"
                }
            }
            'service' {
                if ($script:TabulaProtectedServices -contains [string]$a['name']) { return "touches protected service ($($a['name']))" }
            }
            'scheduledTask' {
                foreach ($p in $script:TabulaProtectedTaskPaths) {
                    if (([string]$a['path']).StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return "touches protected scheduled task path ($($a['path']))" }
                }
            }
            'powercfg' {
                if ($a['op'] -notin 'setActiveScheme', 'duplicateScheme', 'hibernate') { return "powercfg op '$($a['op'])' is not supported" }
            }
            'function' {
                if (-not $script:TabulaFunctionAllowList.ContainsKey([string]$a['name'])) { return "function '$($a['name'])' is not on the allow-list" }
            }
            default { return "unknown action type '$($a['type'])'" }
        }
    }
    $null
}

function Test-TabulaApplies {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Profile)
    $rules = $Tweak['appliesTo']
    $no = { param($r) @{ Applies = $false; Reason = $r } }

    if ($rules) {
        $build = $Profile.Os.Build
        if ($rules['minBuild'] -or $rules['maxBuild']) {
            if ($build -isnot [int]) { return & $no 'Windows build not detected' }
            if ($rules['minBuild'] -and $build -lt [int]$rules['minBuild']) {
                return & $no $(if ([int]$rules['minBuild'] -ge 22000) { 'Windows 11 only' } else { "Needs Windows build $($rules['minBuild']) or later" })
            }
            if ($rules['maxBuild'] -and $build -gt [int]$rules['maxBuild']) {
                return & $no $(if ([int]$rules['maxBuild'] -lt 22000) { 'Windows 10 only' } else { "Needs Windows build $($rules['maxBuild']) or earlier" })
            }
        }
        if ($rules['editions'] -and @($rules['editions']) -notcontains $Profile.Os.Edition) { return & $no ('Not for Windows {0}' -f $Profile.Os.Edition) }
        if ($rules['chassis'] -and $Profile.Chassis -ne $rules['chassis']) {
            return & $no $(if ($Profile.Chassis -eq 'unknown') { 'Could not tell laptop from desktop' } else { ('{0} only' -f (Get-Culture).TextInfo.ToTitleCase([string]$rules['chassis'])) })
        }
        if ($rules['storage'] -and $Profile.Storage.SystemDiskType -ne $rules['storage']) { return & $no ('{0} only' -f ([string]$rules['storage']).ToUpper()) }
    }
    # Power tweaks mean nothing in a VM.
    if ($Profile.IsVm -eq $true -and @(Get-TabulaActions $Tweak | Where-Object { $_['type'] -eq 'powercfg' }).Count -gt 0) {
        return & $no 'Virtual machine'
    }
    @{ Applies = $true; Reason = '' }
}

# ---- powercfg helpers -------------------------------------------------------------------------------

function ConvertTo-TabulaSchemeGuid {
    param([string]$Scheme)
    if ($script:TabulaPowerAliases.ContainsKey($Scheme)) { return $script:TabulaPowerAliases[$Scheme] }
    if ($Scheme -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { return $Scheme.ToLower() }
    throw "Unknown power scheme '$Scheme'"
}

function Get-TabulaPowerSchemeGuids {
    # GUID regex rather than text parsing, so the language of Windows does not matter.
    $r = Invoke-TabulaNative -FilePath 'powercfg' -ArgumentList @('/list')
    if ($r.ExitCode -ne 0) { throw "powercfg /list failed ($($r.ExitCode))" }
    @([regex]::Matches($r.Output, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') | ForEach-Object { $_.Value.ToLower() })
}

function Get-TabulaActiveSchemeGuid {
    $r = Invoke-TabulaNative -FilePath 'powercfg' -ArgumentList @('/getactivescheme')
    $m = [regex]::Match($r.Output, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
    if ($r.ExitCode -ne 0 -or -not $m.Success) { throw 'could not read the active power scheme' }
    $m.Value.ToLower()
}

function Get-TabulaHibernateEnabled {
    # HibernateEnabled is written once hibernation is toggled; before that only the Default value exists.
    $key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power'
    $v = Get-TabulaRegString $key 'HibernateEnabled'
    if ($null -eq $v) { $v = Get-TabulaRegString $key 'HibernateEnabledDefault' }
    if ($null -eq $v) { return $null }
    ([int]$v -ne 0)
}

function Invoke-TabulaPowercfg {
    param([string[]]$ArgumentList)
    $r = Invoke-TabulaNative -FilePath 'powercfg' -ArgumentList $ArgumentList
    if ($r.ExitCode -ne 0) { throw ('powercfg {0} failed ({1}). {2}' -f ($ArgumentList -join ' '), $r.ExitCode, (Get-TabulaOutputTail $r.Output)) }
}

# ---- service / task helpers -------------------------------------------------------------------------

function Get-TabulaServiceState {
    param([string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9_.-]+$') { throw "Invalid service name '$Name'" }
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'"
    if (-not $svc) { throw "Service '$Name' not found" }
    $delayed = ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$Name", 'DelayedAutostart', 0) -eq 1)
    @{ startMode = [string]$svc.StartMode; delayed = $delayed }
}

function ConvertTo-TabulaStartType {
    param([string]$StartMode)
    switch ($StartMode) {
        'Auto' { 'Automatic' } 'Automatic' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' }
        default { throw "Start type '$StartMode' is not handled" }
    }
}

function Set-TabulaServiceStart {
    param([string]$Name, [string]$StartType, [bool]$Delayed = $false)
    $t = ConvertTo-TabulaStartType $StartType
    if ($t -eq 'Automatic' -and $Delayed) {
        $r = Invoke-TabulaNative -FilePath 'sc.exe' -ArgumentList @('config', $Name, 'start=', 'delayed-auto')
        if ($r.ExitCode -ne 0) { throw "sc config failed ($($r.ExitCode))" }
    }
    else { Set-Service -Name $Name -StartupType $t -ErrorAction Stop }
}

function Get-TabulaTaskState {
    param([string]$Path, [string]$Name)
    $t = Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop
    if ([string]$t.State -eq 'Disabled') { 'Disabled' } else { 'Enabled' }
}

# ---- per-action capture / apply / restore / detect --------------------------------------------------

function Get-TabulaPriorState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Action)
    switch ($Action['type']) {
        'registry' { Get-TabulaRegistryState -Hive $Action['hive'] -Path $Action['path'] -Name $Action['name'] }
        'service' {
            $s = Get-TabulaServiceState $Action['name']
            [void](ConvertTo-TabulaStartType $s['startMode'])   # refuses Boot and System drivers up front
            @{ type = 'service'; name = $Action['name']; startMode = $s['startMode']; delayed = $s['delayed'] }
        }
        'scheduledTask' { @{ type = 'scheduledTask'; path = $Action['path']; name = $Action['name']; state = (Get-TabulaTaskState $Action['path'] $Action['name']) } }
        'powercfg' {
            switch ($Action['op']) {
                'setActiveScheme' { @{ type = 'powercfg'; op = 'setActiveScheme'; activeScheme = (Get-TabulaActiveSchemeGuid) } }
                'hibernate' { @{ type = 'powercfg'; op = 'hibernate'; enabled = (Get-TabulaHibernateEnabled) } }
                'duplicateScheme' {
                    $new = ConvertTo-TabulaSchemeGuid $Action['guid']
                    @{ type = 'powercfg'; op = 'duplicateScheme'; guid = $new; existed = ((Get-TabulaPowerSchemeGuids) -contains $new) }
                }
                default { throw "powercfg op '$($Action['op'])' is not supported" }
            }
        }
        'function' {
            $f = $script:TabulaFunctionAllowList[[string]$Action['name']]
            @{ type = 'function'; name = $Action['name']; state = (& $f['Capture']) }
        }
        default { throw "Unknown action type '$($Action['type'])'" }
    }
}

function Set-TabulaAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Action)
    switch ($Action['type']) {
        'registry' {
            Write-TabulaLog ('registry set {0}\{1}\{2} = {3}' -f $Action['hive'], $Action['path'], $Action['name'], $Action['value'])
            Set-TabulaRegistryValue -Hive $Action['hive'] -Path $Action['path'] -Name $Action['name'] -ValueType $Action['valueType'] -Value $Action['value'] -CreateKey:([bool]$Action['createKey'])
        }
        'service' {
            Write-TabulaLog ('service {0} start type -> {1}' -f $Action['name'], $Action['startType'])
            Set-TabulaServiceStart -Name $Action['name'] -StartType $Action['startType']
        }
        'scheduledTask' {
            Write-TabulaLog ('task {0}{1} -> {2}' -f $Action['path'], $Action['name'], $Action['state'])
            if ($Action['state'] -eq 'Disabled') { [void](Disable-ScheduledTask -TaskPath $Action['path'] -TaskName $Action['name'] -ErrorAction Stop) }
            else { [void](Enable-ScheduledTask -TaskPath $Action['path'] -TaskName $Action['name'] -ErrorAction Stop) }
        }
        'powercfg' {
            Write-TabulaLog ('powercfg {0}' -f $Action['op'])
            switch ($Action['op']) {
                'setActiveScheme' { Invoke-TabulaPowercfg @('/setactive', (ConvertTo-TabulaSchemeGuid $Action['scheme'])) }
                'hibernate' { Invoke-TabulaPowercfg @('/hibernate', $(if ($Action['value'] -eq 'on') { 'on' } else { 'off' })) }
                'duplicateScheme' {
                    $new = ConvertTo-TabulaSchemeGuid $Action['guid']
                    if ((Get-TabulaPowerSchemeGuids) -notcontains $new) { Invoke-TabulaPowercfg @('/duplicatescheme', (ConvertTo-TabulaSchemeGuid $Action['scheme']), $new) }
                }
                default { throw "powercfg op '$($Action['op'])' is not supported" }
            }
        }
        'function' { & $script:TabulaFunctionAllowList[[string]$Action['name']]['Apply'] }
        default { throw "Unknown action type '$($Action['type'])'" }
    }
}

function Restore-TabulaPriorState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Prior)
    switch ($Prior['type']) {
        'registry' { Restore-TabulaRegistryState -Prior $Prior }
        'service' { Set-TabulaServiceStart -Name $Prior['name'] -StartType $Prior['startMode'] -Delayed ([bool]$Prior['delayed']) }
        'scheduledTask' {
            if ($Prior['state'] -eq 'Disabled') { [void](Disable-ScheduledTask -TaskPath $Prior['path'] -TaskName $Prior['name'] -ErrorAction Stop) }
            else { [void](Enable-ScheduledTask -TaskPath $Prior['path'] -TaskName $Prior['name'] -ErrorAction Stop) }
        }
        'powercfg' {
            switch ($Prior['op']) {
                'setActiveScheme' { Invoke-TabulaPowercfg @('/setactive', $Prior['activeScheme']) }
                'hibernate' { if ($null -ne $Prior['enabled']) { Invoke-TabulaPowercfg @('/hibernate', $(if ($Prior['enabled']) { 'on' } else { 'off' })) } }
                'duplicateScheme' { if (-not $Prior['existed']) { Invoke-TabulaPowercfg @('/delete', $Prior['guid']) } }
            }
        }
        'function' { & $script:TabulaFunctionAllowList[[string]$Prior['name']]['Undo'] $Prior['state'] }
        default { throw "Unknown prior-state type '$($Prior['type'])'" }
    }
}

function Test-TabulaActionState {
    # True when the action's target is already in place.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Action)
    switch ($Action['type']) {
        'registry' { Test-TabulaRegistryTarget -Action $Action }
        'service' {
            $s = Get-TabulaServiceState $Action['name']
            ((ConvertTo-TabulaStartType $s['startMode']) -eq (ConvertTo-TabulaStartType $Action['startType']))
        }
        'scheduledTask' { (Get-TabulaTaskState $Action['path'] $Action['name']) -eq $Action['state'] }
        'powercfg' {
            switch ($Action['op']) {
                'setActiveScheme' { (Get-TabulaActiveSchemeGuid) -eq (ConvertTo-TabulaSchemeGuid $Action['scheme']) }
                'hibernate' { (Get-TabulaHibernateEnabled) -eq ($Action['value'] -eq 'on') }
                'duplicateScheme' { (Get-TabulaPowerSchemeGuids) -contains (ConvertTo-TabulaSchemeGuid $Action['guid']) }
                default { $false }
            }
        }
        'function' { [bool](& $script:TabulaFunctionAllowList[[string]$Action['name']]['Detect']) }
        default { $false }
    }
}

function Get-TabulaActionText {
    # One line for dry-run output: what it is now and what it would become.
    param([Parameter(Mandatory)]$Action)
    switch ($Action['type']) {
        'registry' {
            $s = Get-TabulaRegistryState -Hive $Action['hive'] -Path $Action['path'] -Name $Action['name']
            $now = if ($s['valueExisted']) { [string]$s['value'] } else { '(not set)' }
            '{0}\{1}\{2}: {3} -> {4}' -f $Action['hive'], $Action['path'], $Action['name'], $now, $Action['value']
        }
        'service' { 'service {0}: {1} -> {2}' -f $Action['name'], (Get-TabulaServiceState $Action['name'])['startMode'], $Action['startType'] }
        'scheduledTask' { 'task {0}{1}: {2} -> {3}' -f $Action['path'], $Action['name'], (Get-TabulaTaskState $Action['path'] $Action['name']), $Action['state'] }
        'powercfg' { 'powercfg {0}' -f $Action['op'] }
        default { [string]$Action['type'] }
    }
}

# ---- tweak level ------------------------------------------------------------------------------------

function Get-TabulaTweakState {
    # State: Protected | NotApplicable | Set | Unset. Never throws; a failed probe is reported as NotApplicable.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Profile)
    $why = Test-TabulaProtected -Tweak $Tweak
    if ($why) { return @{ State = 'Protected'; Reason = $why } }
    $applies = Test-TabulaApplies -Tweak $Tweak -Profile $Profile
    if (-not $applies.Applies) { return @{ State = 'NotApplicable'; Reason = $applies.Reason } }
    try {
        foreach ($a in (Get-TabulaActions $Tweak)) {
            if (-not (Test-TabulaActionState -Action $a)) { return @{ State = 'Unset'; Reason = '' } }
        }
        @{ State = 'Set'; Reason = '' }
    }
    catch {
        Write-TabulaLog ('detect {0} failed: {1}' -f $Tweak['id'], $_.Exception.Message) -Level WARN
        @{ State = 'NotApplicable'; Reason = ('could not read current state: ' + $_.Exception.Message) }
    }
}

function Invoke-TabulaTweakApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Profile,
        $State, $Run, [switch]$DryRun
    )
    $id = [string]$Tweak['id']; $name = [string]$Tweak['name']
    $restart = if ($Tweak['requiresRestart']) { [string]$Tweak['requiresRestart'] } else { 'none' }
    $ErrorActionPreference = 'Stop'

    $s = Get-TabulaTweakState -Tweak $Tweak -Profile $Profile
    switch ($s.State) {
        'Protected' {
            Write-TabulaLog ('tweak:{0} refused: {1}' -f $id, $s.Reason) -Level ERROR
            return New-TabulaResult -Kind tweak -Id $id -Name $name -Status failed -Reason ('refused: ' + $s.Reason)
        }
        'NotApplicable' { return New-TabulaResult -Kind tweak -Id $id -Name $name -Status skipped -Reason ('not applicable: ' + $s.Reason) }
        'Set' { return New-TabulaResult -Kind tweak -Id $id -Name $name -Status skipped -Reason 'already set' }
    }

    if ($DryRun) {
        $detail = (Get-TabulaActions $Tweak | ForEach-Object { Get-TabulaActionText $_ }) -join '; '
        return New-TabulaResult -Kind tweak -Id $id -Name $name -Status dryrun -Reason 'would apply' -Detail $detail -Restart $restart
    }

    $priors = New-Object System.Collections.ArrayList
    try { foreach ($a in (Get-TabulaActions $Tweak)) { [void]$priors.Add((Get-TabulaPriorState -Action $a)) } }
    catch {
        Write-TabulaLog ('tweak:{0} failed before any change: {1}' -f $id, $_.Exception.Message) -Level ERROR
        return New-TabulaResult -Kind tweak -Id $id -Name $name -Status failed -Reason $_.Exception.Message
    }

    # Write-ahead: the prior values hit disk before the first change, so a crash is still revertible.
    $change = Add-TabulaChange -State $State -Run $Run -TweakId $id -Prior $priors
    try {
        foreach ($a in (Get-TabulaActions $Tweak)) { Set-TabulaAction -Action $a }
        Set-TabulaChangeStatus -State $State -Change $change -Status 'applied'
        Write-TabulaLog ('tweak:{0} applied' -f $id)
        New-TabulaResult -Kind tweak -Id $id -Name $name -Status applied -Restart $restart
    }
    catch {
        $reason = $_.Exception.Message
        Write-TabulaLog ('tweak:{0} failed: {1}. Rolling back.' -f $id, $reason) -Level ERROR
        $clean = $true
        for ($i = $priors.Count - 1; $i -ge 0; $i--) {
            try { Restore-TabulaPriorState -Prior $priors[$i] }
            catch { $clean = $false; Write-TabulaLog ('rollback step failed: ' + $_.Exception.Message) -Level ERROR }
        }
        # If the rollback itself failed the change stays pending so Undo retries it.
        Set-TabulaChangeStatus -State $State -Change $change -Status $(if ($clean) { 'failed' } else { 'pending' })
        New-TabulaResult -Kind tweak -Id $id -Name $name -Status failed -Reason $reason
    }
}

function Invoke-TabulaTweakUndo {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Change, [Parameter(Mandatory)]$State, [switch]$DryRun, [string]$Name = '')
    $id = [string]$Change['tweakId']
    if ($DryRun) { return New-TabulaResult -Kind tweak -Id $id -Name $Name -Status dryrun -Reason 'would revert' }
    $priors = @($Change['prior'])
    $errors = New-Object System.Collections.Generic.List[string]
    for ($i = $priors.Count - 1; $i -ge 0; $i--) {
        try { Restore-TabulaPriorState -Prior $priors[$i] }
        catch { $errors.Add($_.Exception.Message); Write-TabulaLog ('undo {0} step failed: {1}' -f $id, $_.Exception.Message) -Level ERROR }
    }
    if ($errors.Count -eq 0) {
        Set-TabulaChangeStatus -State $State -Change $Change -Status 'reverted'
        Write-TabulaLog ('tweak:{0} reverted' -f $id)
        return New-TabulaResult -Kind tweak -Id $id -Name $Name -Status reverted
    }
    New-TabulaResult -Kind tweak -Id $id -Name $Name -Status failed -Reason ($errors -join '; ')
}
