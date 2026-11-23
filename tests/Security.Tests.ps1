BeforeAll {
    . $PSScriptRoot\TestHelper.ps1
    # A folder with a closed ACL (only me, SYSTEM, Administrators). TestDrive inherits extra principals on some machines.
    # Get-Acl/Set-Acl also touch owner and audit data, which needs privileges a normal token lacks. Only the DACL is needed.
    function Get-Dacl { param($Path) (New-Object IO.DirectoryInfo $Path).GetAccessControl([Security.AccessControl.AccessControlSections]::Access) }
    function Set-Dacl { param($Path, $Acl) (New-Object IO.DirectoryInfo $Path).SetAccessControl($Acl) }
    function New-ClosedFolder {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path | Out-Null
        $acl = Get-Dacl $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        foreach ($s in $me, (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'), (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        }
        Set-Dacl $Path $acl
    }
}
AfterAll { Remove-TestRegistry }

Describe 'Protected list resists crafted paths' {
    It 'rejects <name>' -ForEach @(
        @{ name = 'doubled backslash'; a = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\\Policies\Microsoft\Windows Defender'; name = 'x'; valueType = 'DWord'; value = 1 } }
        @{ name = 'leading backslash'; a = @{ type = 'registry'; hive = 'HKLM'; path = '\SOFTWARE\Foo'; name = 'x'; valueType = 'DWord'; value = 1 } }
        @{ name = 'trailing backslash'; a = @{ type = 'registry'; hive = 'HKCU'; path = 'Software\Foo\'; name = 'x'; valueType = 'DWord'; value = 1 } }
        @{ name = 'forward slashes'; a = @{ type = 'registry'; hive = 'HKLM'; path = 'SOFTWARE/Policies/Microsoft/Windows Defender'; name = 'x'; valueType = 'DWord'; value = 1 } }
        @{ name = 'an unsupported hive'; a = @{ type = 'registry'; hive = 'HKCR'; path = 'Foo'; name = 'x'; valueType = 'DWord'; value = 1 } }
        @{ name = 'a service name with a wildcard'; a = @{ type = 'service'; name = 'wuau*'; startType = 'Disabled' } }
        @{ name = 'a task path wildcard'; a = @{ type = 'scheduledTask'; path = '\Microsoft\Windows\Windows*\'; name = 'X'; state = 'Disabled' } }
        @{ name = 'a task name wildcard'; a = @{ type = 'scheduledTask'; path = '\Vendor\'; name = '*'; state = 'Disabled' } }
        @{ name = 'a task path without a leading backslash'; a = @{ type = 'scheduledTask'; path = 'Microsoft\Windows\WindowsUpdate\'; name = 'X'; state = 'Disabled' } }
        @{ name = 'a doubled task path separator'; a = @{ type = 'scheduledTask'; path = '\Microsoft\\Windows\WindowsUpdate\'; name = 'X'; state = 'Disabled' } }
    ) {
        Test-TabulaProtected -Tweak @{ actions = @($a) } | Should -Match '^(invalid|unsupported)'
    }

    It 'refuses to restore a recorded state that points at a protected target' {
        Initialize-TestEnvironment $TestDrive
        $bad = @{ type = 'service'; name = 'WinDefend'; startMode = 'Disabled'; delayed = $false }
        Test-TabulaPriorSafe -Prior $bad | Should -Match 'protected service'
        $change = @{ tweakId = 't'; status = 'applied'; prior = @($bad) }
        $ctx = New-TestRun (New-TestProfile)
        $r = Invoke-TabulaTweakUndo -Change $change -State $ctx.State
        $r.Status | Should -Be 'failed'
        $r.Reason | Should -Match 'refused to restore'
    }

    It 'refuses a malformed GUID in a recorded power state' {
        Test-TabulaPriorSafe -Prior @{ type = 'powercfg'; op = 'setActiveScheme'; activeScheme = 'x; calc' } | Should -Match 'invalid GUID'
    }
}

Describe 'State folder trust' {
    It 'accepts a folder only the current user controls' {
        $dir = Join-Path $TestDrive 'ok'
        New-ClosedFolder $dir
        { Assert-TabulaStateFolder -Folder $dir } | Should -Not -Throw
    }

    It 'refuses a folder that grants write access to Everyone' {
        $dir = Join-Path $TestDrive 'open'
        New-ClosedFolder $dir
        $acl = Get-Dacl $dir
        $everyone = New-Object Security.Principal.SecurityIdentifier 'S-1-1-0'
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Dacl $dir $acl
        { Assert-TabulaStateFolder -Folder $dir } | Should -Throw '*not trusted*'
    }

    It 'does not fail for a caller who cannot read the ACL' {
        Mock Get-Acl { throw (New-Object UnauthorizedAccessException 'Attempted to perform an unauthorized operation.') }
        $dir = Join-Path $TestDrive 'locked'
        New-ClosedFolder $dir
        { Assert-TabulaStateFolder -Folder $dir } | Should -Not -Throw
    }

    It 'refuses a folder that is a junction' {
        $target = Join-Path $TestDrive 'target'
        New-ClosedFolder $target
        $link = Join-Path $TestDrive 'link'
        $null = cmd.exe /c mklink /J "`"$link`"" "`"$target`""
        { Assert-TabulaStateFolder -Folder $link } | Should -Throw '*reparse point*'
    }

    It 'allows read-only access for Users' {
        $dir = Join-Path $TestDrive 'readable'
        New-ClosedFolder $dir
        $acl = Get-Dacl $dir
        $users = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-545'
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Dacl $dir $acl
        { Assert-TabulaStateFolder -Folder $dir } | Should -Not -Throw
    }
}
