# Get-TabulaProfile: one object describing the machine. Every probe is wrapped, a failed one becomes 'unknown'.

function Invoke-TabulaProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Script, $Default = 'unknown')
    try { & $Script }
    catch {
        Write-TabulaLog ("probe '{0}' failed: {1}" -f $Name, $_.Exception.Message) -Level WARN
        $Default
    }
}

function ConvertTo-TabulaEdition {
    [CmdletBinding()]
    param([string]$EditionId)
    switch -Regex ($EditionId) {
        '^Server' { return 'Server' }
        '^Core' { return 'Home' }
        '^Professional' { return 'Pro' }
        '^Enterprise' { return 'Enterprise' }
        '^Education' { return 'Education' }
        default { return 'Other' }
    }
}

function Get-TabulaChassisClass {
    # Portable and desktop enclosure codes from Win32_SystemEnclosure. When the code says nothing useful
    # (Other, Unknown, empty) a battery decides, per the brief. A desktop with a UPS still reads as desktop.
    [CmdletBinding()]
    param([int[]]$ChassisTypes = @(), [bool]$HasBattery = $false)
    $portable = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $desktop = 3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 35, 36
    if (@($ChassisTypes | Where-Object { $portable -contains $_ }).Count -gt 0) { return 'laptop' }
    if (@($ChassisTypes | Where-Object { $desktop -contains $_ }).Count -gt 0) { return 'desktop' }
    if ($HasBattery) { return 'laptop' }
    'unknown'
}

function Test-TabulaVirtualMachine {
    [CmdletBinding()]
    param([string]$Manufacturer, [string]$Model)
    $text = "$Manufacturer $Model"
    if ($text -match 'VMware|VirtualBox|innotek|QEMU|KVM|Bochs|Xen|Parallels') { return $true }
    # Hyper-V and Windows Sandbox report Microsoft Corporation / Virtual Machine.
    ($Manufacturer -match 'Microsoft' -and $Model -match 'Virtual Machine')
}

function Get-TabulaGpuVendor {
    [CmdletBinding()]
    param([string]$Name)
    if ($Name -match 'NVIDIA') { return 'NVIDIA' }
    if ($Name -match 'AMD|Radeon|ATI ') { return 'AMD' }
    if ($Name -match 'Intel') { return 'Intel' }
    'Other'
}

function ConvertTo-TabulaDiskType {
    [CmdletBinding()]
    param([string]$MediaType, [string]$BusType)
    if ($BusType -eq 'NVMe') { return 'ssd' }
    switch ($MediaType) { 'SSD' { return 'ssd' } 'HDD' { return 'hdd' } default { return 'unknown' } }
}

function Get-TabulaSystemDisk {
    # The physical disk behind C:. DeviceId matching the disk number is an assumption that holds for
    # plain disks; Storage Spaces can break it, in which case the caller gets 'unknown'.
    [CmdletBinding()]
    param()
    $part = Get-Partition -DriveLetter C -ErrorAction Stop
    $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq [string]$part.DiskNumber } | Select-Object -First 1
    if (-not $pd) { throw 'no physical disk matches the system partition' }
    [pscustomobject]@{ MediaType = [string]$pd.MediaType; BusType = [string]$pd.BusType }
}

function Get-TabulaRegString {
    param([string]$Key, [string]$Name)
    [Microsoft.Win32.Registry]::GetValue($Key, $Name, $null)
}

