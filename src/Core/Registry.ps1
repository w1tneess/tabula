# Registry wrappers that record prior state. Uses RegistryKey directly (not the provider) so
# the (Default) value, value kinds and the 64-bit view are handled exactly.

function Open-TabulaHive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('HKCU', 'HKLM')][string]$Hive)
    $h = if ($Hive -eq 'HKCU') { [Microsoft.Win32.RegistryHive]::CurrentUser } else { [Microsoft.Win32.RegistryHive]::LocalMachine }
    [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, [Microsoft.Win32.RegistryView]::Registry64)
}

function ConvertTo-TabulaRegName {
    param([string]$Name)
    if ($Name -eq '(Default)') { '' } else { $Name }
}

function ConvertTo-TabulaRegValue {
    param([string]$ValueType, $Value)
    switch ($ValueType) {
        'DWord' {
            # Registry DWords above 2^31 arrive as larger numbers from JSON; SetValue wants the Int32 bit pattern.
            $n = [long]$Value
            if ($n -gt [int]::MaxValue) { [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$n), 0) } else { [int]$n }
        }
        'QWord' { [long]$Value }
        'String' { [string]$Value }
        'ExpandString' { [string]$Value }
        'MultiString' { , ([string[]]@($Value)) }
        'Binary' { , ([byte[]]@($Value)) }
        default { throw "Unsupported registry value type '$ValueType'" }
    }
}

function Get-TabulaRegistryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hive, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $valueName = ConvertTo-TabulaRegName $Name
    $base = Open-TabulaHive $Hive
    try {
        # Every ancestor that does not exist yet, topmost first. Undo removes only these, never a key that was already there.
        $missing = New-Object System.Collections.Generic.List[string]
        $current = ''
        foreach ($part in $Path.Split('\')) {
            $current = if ($current) { "$current\$part" } else { $part }
            $k = $base.OpenSubKey($current)
            if ($k) { $k.Close() } else { $missing.Add($current) }
        }

        $valueExisted = $false; $value = $null; $kind = $null
        if ($missing.Count -eq 0) {
            $k = $base.OpenSubKey($Path)
            try {
                if ($k.GetValueNames() -contains $valueName) {
                    $valueExisted = $true
                    $kind = $k.GetValueKind($valueName).ToString()
                    $raw = $k.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    $value = if ($raw -is [byte[]]) { , ([int[]]$raw) } else { $raw }
                }
            }
            finally { $k.Close() }
        }
        @{
            type         = 'registry'
            hive         = $Hive
            path         = $Path
            name         = $Name
            keyExisted   = ($missing.Count -eq 0)
            valueExisted = $valueExisted
            valueType    = $kind
            value        = $value
            createdKeys  = @($missing)
        }
    }
    finally { $base.Close() }
}

function Set-TabulaRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hive, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ValueType, $Value, [switch]$CreateKey
    )
    $valueName = ConvertTo-TabulaRegName $Name
    $base = Open-TabulaHive $Hive
    try {
        $k = $base.OpenSubKey($Path, $true)
        if (-not $k) {
            if (-not $CreateKey) { throw "Registry key not found: $Hive\$Path" }
            $k = $base.CreateSubKey($Path)
        }
        try { $k.SetValue($valueName, (ConvertTo-TabulaRegValue $ValueType $Value), [Microsoft.Win32.RegistryValueKind]$ValueType) }
        finally { $k.Close() }
    }
    finally { $base.Close() }
}

function Restore-TabulaRegistryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Prior)
    $valueName = ConvertTo-TabulaRegName $Prior['name']
    if ($Prior['valueExisted']) {
        Set-TabulaRegistryValue -Hive $Prior['hive'] -Path $Prior['path'] -Name $Prior['name'] -ValueType $Prior['valueType'] -Value $Prior['value'] -CreateKey
    }
    $base = Open-TabulaHive $Prior['hive']
    try {
        if (-not $Prior['valueExisted']) {
            $k = $base.OpenSubKey($Prior['path'], $true)
            if ($k) {
                try { if ($k.GetValueNames() -contains $valueName) { $k.DeleteValue($valueName) } }
                finally { $k.Close() }
            }
        }
        # Remove keys we created, deepest first, and only if nothing else has since been put in them.
        $created = @($Prior['createdKeys'])
        [array]::Reverse($created)
        foreach ($key in $created) {
            $k = $base.OpenSubKey($key)
            if ($k) {
                $empty = ($k.SubKeyCount -eq 0 -and $k.ValueCount -eq 0)
                $k.Close()
                if ($empty) { $base.DeleteSubKey($key) }
            }
        }
    }
    finally { $base.Close() }
}

function ConvertTo-TabulaUInt32 {
    # The registry hands back DWords as signed Int32; configs write them as plain positive numbers.
    param($Value)
    $n = [long]$Value
    if ($n -lt 0) { [uint32]($n + 4294967296) } else { [uint32]$n }
}

function Test-TabulaRegistryTarget {
    # True when the current value already equals the action's target.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Action)
    $now = Get-TabulaRegistryState -Hive $Action.hive -Path $Action.path -Name $Action.name
    if (-not $now['valueExisted'] -or $now['valueType'] -ne $Action.valueType) { return $false }
    $cur = $now['value']; $want = $Action.value
    switch ($Action.valueType) {
        'DWord' { return ((ConvertTo-TabulaUInt32 $cur) -eq (ConvertTo-TabulaUInt32 $want)) }
        'QWord' { return ([long]$cur -eq [long]$want) }
        { $_ -in 'MultiString', 'Binary' } { return ((@($cur) -join ',') -eq (@($want) -join ',')) }
        default { return ([string]$cur -ceq [string]$want) }
    }
}
