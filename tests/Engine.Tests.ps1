BeforeAll { . $PSScriptRoot\TestHelper.ps1 }
AfterAll { Remove-TestRegistry }

Describe 'State file' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'round-trips through JSON as hashtables and lists' {
        $s = Get-TabulaState
        $run = New-TabulaRun -State $s -Profile (New-TestProfile)
        $prior = New-Object System.Collections.ArrayList
        [void]$prior.Add(@{ type = 'registry'; createdKeys = @('a', 'b'); value = @(1, 2) })
        [void](Add-TabulaChange -State $s -Run $run -TweakId 't' -Prior $prior)
        $back = Get-TabulaState
        $back['runs'][0]['changes'][0]['prior'][0]['createdKeys'].Count | Should -Be 2
        $back['runs'][0]['changes'][0]['status'] | Should -Be 'pending'
    }

    It 'refuses to start over a state file it cannot read' {
        Set-Content -LiteralPath (Get-TabulaStatePath) -Value '{ not json'
        { Get-TabulaState } | Should -Throw '*unreadable*'
    }

    It 'leaves no temp file behind' {
        $s = Get-TabulaState
        [void](New-TabulaRun -State $s -Profile (New-TestProfile))
        Test-Path ((Get-TabulaStatePath) + '.tmp') | Should -BeFalse
    }
}

Describe 'Restore point' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'records a created restore point' {
        Mock Checkpoint-Computer { }
        Mock Get-ComputerRestorePoint { [pscustomobject]@{ SequenceNumber = 42 } }
        $r = New-TabulaRestorePoint -RunId 'r1'
        $r['created'] | Should -BeTrue
        $r['sequence'] | Should -Be 42
    }

    It 'continues with a clear reason when Windows throttles the restore point' {
        Mock Checkpoint-Computer { Write-Warning 'A new system restore point cannot be created because one has already been created within the past 1440 minutes.' }
        $r = New-TabulaRestorePoint -RunId 'r1'
        $r['created'] | Should -BeFalse
        $r['reason'] | Should -Match 'skipped'
    }

    It 'enables System Protection only when allowed, then retries' {
        $script:n = 0
        Mock Checkpoint-Computer { $script:n++; if ($script:n -eq 1) { throw 'System Protection is turned off' } }
        Mock Enable-ComputerRestore { }
        Mock Get-ComputerRestorePoint { [pscustomobject]@{ SequenceNumber = 7 } }
        (New-TabulaRestorePoint -RunId 'r1' -AllowEnable)['created'] | Should -BeTrue
        Should -Invoke Enable-ComputerRestore -Times 1
    }

    It 'does not enable System Protection without permission' {
        Mock Checkpoint-Computer { throw 'System Protection is turned off' }
        Mock Enable-ComputerRestore { }
        (New-TabulaRestorePoint -RunId 'r1')['created'] | Should -BeFalse
        Should -Invoke Enable-ComputerRestore -Times 0
    }
}