function Get-TabulaProfile {
    [CmdletBinding()]
    param()

    $ntKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = Invoke-TabulaProbe 'os' { Get-CimInstance -ClassName Win32_OperatingSystem } $null
    $cs = Invoke-TabulaProbe 'computersystem' { Get-CimInstance -ClassName Win32_ComputerSystem } $null

    $build = Invoke-TabulaProbe 'build' { [int]$os.BuildNumber }
    $editionId = Invoke-TabulaProbe 'edition' { [string](Get-TabulaRegString $ntKey 'EditionID') } ''
    $displayVersion = Invoke-TabulaProbe 'displayversion' {
        $v = Get-TabulaRegString $ntKey 'DisplayVersion'
        if (-not $v) { $v = Get-TabulaRegString $ntKey 'ReleaseId' }
        if ($v) { [string]$v } else { 'unknown' }
    }

    $chassis = Invoke-TabulaProbe 'chassis' {
        $types = @((Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes)
        $battery = @(Get-CimInstance -ClassName Win32_Battery).Count -gt 0
        Get-TabulaChassisClass -ChassisTypes $types -HasBattery $battery
    }

    $disk = Invoke-TabulaProbe 'storage' {
        $d = Get-TabulaSystemDisk
        ConvertTo-TabulaDiskType -MediaType $d.MediaType -BusType $d.BusType
    }

    $gpus = @(Invoke-TabulaProbe 'gpu' {
            Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Vendor = (Get-TabulaGpuVendor $_.Name) }
            }
        } @())

    $isAdmin = Invoke-TabulaProbe 'admin' {
        ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } $false

    $wingetVersion = Invoke-TabulaProbe 'winget' { Get-TabulaWingetVersion } $null

    $pending = Invoke-TabulaProbe 'pendingreboot' {
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        [bool](Get-TabulaRegString 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations')
    } $false

    $edition = ConvertTo-TabulaEdition $editionId
    $productType = Invoke-TabulaProbe 'producttype' { [int]$os.ProductType } 1
    $supported = $true; $reason = ''
    if ($build -isnot [int]) { $supported = $false; $reason = 'Could not read the Windows build number.' }
    elseif ($build -lt 19041) { $supported = $false; $reason = 'Needs Windows 10 version 2004 or later.' }
    elseif ($edition -eq 'Server' -or $productType -ne 1) { $supported = $false; $reason = 'Windows Server is not supported.' }

    $user = Invoke-TabulaProbe 'user' { [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    $interactive = Invoke-TabulaProbe 'interactiveuser' { [string]$cs.UserName }

    [pscustomobject]@{
        Os              = [pscustomobject]@{
            Caption        = (Invoke-TabulaProbe 'caption' { [string]$os.Caption })
            Build          = $build
            DisplayVersion = $displayVersion
            Edition        = $edition
            Is11           = ($build -is [int] -and $build -ge 22000)
        }
        Chassis         = $chassis
        Storage         = [pscustomobject]@{ SystemDiskType = $disk }
        Ram             = [pscustomobject]@{ GB = (Invoke-TabulaProbe 'ram' { [math]::Round($cs.TotalPhysicalMemory / 1GB) }) }
        Cpu             = [pscustomobject]@{ Name = (Invoke-TabulaProbe 'cpu' { (Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1).Name }) }
        Gpu             = $gpus
        IsVm            = (Invoke-TabulaProbe 'vm' { Test-TabulaVirtualMachine -Manufacturer ([string]$cs.Manufacturer) -Model ([string]$cs.Model) } $false)
        IsAdmin         = $isAdmin
        User            = $user
        InteractiveUser = $interactive
        WingetPresent   = [bool]$wingetVersion
        WingetVersion   = $wingetVersion
        PendingReboot   = $pending
        Supported       = $supported
        SupportReason   = $reason
    }
}

function Get-TabulaProfileSummary {
    # "Windows 11 Pro 24H2 | Laptop | SSD | 16 GB" for the Setup page and the CLI header.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)
    $os = '{0} {1}' -f $Profile.Os.Caption.Replace('Microsoft ', ''), $Profile.Os.DisplayVersion
    $parts = @($os, (Get-Culture).TextInfo.ToTitleCase([string]$Profile.Chassis), ([string]$Profile.Storage.SystemDiskType).ToUpper(), ('{0} GB' -f $Profile.Ram.GB))
    $parts -join ' | '
}
