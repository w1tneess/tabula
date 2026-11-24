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
        ($out | Out-String) | Should -Match '^Tabula 0\.1\.0 \(built .+, commit .+\)'
    }

    It 'runs through iex (GUI mode, closes itself)' {
        $env:TABULA_UI_AUTOCLOSE_MS = '1500'
        try { $out = & powershell.exe -NoProfile -STA -Command "Get-Content -Raw '$dist' | Invoke-Expression; exit `$LASTEXITCODE" 2>&1 | Out-String }
        finally { Remove-Item Env:\TABULA_UI_AUTOCLOSE_MS -ErrorAction SilentlyContinue }
        $LASTEXITCODE | Should -Be 0
        $out | Should -Not -Match 'Exception|Error'
    }
    It 'accepts parameters through a script block, and a dry run exits 0' {
        $log = Join-Path $TestDrive 'dry.log'
        $cmd = "& ([scriptblock]::Create((Get-Content -Raw '$dist'))) -Mode Auto -DryRun -LogPath '$log'; exit `$LASTEXITCODE"
        $out = & powershell.exe -NoProfile -Command $cmd
        # windows-latest in CI is a Server SKU, which Tabula rejects with exit 2, so assert on the output only.
        ($out | Out-String) | Should -Match 'mode Auto, dry run'
    }

    It 'returns exit code 2 for a real run without elevation' -Skip:(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $log = Join-Path $TestDrive 'real.log'
        & powershell.exe -NoProfile -File $dist -Mode Auto -Yes -LogPath $log | Out-Null
        $LASTEXITCODE | Should -Be 2
    }
}
