BeforeAll {
    $script:root = Split-Path -Parent $PSScriptRoot
    $script:dist = Join-Path $root 'dist\tabula.ps1'
    & (Join-Path $root 'build.ps1') | Out-Null
}

Describe 'M0 build' {
    It 'produces dist/tabula.ps1 and a matching sha256' {
        Test-Path $dist | Should -BeTrue
        $line = (Get-Content "$dist.sha256" -Raw).Trim()
        $line | Should -Be ((Get-FileHash $dist -Algorithm SHA256).Hash.ToLower() + '  tabula.ps1')
    }

    It 'parses without errors' {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($dist, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'prints its version from a fresh Windows PowerShell 5.1' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dist -Version
        ($out | Out-String) | Should -Match '^Tabula 0\.0\.1 \(built .+, commit .+\)'
    }

    It 'runs through iex' {
        $out = & powershell.exe -NoProfile -Command "Get-Content -Raw '$dist' | Invoke-Expression"
        ($out | Out-String) | Should -Match 'Mode Gui is not implemented yet'
    }

    It 'accepts parameters through a script block' {
        $cmd = "& ([scriptblock]::Create((Get-Content -Raw '$dist'))) -Mode Auto -DryRun"
        $out = & powershell.exe -NoProfile -Command $cmd
        ($out | Out-String) | Should -Match 'Mode Auto is not implemented yet'
    }
}
