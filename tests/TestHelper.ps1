# Dot-sourced by every test file. Loads the engine and provides builders. Registry tests only ever
# touch HKCU:\Software\TabulaTest, and state/log go to Pester's TestDrive.

$script:srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$script:TabulaBuild = @{ Version = 'test'; Built = 'n/a'; Commit = 'n/a' }
foreach ($f in (Get-ChildItem (Join-Path $script:srcRoot 'Core') -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
Set-StrictMode -Version 2.0

$script:TestRegRoot = 'HKEY_CURRENT_USER\Software\TabulaTest'

function Initialize-TestEnvironment {
    param([string]$Root)
    $script:TabulaStatePath = Join-Path $Root 'state.json'
    # TestDrive lives for the whole Describe, so clear what the previous test left behind.
    Remove-Item -LiteralPath $script:TabulaStatePath -Force -ErrorAction SilentlyContinue
    [void](Initialize-TabulaLog -Path (Join-Path $Root 'test.log') -Quiet)
    Remove-TestRegistry
}

function Remove-TestRegistry {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\TabulaTest')
    if ($k) { $k.Close(); [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\TabulaTest') }
}

function Get-TestRegValue {
    param([string]$Path, [string]$Name)
    # Not Registry.GetValue: it expands %VARS% in ExpandString values, which hides what is really stored.
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\TabulaTest\$Path")
    if (-not $k) { return '<<absent>>' }
    try { $k.GetValue($(if ($Name -eq '(Default)') { '' } else { $Name }), '<<absent>>', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $k.Close() }
}

function Test-TestRegKey {
    param([string]$Path)
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\TabulaTest\$Path")
    if ($k) { $k.Close(); $true } else { $false }
}

function New-TestRegAction {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [bool]$CreateKey = $true)
    @{ type = 'registry'; hive = 'HKCU'; path = "Software\TabulaTest\$Path"; name = $Name; valueType = $Type; value = $Value; createKey = $CreateKey }
}

function New-TestTweak {
    param([string]$Id, [object[]]$Actions, [hashtable]$Extra = @{})
    $t = @{ id = $Id; name = "Tweak $Id"; category = 'Interface'; risk = 'low'; verified = $true; defaultOn = $true; actions = $Actions; detect = 'actions'; undo = 'restore-prior' }
    foreach ($k in $Extra.Keys) { $t[$k] = $Extra[$k] }
    $t
}

function New-TestProfile {
    param([int]$Build = 26100, [string]$Edition = 'Pro', [string]$Chassis = 'desktop', [string]$Disk = 'ssd', [bool]$IsVm = $false, [bool]$IsAdmin = $true)
    [pscustomobject]@{
        Os = [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; Build = $Build; DisplayVersion = '24H2'; Edition = $Edition; Is11 = ($Build -ge 22000) }
        Chassis = $Chassis
        Storage = [pscustomobject]@{ SystemDiskType = $Disk }
        Ram = [pscustomobject]@{ GB = 16 }
        Cpu = [pscustomobject]@{ Name = 'Test CPU' }
        Gpu = @()
        IsVm = $IsVm; IsAdmin = $IsAdmin
        User = 'PC\user'; InteractiveUser = 'PC\user'
        WingetPresent = $true; WingetVersion = 'v1.0'
        PendingReboot = $false; Supported = $true; SupportReason = ''
    }
}

function New-TestRun {
    param($Profile)
    $state = Get-TabulaState
    $run = New-TabulaRun -State $state -Profile $Profile
    @{ State = $state; Run = $run }
}
