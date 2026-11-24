BeforeAll {
    $script:root = Split-Path -Parent $PSScriptRoot
    & (Join-Path $script:root 'build.ps1') | Out-Null
    $script:dist = Join-Path $script:root 'dist\tabula.ps1'

    function ConvertTo-Luminance([string]$hex) {
        $c = foreach ($i in 1, 3, 5) { [Convert]::ToInt32($hex.Substring($i, 2), 16) / 255 }
        $lin = $c | ForEach-Object { if ($_ -le 0.03928) { $_ / 12.92 } else { [math]::Pow(($_ + 0.055) / 1.055, 2.4) } }
        0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2]
    }
    function Get-Contrast([string]$a, [string]$b) {
        $la = ConvertTo-Luminance $a; $lb = ConvertTo-Luminance $b
        ([math]::Max($la, $lb) + 0.05) / ([math]::Min($la, $lb) + 0.05)
    }
    function Get-Palette([string]$file) {
        $xml = [IO.File]::ReadAllText((Join-Path $script:root "src\UI\$file"))
        $p = @{}
        foreach ($m in [regex]::Matches($xml, 'x:Key="(\w+)Brush" Color="(#[0-9A-Fa-f]{6})"')) { $p[$m.Groups[1].Value] = $m.Groups[2].Value }
        $p
    }
}

Describe 'Theme contrast (WCAG AA, 4.5:1 for text)' {
    It '<theme> palette meets AA for every text pairing' -ForEach @(
        @{ theme = 'Dark'; file = 'Theme.Dark.xaml' }
        @{ theme = 'Light'; file = 'Theme.Light.xaml' }
    ) {
        $p = Get-Palette $file
        $p.Count | Should -Be 12
        $pairs = @(
            @('Text', 'Bg'), @('Text', 'Surface'), @('Text', 'SurfaceHover'),
            @('TextDim', 'Bg'), @('TextDim', 'Surface'), @('TextDim', 'SurfaceHover'),
            @('Accent', 'Bg'), @('Accent', 'Surface'), @('AccentText', 'Accent'),
            @('Ok', 'Surface'), @('Warn', 'Surface'), @('Err', 'Surface')
        )
        $bad = foreach ($pair in $pairs) {
            $r = Get-Contrast $p[$pair[0]] $p[$pair[1]]
            if ($r -lt 4.5) { '{0} on {1} = {2:N2}' -f $pair[0], $pair[1], $r }
        }
        @($bad) -join '; ' | Should -BeNullOrEmpty
    }

    It 'defines the same tokens in both palettes' {
        (Get-Palette 'Theme.Dark.xaml').Keys | Sort-Object | Should -Be ((Get-Palette 'Theme.Light.xaml').Keys | Sort-Object)
    }
}

Describe 'Window (opened off-screen in its own STA process)' {
    BeforeAll {
        $script:runs = @{}
        foreach ($theme in 'Dark', 'Light') {
            $json = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $script:root 'tests\UiHarness.ps1') -Theme $theme 2>&1 | Out-String
            $script:runs[$theme] = $json.Trim() | ConvertFrom-Json
        }
    }

    It 'lays out all five pages in the <theme> theme' -ForEach @(@{ theme = 'Dark' }, @{ theme = 'Light' }) {
        $r = $script:runs[$theme]
        @($r.pages.PSObject.Properties.Name | Sort-Object) | Should -Be @('About', 'Apps', 'Setup', 'Tools', 'Tweaks')
        foreach ($p in $r.pages.PSObject.Properties) { $p.Value.w | Should -BeGreaterThan 300; $p.Value.h | Should -BeGreaterThan 300 }
        $r.light | Should -Be ($theme -eq 'Light')
    }

    It 'uses no default-looking WPF controls (<theme>)' -ForEach @(@{ theme = 'Dark' }, @{ theme = 'Light' }) {
        $r = $script:runs[$theme]
        $r.checked | Should -BeGreaterThan 40
        @($r.defaultLooking) -join ', ' | Should -BeNullOrEmpty
    }

    It 'stays responsive while a three second background task runs (<theme>)' -ForEach @(@{ theme = 'Dark' }, @{ theme = 'Light' }) {
        $r = $script:runs[$theme]
        $r.demoDone | Should -BeTrue
        $r.elapsedMs | Should -BeGreaterThan 2800
        $r.ticks | Should -BeGreaterThan 30
        $r.maxGapMs | Should -BeLessThan 400
    }
}

Describe 'Opening the window from the shipped script' {
    BeforeAll { $env:TABULA_UI_AUTOCLOSE_MS = '3500' }
    AfterAll { Remove-Item Env:\TABULA_UI_AUTOCLOSE_MS -ErrorAction SilentlyContinue }

    It 'opens and closes from a file in an STA console' {
        $log = Join-Path $TestDrive 'sta.log'
        & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $script:dist -Mode Gui -LogPath $log | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Get-Content $log -Raw) | Should -Not -Match 'ERROR'
    }

    It 'opens through iex' {
        $out = & powershell.exe -NoProfile -STA -Command "Get-Content -Raw '$script:dist' | Invoke-Expression; exit `$LASTEXITCODE" 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Not -Match 'Exception|Error'
    }

    It 'opens from an MTA console by using its own STA runspace' {
        $log = Join-Path $TestDrive 'mta.log'
        $cmd = "& ([scriptblock]::Create((Get-Content -Raw '$script:dist'))) -Mode Gui -LogPath '$log'; exit `$LASTEXITCODE"
        $out = & powershell.exe -NoProfile -MTA -Command $cmd 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        (Get-Content $log -Raw) | Should -Match 'not STA'
        $out | Should -Not -Match 'Exception'
    }
}
