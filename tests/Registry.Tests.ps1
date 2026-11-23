BeforeAll { . $PSScriptRoot\TestHelper.ps1 }
AfterAll { Remove-TestRegistry }

Describe 'Registry wrapper' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'restores a value that existed' {
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V' -ValueType String -Value 'old' -CreateKey
        $prior = Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V'
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V' -ValueType String -Value 'new'
        Get-TestRegValue 'A' 'V' | Should -Be 'new'
        Restore-TabulaRegistryState -Prior $prior
        Get-TestRegValue 'A' 'V' | Should -Be 'old'
    }

    It 'restores the original value type, not just the data' {
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V' -ValueType String -Value '7' -CreateKey
        $prior = Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V'
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V' -ValueType DWord -Value 7
        Restore-TabulaRegistryState -Prior $prior
        (Get-TestRegValue 'A' 'V') | Should -BeOfType [string]
    }

    It 'deletes a value that did not exist and keeps its key' {
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'Other' -ValueType DWord -Value 1 -CreateKey
        $prior = Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V'
        $prior['keyExisted'] | Should -BeTrue
        $prior['valueExisted'] | Should -BeFalse
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\A' -Name 'V' -ValueType DWord -Value 5
        Restore-TabulaRegistryState -Prior $prior
        Get-TestRegValue 'A' 'V' | Should -Be '<<absent>>'
        Get-TestRegValue 'A' 'Other' | Should -Be 1
    }

    It 'removes only the keys it created' {
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\Keep' -Name 'x' -ValueType DWord -Value 1 -CreateKey
        $prior = Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\Keep\B\C' -Name 'V'
        $prior['keyExisted'] | Should -BeFalse
        @($prior['createdKeys']).Count | Should -Be 2
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\Keep\B\C' -Name 'V' -ValueType DWord -Value 1 -CreateKey
        Restore-TabulaRegistryState -Prior $prior
        Test-TestRegKey 'Keep' | Should -BeTrue
        Test-TestRegKey 'Keep\B' | Should -BeFalse
    }

    It 'leaves a created key alone if something else has since been put in it' {
        $prior = Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\New' -Name 'V'
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\New' -Name 'V' -ValueType DWord -Value 1 -CreateKey
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\New' -Name 'Someone' -ValueType DWord -Value 9
        Restore-TabulaRegistryState -Prior $prior
        Get-TestRegValue 'New' 'V' | Should -Be '<<absent>>'
        Get-TestRegValue 'New' 'Someone' | Should -Be 9
    }

    It 'handles the (Default) value' {
        $prior = Get-TabulaRegistryState -Hive HKCU -Path 'Software\TabulaTest\D\Inproc' -Name '(Default)'
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\D\Inproc' -Name '(Default)' -ValueType String -Value '' -CreateKey
        Get-TestRegValue 'D\Inproc' '(Default)' | Should -Be ''
        Restore-TabulaRegistryState -Prior $prior
        Test-TestRegKey 'D' | Should -BeFalse
    }

    It 'round-trips DWords above Int32 range' {
        Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\W' -Name 'V' -ValueType DWord -Value 4294967295 -CreateKey
        Get-TestRegValue 'W' 'V' | Should -Be -1
        Test-TabulaRegistryTarget -Action (New-TestRegAction 'W' 'V' 4294967295) | Should -BeTrue
        Test-TabulaRegistryTarget -Action (New-TestRegAction 'W' 'V' 1) | Should -BeFalse
    }

    It 'survives a JSON round trip of the prior state for every value type' {
        $path = 'Software\TabulaTest\Types'
        Set-TabulaRegistryValue -Hive HKCU -Path $path -Name 'Q' -ValueType QWord -Value 5000000000 -CreateKey
        Set-TabulaRegistryValue -Hive HKCU -Path $path -Name 'M' -ValueType MultiString -Value @('a', 'b')
        Set-TabulaRegistryValue -Hive HKCU -Path $path -Name 'B' -ValueType Binary -Value @(1, 2, 255)
        Set-TabulaRegistryValue -Hive HKCU -Path $path -Name 'E' -ValueType ExpandString -Value '%TEMP%\x'
        $priors = foreach ($n in 'Q', 'M', 'B', 'E') { Get-TabulaRegistryState -Hive HKCU -Path $path -Name $n }
        $json = ConvertTo-Json -InputObject @($priors) -Depth 8
        $back = ConvertTo-TabulaData ($json | ConvertFrom-Json)
        foreach ($n in 'Q', 'M', 'B', 'E') { Set-TabulaRegistryValue -Hive HKCU -Path $path -Name $n -ValueType String -Value 'x' }
        foreach ($p in $back) { Restore-TabulaRegistryState -Prior $p }
        Get-TestRegValue 'Types' 'Q' | Should -Be 5000000000
        (Get-TestRegValue 'Types' 'M') -join ',' | Should -Be 'a,b'
        (Get-TestRegValue 'Types' 'B') -join ',' | Should -Be '1,2,255'
        (Get-TestRegValue 'Types' 'E') | Should -Be '%TEMP%\x'
    }

    It 'refuses to write into a missing key unless asked to create it' {
        { Set-TabulaRegistryValue -Hive HKCU -Path 'Software\TabulaTest\Nope' -Name 'V' -ValueType DWord -Value 1 } | Should -Throw
    }
}