Describe 'Plan resolution' {
    BeforeEach {
        Initialize-TestEnvironment $TestDrive
        $script:cfg = @{
            tweaks  = @(
                @{ id = 'a'; name = 'A'; risk = 'low'; verified = $true; defaultOn = $true; actions = @() }
                @{ id = 'ultimate-performance-plan'; name = 'U'; risk = 'medium'; verified = $true; defaultOn = $true; actions = @() }
                @{ id = 'unverified'; name = 'V'; risk = 'low'; verified = $false; defaultOn = $true; actions = @() }
                @{ id = 'risky'; name = 'R'; risk = 'high'; verified = $true; defaultOn = $false; actions = @() }
                @{ id = 'off'; name = 'O'; risk = 'low'; verified = $true; defaultOn = $false; actions = @() }
            )
            apps    = @(
                @{ id = 'rt'; name = 'Runtime'; source = 'winget'; wingetId = 'V.Rt'; defaultSelected = $false }
                @{ id = 'app'; name = 'App'; source = 'winget'; wingetId = 'V.App'; defaultSelected = $true; requires = @('rt') }
                @{ id = 'other'; name = 'Other'; source = 'winget'; wingetId = 'V.Other'; defaultSelected = $true }
            )
            presets = @(
                @{ id = 'Standard'; apps = 'defaultSelected'; tweaks = 'defaultOn'; overrides = @{ laptop = @{ excludeTweaks = @('ultimate-performance-plan') } } }
                @{ id = 'Minimal'; apps = @('other'); tweaks = @('a', 'risky') }
            )
        }
    }

    It 'resolves defaults and holds unverified tweaks' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile -Chassis desktop)
        ($plan | Where-Object Kind -eq 'tweak').Id | Should -Be @('a', 'ultimate-performance-plan', 'unverified')
        ($plan | Where-Object Id -eq 'unverified').Hold | Should -Match 'unverified'
        ($plan | Where-Object Id -eq 'a').Hold | Should -BeNullOrEmpty
    }

    It 'applies the laptop override' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile -Chassis laptop)
        ($plan | Where-Object Kind -eq 'tweak').Id | Should -Not -Contain 'ultimate-performance-plan'
    }

    It 'installs required apps first' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Scope Apps
        ($plan | Where-Object Kind -eq 'app').Id | Should -Be @('rt', 'app', 'other')
    }

    It 'honours -Apps and -Skip' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Scope Apps -Preset Minimal -Apps @('rt') -Skip @('other')
        ($plan | Where-Object Kind -eq 'app').Id | Should -Be @('rt')
    }

    It '-Exact plans only what was asked for, ignoring the preset' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Exact -Tweaks @('off') -Apps @('other')
        @($plan | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Id }) | Should -Be @('tweak:off', 'app:other')
    }

    It '-Exact still pulls in required apps and holds an unverified tweak' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Exact -Tweaks @('unverified') -Apps @('app')
        @($plan | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Id }) | Should -Be @('tweak:unverified', 'app:rt', 'app:app')
        ($plan | Where-Object Id -eq 'unverified').Hold | Should -Match 'unverified'
    }

    It 'holds high-risk tweaks under -Yes unless -IncludeHighRisk' {
        $held = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Scope Tweaks -Preset Minimal -Yes
        ($held | Where-Object Id -eq 'risky').Hold | Should -Match 'IncludeHighRisk'
        $open = Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Scope Tweaks -Preset Minimal -Yes -IncludeHighRisk
        ($open | Where-Object Id -eq 'risky').Hold | Should -BeNullOrEmpty
    }

    It 'throws on an unknown preset' {
        { Resolve-TabulaPlan -Config $script:cfg -Profile (New-TestProfile) -Preset Nope } | Should -Throw '*Unknown preset*'
    }
}

