BeforeAll {
    . $PSScriptRoot\TestHelper.ps1
    function New-GoodConfig {
        @{
            apps    = @(
                @{ id = 'a'; name = 'A'; category = 'Utilities'; source = 'winget'; wingetId = 'V.A'; officialUrl = 'https://a.example/'; defaultSelected = $true }
                @{ id = 'b'; name = 'B'; category = 'Utilities'; source = 'manual'; officialUrl = 'https://b.example/'; defaultSelected = $false; requires = @('a') }
            )
            tweaks  = @(
                @{ id = 't'; name = 'T'; category = 'Interface'; description = 'd'; risk = 'low'; defaultOn = $false; verified = $false; detect = 'actions'; undo = 'restore-prior'
                    actions = @(@{ type = 'registry'; hive = 'HKCU'; path = 'Software\X'; name = 'V'; valueType = 'DWord'; value = 1 }) }
            )
            presets = @(@{ id = 'Standard'; apps = 'defaultSelected'; tweaks = 'defaultOn'; overrides = @{ laptop = @{ excludeTweaks = @('t') } } })
        }
    }
}
AfterAll { Remove-TestRegistry }

Describe 'Test-TabulaConfig' {
    It 'accepts a good config' {
        @(Test-TabulaConfig -Config (New-GoodConfig)).Count | Should -Be 0
    }

    It 'accepts the shipped catalog' {
        $cfg = Get-TabulaConfig -ConfigRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'config')
        $errs = @(Test-TabulaConfig -Config $cfg)
        $errs -join "`n" | Should -BeNullOrEmpty
    }

    It 'reports <name>' -ForEach @(
        @{ name = 'a duplicate app id'; mutate = { $c = $args[0]; $c.apps[1].id = 'a' }; match = 'duplicate app id' }
        @{ name = 'a winget app without wingetId'; mutate = { $args[0].apps[0].Remove('wingetId') }; match = 'needs wingetId' }
        @{ name = 'a non-https URL'; mutate = { $args[0].apps[0].officialUrl = 'http://a.example/' }; match = 'must be https' }
        @{ name = 'a bad app id'; mutate = { $args[0].apps[0].id = 'Bad_Id' }; match = 'kebab-case' }
        @{ name = 'an unknown category'; mutate = { $args[0].apps[0].category = 'Stuff' }; match = 'unknown category' }
        @{ name = 'an unknown dependency'; mutate = { $args[0].apps[1].requires = @('zzz') }; match = 'requires unknown app' }
        @{ name = 'a disallowed winget flag'; mutate = { $args[0].apps[0].extraArgs = @('--override', 'x') }; match = 'not allowed' }
        @{ name = 'a duplicate tweak id'; mutate = { $c = $args[0]; $c.tweaks = @($c.tweaks[0], $c.tweaks[0]) }; match = 'duplicate tweak id' }
        @{ name = 'a high-risk default-on tweak'; mutate = { $t = $args[0].tweaks[0]; $t.risk = 'high'; $t.defaultOn = $true; $t.verified = $true; $t.testedBuilds = @(26100) }; match = 'high risk' }
        @{ name = 'an unverified default-on tweak'; mutate = { $args[0].tweaks[0].defaultOn = $true }; match = 'unverified tweaks cannot be default-on' }
        @{ name = 'a verified tweak with no tested builds'; mutate = { $args[0].tweaks[0].verified = $true }; match = 'needs testedBuilds' }
        @{ name = 'a tweak with no actions'; mutate = { $args[0].tweaks[0].actions = @() }; match = 'at least one action' }
        @{ name = 'explicit undo'; mutate = { $args[0].tweaks[0].undo = 'explicit' }; match = 'explicit undo is not in v1' }
        @{ name = 'a missing registry value'; mutate = { $args[0].tweaks[0].actions[0].Remove('value') }; match = 'missing value' }
        @{ name = 'a bad value type'; mutate = { $args[0].tweaks[0].actions[0].valueType = 'Float' }; match = 'unknown valueType' }
        @{ name = 'an unknown action type'; mutate = { $args[0].tweaks[0].actions[0].type = 'bcdedit' }; match = 'unknown action type' }
        @{ name = 'a protected target'; mutate = { $args[0].tweaks[0].actions = @(@{ type = 'service'; name = 'WinDefend'; startType = 'Disabled' }) }; match = 'protected service' }
        @{ name = 'a bad appliesTo key'; mutate = { $args[0].tweaks[0].appliesTo = @{ colour = 'red' } }; match = 'unknown key' }
        @{ name = 'a preset naming an unknown app'; mutate = { $args[0].presets[0].apps = @('nope') }; match = "unknown app 'nope'" }
        @{ name = 'an override naming an unknown tweak'; mutate = { $args[0].presets[0].overrides.laptop.excludeTweaks = @('nope') }; match = "unknown id 'nope'" }
        @{ name = 'a bad override trait'; mutate = { $args[0].presets[0].overrides = @{ tablet = @{} } }; match = 'unknown override trait' }
    ) {
        $c = New-GoodConfig
        & $mutate $c
        (@(Test-TabulaConfig -Config $c) -join "`n") | Should -Match $match
    }

    It 'fails the build on an invalid catalog' {
        $tmp = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path $tmp | Out-Null
        foreach ($d in 'src', 'config') { Copy-Item (Join-Path (Split-Path -Parent $PSScriptRoot) $d) $tmp -Recurse }
        Copy-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'build.ps1'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION') $tmp
        $apps = Get-Content (Join-Path $tmp 'config\apps.json') -Raw
        Set-Content (Join-Path $tmp 'config\apps.json') ($apps -replace '"officialUrl": "https://www.google.com/chrome/"', '"officialUrl": "http://www.google.com/chrome/"')
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp 'build.ps1') -OutDir (Join-Path $tmp 'out') 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $out | Should -Match 'must be https'
    }
}

