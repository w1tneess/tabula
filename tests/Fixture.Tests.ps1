BeforeAll { . $PSScriptRoot\TestHelper.ps1 }
AfterAll { Remove-TestRegistry }

# Config goes through real ConvertFrom-Json here, not hand-built hashtables, because that is the path M2 data takes.
Describe 'JSON config to dry-run plan' {
    BeforeEach {
        Initialize-TestEnvironment $TestDrive
        $script:cfgRoot = Join-Path $TestDrive 'config'
        New-Item -ItemType Directory -Force $script:cfgRoot | Out-Null
        @'
{ "schemaVersion": 1, "tweaks": [
  { "id": "t-dword", "name": "Sample DWord", "category": "Interface", "risk": "low", "defaultOn": true, "verified": true, "requiresRestart": "explorer",
    "actions": [ { "type": "registry", "hive": "HKCU", "path": "Software\\TabulaTest\\Fx", "name": "Hidden", "valueType": "DWord", "value": 1, "createKey": true } ],
    "detect": "actions", "undo": "restore-prior" },
  { "id": "t-win11", "name": "Win11 only", "category": "Interface", "risk": "low", "defaultOn": true, "verified": true,
    "appliesTo": { "minBuild": 22000, "editions": ["Pro", "Home"] },
    "actions": [ { "type": "registry", "hive": "HKCU", "path": "Software\\TabulaTest\\Fx", "name": "W11", "valueType": "DWord", "value": 1, "createKey": true } ],
    "detect": "actions", "undo": "restore-prior" },
  { "id": "t-experimental", "name": "Unverified", "category": "Privacy", "risk": "low", "defaultOn": true, "verified": false,
    "actions": [ { "type": "registry", "hive": "HKCU", "path": "Software\\TabulaTest\\Fx", "name": "Exp", "valueType": "DWord", "value": 1, "createKey": true } ],
    "detect": "actions", "undo": "restore-prior" },
  { "id": "t-defender", "name": "Must be refused", "category": "Privacy", "risk": "low", "defaultOn": true, "verified": true,
    "actions": [ { "type": "service", "name": "WinDefend", "startType": "Disabled" } ], "detect": "actions", "undo": "restore-prior" }
] }
'@ | Set-Content (Join-Path $script:cfgRoot 'tweaks.json')
        @'
{ "schemaVersion": 1, "apps": [
  { "id": "rt", "name": "Runtime", "category": "Development", "source": "winget", "wingetId": "Vendor.Runtime", "officialUrl": "https://example.com/", "defaultSelected": false },
  { "id": "tool", "name": "Tool", "category": "Utilities", "source": "winget", "wingetId": "Vendor.Tool", "officialUrl": "https://example.com/", "defaultSelected": true, "requires": ["rt"] },
  { "id": "manual", "name": "Manual", "category": "Utilities", "source": "manual", "officialUrl": "https://vendor.example/download", "defaultSelected": true }
] }
'@ | Set-Content (Join-Path $script:cfgRoot 'apps.json')
        @'
{ "schemaVersion": 1, "presets": [ { "id": "Standard", "name": "Standard", "apps": "defaultSelected", "tweaks": "defaultOn" } ] }
'@ | Set-Content (Join-Path $script:cfgRoot 'presets.json')
        Mock Get-TabulaWingetPath { 'C:\fake\winget.exe' }
        Mock Invoke-TabulaNative { [pscustomobject]@{ ExitCode = $(if ($ArgumentList[0] -eq 'list') { -1978335212 } else { 0 }); Output = ''; TimedOut = $false } }
    }

    It 'loads, resolves and dry-runs a Windows 11 Pro desktop' {
        $cfg = Get-TabulaConfig -ConfigRoot $script:cfgRoot
        $prof = New-TestProfile -Build 26100 -Edition Pro
        $plan = Resolve-TabulaPlan -Config $cfg -Profile $prof
        $res = Invoke-TabulaPlan -Plan $plan -Profile $prof -DryRun
        $lines = $res | ForEach-Object { '{0}:{1}:{2}' -f $_.Kind, $_.Id, $_.Status }
        $lines | Should -Be @(
            'tweak:t-dword:dryrun', 'tweak:t-win11:dryrun', 'tweak:t-experimental:skipped', 'tweak:t-defender:failed',
            'app:rt:dryrun', 'app:tool:dryrun', 'app:manual:skipped')
        ($res | Where-Object Id -eq 't-defender').Reason | Should -Match '^refused'
        ($res | Where-Object Id -eq 't-experimental').Reason | Should -Match 'unverified'
        ($res | Where-Object Id -eq 'manual').Reason | Should -Match 'vendor.example'
        ($res | Where-Object Id -eq 't-dword').Restart | Should -Be 'explorer'
        Test-TestRegKey 'Fx' | Should -BeFalse
        Test-Path (Get-TabulaStatePath) | Should -BeFalse
    }

    It 'skips the Windows 11 tweak on Windows 10 and on an edition not listed' {
        $cfg = Get-TabulaConfig -ConfigRoot $script:cfgRoot
        foreach ($prof in (New-TestProfile -Build 19045 -Edition Pro), (New-TestProfile -Build 26100 -Edition Enterprise)) {
            $plan = Resolve-TabulaPlan -Config $cfg -Profile $prof -Scope Tweaks
            $r = (Invoke-TabulaPlan -Plan $plan -Profile $prof -DryRun) | Where-Object Id -eq 't-win11'
            $r.Status | Should -Be 'skipped'
            $r.Reason | Should -Match '^not applicable'
        }
    }

    It 'applies for real on the scratch key and undo restores it, from JSON-shaped data' {
        $cfg = Get-TabulaConfig -ConfigRoot $script:cfgRoot
        $prof = New-TestProfile
        $plan = Resolve-TabulaPlan -Config $cfg -Profile $prof -Scope Tweaks
        $res = Invoke-TabulaPlan -Plan $plan -Profile $prof -NoRestorePoint
        Get-TestRegValue 'Fx' 'Hidden' | Should -Be 1
        ($res | Where-Object Id -eq 't-dword').Status | Should -Be 'applied'
        [void](Invoke-TabulaUndo)
        Test-TestRegKey 'Fx' | Should -BeFalse
    }
}
