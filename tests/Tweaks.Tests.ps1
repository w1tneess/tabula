BeforeAll { . $PSScriptRoot\TestHelper.ps1 }
AfterAll { Remove-TestRegistry }

Describe 'Tweak apply and undo (scratch registry key)' {
    BeforeEach {
        Initialize-TestEnvironment $TestDrive
        $script:profile1 = New-TestProfile
        $script:t1 = New-TestTweak 'sample-dword' @((New-TestRegAction 'Adv' 'Hidden' 1))
        $script:t2 = New-TestTweak 'sample-context' @((New-TestRegAction 'Classes\CLSID\{x}\InprocServer32' '(Default)' '' 'String'))
        $script:t3 = New-TestTweak 'sample-multi' @((New-TestRegAction 'Multi' 'A' 1), (New-TestRegAction 'Multi' 'B' 'hello' 'String'))
    }

    It 'applies three sample tweaks, then undo returns the registry to how it was' {
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\Adv' -Name 'Hidden' -ValueType DWord -Value 2 -CreateKey
        $ctx = New-TestRun $script:profile1
        foreach ($t in $script:t1, $script:t2, $script:t3) {
            (Invoke-TabulaTweakApply -Tweak $t -Profile $script:profile1 -State $ctx.State -Run $ctx.Run).Status | Should -Be 'applied'
        }
        Complete-TabulaRun -State $ctx.State -Run $ctx.Run
        Get-TestRegValue 'Adv' 'Hidden' | Should -Be 1
        Get-TestRegValue 'Classes\CLSID\{x}\InprocServer32' '(Default)' | Should -Be ''
        Get-TestRegValue 'Multi' 'B' | Should -Be 'hello'

        $results = Invoke-TabulaUndo
        @($results).Count | Should -Be 3
        @($results | Where-Object Status -ne 'reverted').Count | Should -Be 0
        Get-TestRegValue 'Adv' 'Hidden' | Should -Be 2
        Test-TestRegKey 'Classes' | Should -BeFalse
        Test-TestRegKey 'Multi' | Should -BeFalse
        (Get-TabulaState)['runs'][0]['status'] | Should -Be 'reverted'
    }

    It 'reports skipped (already set) on a second apply, and does not record a change for it' {
        $ctx = New-TestRun $script:profile1
        [void](Invoke-TabulaTweakApply -Tweak $script:t1 -Profile $script:profile1 -State $ctx.State -Run $ctx.Run)
        $second = Invoke-TabulaTweakApply -Tweak $script:t1 -Profile $script:profile1 -State $ctx.State -Run $ctx.Run
        $second.Status | Should -Be 'skipped'
        $second.Reason | Should -Be 'already set'
        @($ctx.Run['changes']).Count | Should -Be 1
    }

    It 'dry run changes nothing and writes no state' {
        $r = Invoke-TabulaTweakApply -Tweak $script:t1 -Profile $script:profile1 -DryRun
        $r.Status | Should -Be 'dryrun'
        $r.Detail | Should -Match 'Hidden: \(not set\) -> 1'
        Get-TestRegValue 'Adv' 'Hidden' | Should -Be '<<absent>>'
        Test-Path (Get-TabulaStatePath) | Should -BeFalse
    }

    It 'writes the prior values to disk before the first change' {
        $ctx = New-TestRun $script:profile1
        $script:seen = $null
        Mock Set-TabulaAction { $script:seen = (Get-TabulaState)['runs'][0]['changes'] }
        [void](Invoke-TabulaTweakApply -Tweak $script:t1 -Profile $script:profile1 -State $ctx.State -Run $ctx.Run)
        @($script:seen).Count | Should -Be 1
        $script:seen[0]['status'] | Should -Be 'pending'
        $script:seen[0]['prior'][0]['keyExisted'] | Should -BeFalse
    }

    It 'rolls back and marks the change failed when a later action throws' {
        $bad = New-TestTweak 'bad' @((New-TestRegAction 'Bad' 'A' 1), (New-TestRegAction 'Bad' 'B' 1 'Bogus'))
        $ctx = New-TestRun $script:profile1
        $r = Invoke-TabulaTweakApply -Tweak $bad -Profile $script:profile1 -State $ctx.State -Run $ctx.Run
        $r.Status | Should -Be 'failed'
        Get-TestRegValue 'Bad' 'A' | Should -Be '<<absent>>'
        Test-TestRegKey 'Bad' | Should -BeFalse
        (Get-TabulaState)['runs'][0]['changes'][0]['status'] | Should -Be 'failed'
    }

    It 'undoes a change left pending by a crash' {
        $ctx = New-TestRun $script:profile1
        $prior = New-Object System.Collections.ArrayList
        [void]$prior.Add((Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\Crash' -Name 'V'))
        [void](Add-TabulaChange -State $ctx.State -Run $ctx.Run -TweakId 'crashed' -Prior $prior)
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\Crash' -Name 'V' -ValueType DWord -Value 1 -CreateKey
        # process "dies" here: run stays 'running', change stays 'pending'
        (Find-TabulaIncompleteRun -State (Get-TabulaState))['runId'] | Should -Not -BeNullOrEmpty
        $results = Invoke-TabulaUndo
        @($results)[0].Status | Should -Be 'reverted'
        Test-TestRegKey 'Crash' | Should -BeFalse
    }

    It 'does not touch changes that were skipped or failed when undoing' {
        $ctx = New-TestRun $script:profile1
        [void](Invoke-TabulaTweakApply -Tweak $script:t1 -Profile $script:profile1 -State $ctx.State -Run $ctx.Run)
        [void](Invoke-TabulaTweakApply -Tweak $script:t1 -Profile $script:profile1 -State $ctx.State -Run $ctx.Run)
        @(Invoke-TabulaUndo).Count | Should -Be 1
    }
}

Describe 'Protected list' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'refuses <name>' -ForEach @(
        @{ name = 'Defender policy'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Policies\Microsoft\Windows Defender'; name = 'DisableAntiSpyware'; valueType = 'DWord'; value = 1 } }
        @{ name = 'Defender real-time key'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Microsoft\Windows Defender\Real-Time Protection'; name = 'DisableRealtimeMonitoring'; valueType = 'DWord'; value = 1 } }
        @{ name = 'Windows Update service'; action = @{ type = 'service'; name = 'wuauserv'; startType = 'Disabled' } }
        @{ name = 'Defender service'; action = @{ type = 'service'; name = 'WinDefend'; startType = 'Disabled' } }
        @{ name = 'Update policy'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; name = 'NoAutoUpdate'; valueType = 'DWord'; value = 1 } }
        @{ name = 'firewall policy'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'; name = 'EnableFirewall'; valueType = 'DWord'; value = 0 } }
        @{ name = 'UAC'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'EnableLUA'; valueType = 'DWord'; value = 0 } }
        @{ name = 'Store policy'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Policies\Microsoft\WindowsStore'; name = 'RemoveWindowsStore'; valueType = 'DWord'; value = 1 } }
        @{ name = 'secure boot'; action = @{ type = 'registry'; hive = 'HKLM'; path = 'SYSTEM\CurrentControlSet\Control\SecureBoot\State'; name = 'UEFISecureBootEnabled'; valueType = 'DWord'; value = 0 } }
        @{ name = 'defender task'; action = @{ type = 'scheduledTask'; path = '\Microsoft\Windows\Windows Defender\'; name = 'Windows Defender Scheduled Scan'; state = 'Disabled' } }
        @{ name = 'update task'; action = @{ type = 'scheduledTask'; path = '\Microsoft\Windows\WindowsUpdate\'; name = 'Scheduled Start'; state = 'Disabled' } }
        @{ name = 'unlisted function'; action = @{ type = 'function'; name = 'Remove-Everything' } }
        @{ name = 'unknown action type'; action = @{ type = 'bcdedit'; value = 'x' } }
        @{ name = 'unsupported powercfg op'; action = @{ type = 'powercfg'; op = 'setValue' } }
    ) {
        $tweak = New-TestTweak 'x' @($action)
        Test-TabulaProtected -Tweak $tweak | Should -Not -BeNullOrEmpty
        $r = Invoke-TabulaTweakApply -Tweak $tweak -Profile (New-TestProfile) -DryRun
        $r.Status | Should -Be 'failed'
        $r.Reason | Should -Match '^refused'
    }

    It 'allows an ordinary tweak and a different UAC-adjacent value' {
        Test-TabulaProtected -Tweak (New-TestTweak 'ok' @((New-TestRegAction 'X' 'Y' 1))) | Should -BeNullOrEmpty
        $other = @{ type = 'registry'; hive = 'HKCU'; path = 'Software\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'DisableLockWorkstation'; valueType = 'DWord'; value = 1 }
        Test-TabulaProtected -Tweak (New-TestTweak 'ok2' @($other)) | Should -BeNullOrEmpty
    }
}

Describe 'Applicability' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'skips Windows 11 tweaks on Windows 10 with a reason' {
        $t = New-TestTweak 'w11' @((New-TestRegAction 'A' 'B' 1)) @{ appliesTo = @{ minBuild = 22000 } }
        $r = Invoke-TabulaTweakApply -Tweak $t -Profile (New-TestProfile -Build 19045) -DryRun
        $r.Status | Should -Be 'skipped'
        $r.Reason | Should -Be 'not applicable: Windows 11 only'
    }

    It 'matches <rule> against the profile' -ForEach @(
        @{ rule = 'laptop-only on desktop'; applies = @{ chassis = 'laptop' }; prof = @{ Chassis = 'desktop' }; ok = $false; why = 'Laptop only' }
        @{ rule = 'laptop-only on laptop'; applies = @{ chassis = 'laptop' }; prof = @{ Chassis = 'laptop' }; ok = $true; why = '' }
        @{ rule = 'ssd-only on hdd'; applies = @{ storage = 'ssd' }; prof = @{ Disk = 'hdd' }; ok = $false; why = 'SSD only' }
        @{ rule = 'Pro-only on Home'; applies = @{ editions = @('Pro', 'Enterprise') }; prof = @{ Edition = 'Home' }; ok = $false; why = 'Not for Windows Home' }
        @{ rule = 'Win10-only on Win11'; applies = @{ maxBuild = 19045 }; prof = @{ Build = 26100 }; ok = $false; why = 'Windows 10 only' }
    ) {
        $t = New-TestTweak 'r' @((New-TestRegAction 'A' 'B' 1)) @{ appliesTo = $applies }
        $p = New-TestProfile @prof
        $res = Test-TabulaApplies -Tweak $t -Profile $p
        $res.Applies | Should -Be $ok
        $res.Reason | Should -Be $why
    }

    It 'skips power tweaks in a virtual machine' {
        $t = New-TestTweak 'power' @(@{ type = 'powercfg'; op = 'setActiveScheme'; scheme = 'SCHEME_BALANCED' })
        (Test-TabulaApplies -Tweak $t -Profile (New-TestProfile -IsVm $true)).Reason | Should -Be 'Virtual machine'
    }
}

Describe 'powercfg, service and task actions (mocked, nothing is changed)' {
    BeforeEach {
        Initialize-TestEnvironment $TestDrive
        $script:active = '381b4222-f694-41f0-9685-ff5bb260df2e'
        $script:calls = New-Object System.Collections.Generic.List[string]
        Mock Invoke-TabulaNative {
            $script:calls.Add(($ArgumentList -join ' '))
            switch ($ArgumentList[0]) {
                '/getactivescheme' { [pscustomobject]@{ ExitCode = 0; Output = "Power Scheme GUID: $script:active  (x)"; TimedOut = $false } }
                '/list' { [pscustomobject]@{ ExitCode = 0; Output = "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)`nPower Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High)"; TimedOut = $false } }
                '/setactive' { $script:active = $ArgumentList[1]; [pscustomobject]@{ ExitCode = 0; Output = ''; TimedOut = $false } }
                default { [pscustomobject]@{ ExitCode = 0; Output = ''; TimedOut = $false } }
            }
        }
    }

    It 'switches the power scheme and puts the previous one back on undo' {
        $t = New-TestTweak 'plan' @(@{ type = 'powercfg'; op = 'setActiveScheme'; scheme = 'SCHEME_MIN' })
        $ctx = New-TestRun (New-TestProfile)
        (Invoke-TabulaTweakApply -Tweak $t -Profile (New-TestProfile) -State $ctx.State -Run $ctx.Run).Status | Should -Be 'applied'
        $script:active | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        [void](Invoke-TabulaUndo)
        $script:active | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
    }

    It 'duplicates a scheme once and deletes it on undo only if it was created' {
        $new = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $t = New-TestTweak 'dup' @(@{ type = 'powercfg'; op = 'duplicateScheme'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; guid = $new })
        $ctx = New-TestRun (New-TestProfile)
        [void](Invoke-TabulaTweakApply -Tweak $t -Profile (New-TestProfile) -State $ctx.State -Run $ctx.Run)
        $script:calls | Should -Contain "/duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c $new"
        [void](Invoke-TabulaUndo)
        $script:calls | Should -Contain "/delete $new"
    }

    It 'restores a service start type, including delayed start' {
        Mock Get-CimInstance { [pscustomobject]@{ StartMode = 'Auto' } } -ParameterFilter { $ClassName -eq 'Win32_Service' }
        Mock Set-Service { }
        $prior = Get-TabulaPriorState -Action @{ type = 'service'; name = 'Spooler'; startType = 'Manual' }
        $prior['startMode'] | Should -Be 'Auto'
        Restore-TabulaPriorState -Prior $prior
        Should -Invoke Set-Service -Times 1 -ParameterFilter { $Name -eq 'Spooler' -and $StartupType -eq 'Automatic' }
    }

    It 'records and restores a scheduled task state' {
        Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
        Mock Disable-ScheduledTask { }
        Mock Enable-ScheduledTask { }
        $action = @{ type = 'scheduledTask'; path = '\Vendor\'; name = 'Telemetry'; state = 'Disabled' }
        $prior = Get-TabulaPriorState -Action $action
        $prior['state'] | Should -Be 'Enabled'
        Set-TabulaAction -Action $action
        Should -Invoke Disable-ScheduledTask -Times 1
        Restore-TabulaPriorState -Prior $prior
        Should -Invoke Enable-ScheduledTask -Times 1
    }
}