Describe 'App applicability in plans' {
    It 'holds Windows Terminal on Windows 11' {
        $cfg = Get-TabulaConfig -ConfigRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'config')
        $win11 = Resolve-TabulaPlan -Config $cfg -Profile (New-TestProfile -Build 26100) -Scope Apps
        ($win11 | Where-Object Id -eq 'windows-terminal').Hold | Should -Be 'not applicable: Windows 10 only'
        $win10 = Resolve-TabulaPlan -Config $cfg -Profile (New-TestProfile -Build 19045) -Scope Apps
        ($win10 | Where-Object Id -eq 'windows-terminal').Hold | Should -BeNullOrEmpty
    }

    It 'verifies only the three tweaks whose Microsoft source and Sandbox run are recorded' {
        $cfg = Get-TabulaConfig -ConfigRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'config')
        # docs/tweaks-verification.md: documented by Microsoft and applied and undone on build 26100. Add to this list only with that evidence.
        @($cfg.tweaks | Where-Object { $_['verified'] } | ForEach-Object { $_['id'] } | Sort-Object) | Should -Be @('dark-mode', 'disable-activity-history', 'telemetry-minimum')
        foreach ($t in @($cfg.tweaks | Where-Object { $_['verified'] })) { @($t['testedBuilds']) | Should -Contain 26100 }
        # Default-on is the verified tweaks that were meant to be on by default; dark mode is opt-in.
        @($cfg.tweaks | Where-Object { $_['defaultOn'] } | ForEach-Object { $_['id'] } | Sort-Object) | Should -Be @('disable-activity-history', 'telemetry-minimum')
        $plan = Resolve-TabulaPlan -Config $cfg -Profile (New-TestProfile) -Preset Minimal -Scope Tweaks
        @($plan | Where-Object { -not $_.Hold }).Count | Should -Be 0   # Minimal names only unverified tweaks
    }
}