Describe 'Winget wrapper' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'builds the install command from data, with scope only when asked' {
        $app = @{ id = 'x'; wingetId = 'Git.Git'; source = 'winget' }
        (New-TabulaWingetInstallArgs -App $app) -join ' ' | Should -Be 'install --id Git.Git -e --accept-package-agreements --accept-source-agreements --silent'
        $app['scope'] = 'machine'
        (New-TabulaWingetInstallArgs -App $app) -join ' ' | Should -Match '--scope machine$'
    }

    It 'allows listed extra flags and rejects the rest, including --override' {
        $ok = @{ wingetId = 'A.B'; extraArgs = @('--architecture', 'x64') }
        (New-TabulaWingetInstallArgs -App $ok) -join ' ' | Should -Match '--architecture x64$'
        { New-TabulaWingetInstallArgs -App @{ wingetId = 'A.B'; extraArgs = @('--override', '/x') } } | Should -Throw '*not allowed*'
        { New-TabulaWingetInstallArgs -App @{ wingetId = 'A.B'; extraArgs = @('--architecture') } } | Should -Throw '*needs a value*'
        { New-TabulaWingetInstallArgs -App @{ wingetId = 'A.B; calc'; } } | Should -Throw '*Invalid winget ID*'
    }

    It 'maps exit code <hex> to <status>' -ForEach @(
        @{ code = 0; hex = '0x0'; status = 'applied' }
        @{ code = -1978335135; hex = '0x8A150061'; status = 'skipped' }
        @{ code = -1978335189; hex = '0x8A15002B'; status = 'skipped' }
        @{ code = -1978334967; hex = '0x8A150109'; status = 'applied' }
        @{ code = 1; hex = '0x1'; status = 'failed' }
        @{ code = -1978335212; hex = '0x8A150014'; status = 'failed' }
    ) { (ConvertTo-TabulaWingetStatus -ExitCode $code).Status | Should -Be $status }

    It 'flags a restart-needed install' {
        (ConvertTo-TabulaWingetStatus -ExitCode -1978334967).Reboot | Should -BeTrue
    }

    Context 'Install-TabulaApp with winget mocked' {
        BeforeEach {
            $script:installed = $false; $script:installExit = 0; $script:timedOut = $false
            $script:app = @{ id = 'git'; name = 'Git'; source = 'winget'; wingetId = 'Git.Git'; officialUrl = 'https://git-scm.com/' }
            Mock Get-TabulaWingetPath { 'winget.exe' }
            Mock Invoke-TabulaNative {
                switch ($ArgumentList[0]) {
                    'list' { if ($script:installed) { [pscustomobject]@{ ExitCode = 0; Output = 'Git  Git.Git  2.0'; TimedOut = $false } } else { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No installed package found'; TimedOut = $false } } }
                    'show' { [pscustomobject]@{ ExitCode = 0; Output = 'Found Git'; TimedOut = $false } }
                    'install' { [pscustomobject]@{ ExitCode = $script:installExit; Output = 'out'; TimedOut = $script:timedOut } }
                }
            }
        }

        It 'installs a missing app' {
            (Install-TabulaApp -App $script:app).Status | Should -Be 'applied'
            Should -Invoke Invoke-TabulaNative -ParameterFilter { $ArgumentList[0] -eq 'install' } -Times 1
        }
        It 'skips an app that is already installed without running install' {
            $script:installed = $true
            $r = Install-TabulaApp -App $script:app
            $r.Status | Should -Be 'skipped'
            Should -Invoke Invoke-TabulaNative -ParameterFilter { $ArgumentList[0] -eq 'install' } -Times 0
        }
        It 'dry run shows the command and never installs' {
            $r = Install-TabulaApp -App $script:app -DryRun
            $r.Status | Should -Be 'dryrun'
            $r.Detail | Should -Match '^winget install --id Git.Git'
            Should -Invoke Invoke-TabulaNative -ParameterFilter { $ArgumentList[0] -eq 'install' } -Times 0
        }
        It 'reports a failure with the exit code and carries on' {
            $script:installExit = 5
            $r = Install-TabulaApp -App $script:app
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Match '0x00000005'
        }
        It 'reports a timeout as a failure' {
            $script:timedOut = $true
            (Install-TabulaApp -App $script:app).Reason | Should -Match 'timed out'
        }
        It 'turns a restart-needed install into applied with a reboot hint' {
            $script:installExit = -1978334967
            $r = Install-TabulaApp -App $script:app
            $r.Status | Should -Be 'applied'
            $r.Restart | Should -Be 'reboot'
        }
        It 'points manual apps at the vendor page and runs nothing' {
            $r = Install-TabulaApp -App @{ id = 'm'; name = 'M'; source = 'manual'; officialUrl = 'https://vendor.example/' }
            $r.Status | Should -Be 'skipped'
            $r.Reason | Should -Match 'vendor.example'
            Should -Invoke Invoke-TabulaNative -Times 0
        }
        It 'fails cleanly when winget is missing' {
            Mock Get-TabulaWingetPath { $null }
            (Install-TabulaApp -App $script:app).Reason | Should -Be 'winget is not available'
        }
    }
}

Describe 'Plan runner, dry run and CLI' {
    BeforeEach {
        Initialize-TestEnvironment $TestDrive
        $script:profile1 = New-TestProfile
        $script:tw = New-TestTweak 'ext' @((New-TestRegAction 'Cli' 'HideFileExt' 0))
        $script:tw2 = New-TestTweak 'exp' @((New-TestRegAction 'Cli' 'Exp' 1)) @{ verified = $false }
        $script:cfg = @{
            tweaks  = @($script:tw, $script:tw2)
            apps    = @(@{ id = 'a1'; name = 'A1'; source = 'winget'; wingetId = 'V.A1'; defaultSelected = $true })
            presets = @(@{ id = 'Standard'; apps = 'defaultSelected'; tweaks = 'defaultOn' })
        }
        Mock Get-TabulaWingetPath { 'winget.exe' }
        Mock Assert-TabulaWinget { $true }
        Mock Invoke-TabulaNative { [pscustomobject]@{ ExitCode = 0; Output = ''; TimedOut = $false } }
        Mock New-TabulaRestorePoint { @{ created = $true; sequence = 1; reason = $null } }
    }

    It 'dry run plans everything and changes nothing' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1
        $res = Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -DryRun
        ($res | ForEach-Object { '{0}:{1}:{2}' -f $_.Kind, $_.Id, $_.Status }) | Should -Be @('tweak:ext:dryrun', 'tweak:exp:skipped', 'app:a1:dryrun')
        Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be '<<absent>>'
        Test-Path (Get-TabulaStatePath) | Should -BeFalse
        Should -Invoke New-TabulaRestorePoint -Times 0
        (Get-TabulaSummary -Results $res -DryRun).Text | Should -Be '2 changes ready. Nothing applied.'
    }

    It 'takes a restore point first, then tweaks, then apps, and records the run' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1
        $res = Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -Yes
        Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be 0
        Get-TestRegValue 'Cli' 'Exp' | Should -Be '<<absent>>'
        Should -Invoke New-TabulaRestorePoint -Times 1
        $state = Get-TabulaState
        $state['runs'][0]['status'] | Should -Be 'complete'
        $state['runs'][0]['restorePoint']['created'] | Should -BeTrue
        $sum = Get-TabulaSummary -Results $res
        $sum.ExitCode | Should -Be 0
    }

    It 'skips the restore point when asked' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1 -Scope Tweaks
        [void](Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint)
        Should -Invoke New-TabulaRestorePoint -Times 0
    }

    It 'one failing item does not stop the run, and the exit code says so' {
        $bad = New-TestTweak 'bad' @((New-TestRegAction 'Cli' 'Z' 1 'Bogus'))
        $cfg2 = @{ tweaks = @($bad, $script:tw); apps = @(); presets = $script:cfg.presets }
        $plan = Resolve-TabulaPlan -Config $cfg2 -Profile $script:profile1
        $res = Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint
        ($res | ForEach-Object Status) | Should -Be @('failed', 'applied')
        (Get-TabulaSummary -Results $res).ExitCode | Should -Be 1
    }

    It 'stops between items when cancelled' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1 -Scope Tweaks
        Mock Invoke-TabulaTweakApply { $script:TabulaCancel = $true; New-TabulaResult -Kind tweak -Id 'ext' -Status applied }
        $res = Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint
        ($res | ForEach-Object Status) | Should -Be @('applied', 'cancelled')
        (Get-TabulaSummary -Results $res).ExitCode | Should -Be 3
    }

    It 'reports start and done for every item, in order, with the result on done' {
        $script:events = New-Object System.Collections.Generic.List[string]
        $cb = { param($e) $script:events.Add(('{0}:{1}:{2}' -f $e.Phase, $e.Index, $e.Id)) }
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1
        [void](Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint -OnProgress $cb)
        @($script:events) | Should -Be @('start:1:ext', 'done:1:ext', 'start:2:exp', 'done:2:exp', 'start:3:a1', 'done:3:a1')
    }

    It 'a throwing progress callback does not stop the run' {
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1 -Scope Tweaks
        $res = Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint -OnProgress { throw 'boom' }
        ($res | ForEach-Object Status) | Should -Be @('applied', 'skipped')
        Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be 0
    }

    It 'stops between items when the caller flips -Control (the window Cancel button)' {
        $ctl = [hashtable]::Synchronized(@{ Cancel = $false })
        $cb = { param($e) if ($e.Phase -eq 'done' -and $e.Index -eq 1) { $ctl['Cancel'] = $true } }
        $plan = Resolve-TabulaPlan -Config $script:cfg -Profile $script:profile1
        $res = Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint -Control $ctl -OnProgress $cb
        ($res | ForEach-Object Status) | Should -Be @('applied', 'cancelled', 'cancelled')
        Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be 0
        (Get-TabulaSummary -Results $res).ExitCode | Should -Be 3
    }

    It 'a cancelled undo leaves the run revertible and resumable' {
        $t2 = New-TestTweak 'two' @((New-TestRegAction 'Cli' 'Two' 1))
        $cfg2 = @{ tweaks = @($script:tw, $t2); apps = @(); presets = $script:cfg.presets }
        $plan = Resolve-TabulaPlan -Config $cfg2 -Profile $script:profile1
        [void](Invoke-TabulaPlan -Plan $plan -Profile $script:profile1 -NoRestorePoint)
        $ctl = [hashtable]::Synchronized(@{ Cancel = $false })
        $cb = { param($e) if ($e.Phase -eq 'done' -and $e.Index -eq 1) { $ctl['Cancel'] = $true } }
        $res = Invoke-TabulaUndo -Tweaks $cfg2.tweaks -Control $ctl -OnProgress $cb
        ($res | ForEach-Object Status) | Should -Be @('reverted', 'cancelled')   # newest change first
        Get-TestRegValue 'Cli' 'Two' | Should -Be '<<absent>>'
        Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be 0
        (Get-TabulaState)['runs'][0]['status'] | Should -Not -Be 'reverted'
        $again = Invoke-TabulaUndo -Tweaks $cfg2.tweaks
        ($again | ForEach-Object Status) | Should -Be @('reverted')
        (Get-TabulaState)['runs'][0]['status'] | Should -Be 'reverted'
    }

    It 'summarises restart needs' {
        $r = @(
            (New-TabulaResult -Kind tweak -Id 'a' -Status applied -Restart explorer),
            (New-TabulaResult -Kind tweak -Id 'b' -Status applied -Restart explorer),
            (New-TabulaResult -Kind tweak -Id 'c' -Status skipped -Reason 'already set')
        )
        (Get-TabulaSummary -Results $r).Text | Should -Be 'Done. 2 applied, 1 skipped, 0 failed. Restart Explorer to finish 2 change(s).'
    }

    Context 'Invoke-TabulaMain' {
        BeforeEach {
            Mock Get-TabulaConfig { $script:cfg }
            # These hand-built configs are minimal on purpose; the validator has its own tests in Config.Tests.ps1.
            Mock Test-TabulaConfig { @() }
            Mock Get-TabulaProfile { $script:profile1 }
        }
        It 'dry run exits 0 without elevation and changes nothing' {
            Mock Get-TabulaProfile { New-TestProfile -IsAdmin $false }
            Invoke-TabulaMain -Mode Auto -DryRun -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 0
            Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be '<<absent>>'
        }
        It 'refuses a real run without elevation (exit 2)' {
            Mock Get-TabulaProfile { New-TestProfile -IsAdmin $false }
            Invoke-TabulaMain -Mode Auto -Yes -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 2
            Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be '<<absent>>'
        }
        It 'exits 2 on an unsupported OS' {
            $p = New-TestProfile; $p.Supported = $false; $p.SupportReason = 'Needs Windows 10 version 2004 or later.'
            Mock Get-TabulaProfile { $p }
            Invoke-TabulaMain -Mode Auto -DryRun -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 2
        }
        It 'exits 2 and lists the problems when the catalog is invalid' {
            Mock Test-TabulaConfig { @('app x: missing name') }
            Invoke-TabulaMain -Mode Auto -DryRun -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 2
            (Get-TabulaLogLines) -join "`n" | Should -Match 'config: app x: missing name'
        }
        It 'exits 3 when the user declines a risky plan' {
            $risky = New-TestTweak 'med' @((New-TestRegAction 'Cli' 'M' 1)) @{ risk = 'medium' }
            $script:cfg['tweaks'] = @($risky)
            Mock Read-Host { 'n' }
            Invoke-TabulaMain -Mode Tweaks -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 3
            Get-TestRegValue 'Cli' 'M' | Should -Be '<<absent>>'
        }
        It 'applies with -Yes, then -Mode Undo reverts it' {
            Invoke-TabulaMain -Mode Tweaks -Yes -NoRestorePoint -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 0
            Get-TestRegValue 'Cli' 'HideFileExt' | Should -Be 0
            Invoke-TabulaMain -Mode Undo -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 0
            Test-TestRegKey 'Cli' | Should -BeFalse
        }
        It 'says so when there is nothing to undo' {
            Invoke-TabulaMain -Mode Undo -LogPath (Join-Path $TestDrive 'm.log') | Should -Be 0
            (Get-TabulaLogLines) -join "`n" | Should -Match 'Nothing to undo'
        }
    }
}

Describe 'Logging' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'writes the documented line format to the file and the in-memory sink' {
        Write-TabulaLog 'tweak:x applied'
        $line = @(Get-Content (Join-Path $TestDrive 'test.log'))[-1]
        $line | Should -Match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[INFO\] tweak:x applied$'
        (Get-TabulaLogLines)[-1] | Should -Be $line
    }

    It 'hides DEBUG unless enabled' {
        Write-TabulaLog 'secret detail' -Level DEBUG
        (Get-TabulaLogLines) -join '' | Should -Not -Match 'secret detail'
        [void](Initialize-TabulaLog -Path (Join-Path $TestDrive 'd.log') -DebugEnabled -Quiet)
        Write-TabulaLog 'secret detail' -Level DEBUG
        (Get-TabulaLogLines) -join '' | Should -Match 'secret detail'
    }
}
