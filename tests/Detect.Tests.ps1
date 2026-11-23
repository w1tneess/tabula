BeforeAll { . $PSScriptRoot\TestHelper.ps1 }

Describe 'Detection helpers' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'normalises edition <id> to <edition>' -ForEach @(
        @{ id = 'Core'; edition = 'Home' }, @{ id = 'CoreSingleLanguage'; edition = 'Home' },
        @{ id = 'Professional'; edition = 'Pro' }, @{ id = 'ProfessionalWorkstation'; edition = 'Pro' },
        @{ id = 'Enterprise'; edition = 'Enterprise' }, @{ id = 'Education'; edition = 'Education' },
        @{ id = 'ServerStandard'; edition = 'Server' }, @{ id = 'IoTEnterprise'; edition = 'Other' }, @{ id = ''; edition = 'Other' }
    ) { ConvertTo-TabulaEdition $id | Should -Be $edition }

    It 'classifies chassis <types> battery=<battery> as <expected>' -ForEach @(
        @{ types = @(10); battery = $true; expected = 'laptop' }
        @{ types = @(9); battery = $false; expected = 'laptop' }
        @{ types = @(3); battery = $false; expected = 'desktop' }
        @{ types = @(3); battery = $true; expected = 'desktop' }   # desktop with a UPS
        @{ types = @(1); battery = $true; expected = 'laptop' }    # "Other": the battery decides
        @{ types = @(2); battery = $false; expected = 'unknown' }
        @{ types = @(); battery = $false; expected = 'unknown' }
    ) { Get-TabulaChassisClass -ChassisTypes $types -HasBattery $battery | Should -Be $expected }

    It 'recognises hypervisors' -ForEach @(
        @{ m = 'VMware, Inc.'; model = 'VMware7,1'; vm = $true }
        @{ m = 'innotek GmbH'; model = 'VirtualBox'; vm = $true }
        @{ m = 'Microsoft Corporation'; model = 'Virtual Machine'; vm = $true }
        @{ m = 'QEMU'; model = 'Standard PC'; vm = $true }
        @{ m = 'Microsoft Corporation'; model = 'Surface Laptop 5'; vm = $false }
        @{ m = 'LENOVO'; model = '82XV'; vm = $false }
    ) { Test-TabulaVirtualMachine -Manufacturer $m -Model $model | Should -Be $vm }

    It 'maps GPU names to vendors' -ForEach @(
        @{ n = 'NVIDIA GeForce RTX 4070'; v = 'NVIDIA' }, @{ n = 'AMD Radeon RX 7800 XT'; v = 'AMD' },
        @{ n = 'Intel(R) UHD Graphics'; v = 'Intel' }, @{ n = 'Microsoft Basic Display Adapter'; v = 'Other' }
    ) { Get-TabulaGpuVendor $n | Should -Be $v }

    It 'treats NVMe as SSD even when MediaType is Unspecified' {
        ConvertTo-TabulaDiskType -MediaType 'Unspecified' -BusType 'NVMe' | Should -Be 'ssd'
        ConvertTo-TabulaDiskType -MediaType 'HDD' -BusType 'SATA' | Should -Be 'hdd'
        ConvertTo-TabulaDiskType -MediaType 'Unspecified' -BusType 'SATA' | Should -Be 'unknown'
    }
}

Describe 'Get-TabulaProfile with mocked hardware' {
    BeforeEach {
        Initialize-TestEnvironment $TestDrive
        Mock Get-TabulaRegString { switch ($Name) { 'EditionID' { 'Professional' } 'DisplayVersion' { '24H2' } default { $null } } }
        Mock Get-TabulaWingetVersion { 'v1.9.0' }
        Mock Get-TabulaSystemDisk { [pscustomobject]@{ MediaType = 'Unspecified'; BusType = 'NVMe' } }
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; BuildNumber = '26100'; ProductType = 1 } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        Mock Get-CimInstance { [pscustomobject]@{ TotalPhysicalMemory = 17179869184; Manufacturer = 'LENOVO'; Model = '82XV'; UserName = 'PC\me' } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        Mock Get-CimInstance { [pscustomobject]@{ ChassisTypes = @(10) } } -ParameterFilter { $ClassName -eq 'Win32_SystemEnclosure' }
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'Battery' } } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'AMD Ryzen 7' } } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4060' } } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
    }

    It 'builds a Windows 11 Pro laptop profile' {
        $p = Get-TabulaProfile
        $p.Os.Build | Should -Be 26100
        $p.Os.Is11 | Should -BeTrue
        $p.Os.Edition | Should -Be 'Pro'
        $p.Os.DisplayVersion | Should -Be '24H2'
        $p.Chassis | Should -Be 'laptop'
        $p.Storage.SystemDiskType | Should -Be 'ssd'
        $p.Ram.GB | Should -Be 16
        $p.Gpu[0].Vendor | Should -Be 'NVIDIA'
        $p.IsVm | Should -BeFalse
        $p.WingetPresent | Should -BeTrue
        $p.Supported | Should -BeTrue
        Get-TabulaProfileSummary -Profile $p | Should -Be 'Windows 11 Pro 24H2 | Laptop | SSD | 16 GB'
    }

    It 'never throws when a probe fails, and marks the field unknown' {
        Mock Get-TabulaSystemDisk { throw 'no disk' }
        $p = Get-TabulaProfile
        $p.Storage.SystemDiskType | Should -Be 'unknown'
        $p.Chassis | Should -Be 'laptop'
    }

    It 'marks Windows older than 10 2004 and Server as unsupported' {
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Pro'; BuildNumber = '18363'; ProductType = 1 } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        (Get-TabulaProfile).Supported | Should -BeFalse
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Windows Server 2022'; BuildNumber = '20348'; ProductType = 3 } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        (Get-TabulaProfile).SupportReason | Should -Match 'Server'
    }

    It 'detects a Windows 10 desktop VM' {
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Pro'; BuildNumber = '19045'; ProductType = 1 } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        Mock Get-CimInstance { [pscustomobject]@{ TotalPhysicalMemory = 8589934592; Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'; UserName = 'PC\me' } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        Mock Get-CimInstance { [pscustomobject]@{ ChassisTypes = @(3) } } -ParameterFilter { $ClassName -eq 'Win32_SystemEnclosure' }
        Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        $p = Get-TabulaProfile
        $p.Os.Is11 | Should -BeFalse
        $p.IsVm | Should -BeTrue
        $p.Chassis | Should -Be 'desktop'
    }
}
