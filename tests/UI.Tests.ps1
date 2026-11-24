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

Describe 'Driving the engine from the window (real buttons, fixture config, scratch registry key, stubbed winget)' {
    BeforeAll {
        $run = {
            param($mode)
            $out = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $script:root 'tests\UiRunHarness.ps1') -Mode $mode 2>&1 | Out-String
            $out.Trim() | ConvertFrom-Json
        }
        $script:flow = & $run 'Flow'
        $script:nonAdmin = & $run 'NotAdmin'
    }

    It 'finishes every step without a timeout or a handler error' {
        @($script:flow.errors) | Should -BeNullOrEmpty
        @($script:nonAdmin.errors) | Should -BeNullOrEmpty
        $script:flow.logFileText | Should -Not -Match 'handler failed'
        $script:flow.logFileText | Should -Not -Match '\[ERROR\]'
    }

    It 'gates the buttons: no admin, nothing ticked, no run to undo' {
        $b = $script:flow.steps.initial.buttons
        $b.BtnApply.enabled | Should -BeFalse
        $b.BtnStageApply.enabled | Should -BeFalse
        $b.BtnUndoLast.tip | Should -Be 'No run to undo.'
        $n = $script:nonAdmin.steps.initial.buttons
        $n.BtnInstall.tip | Should -Be 'Needs an elevated PowerShell.'
        $n.BtnUndoLast.tip | Should -Be 'Needs an elevated PowerShell.'
        $script:nonAdmin.steps.plan.buttons.BtnApply.enabled | Should -BeFalse
        $script:nonAdmin.steps.plan.buttons.BtnDry.enabled | Should -BeTrue
    }

    It 'dry run from the window shows every item and changes nothing, with or without admin' {
        foreach ($d in $script:flow.steps.dry, $script:nonAdmin.steps.dry) {
            @($d.rows) | Should -Be @('tweak:t-one=Would apply', 'tweak:t-two=Would apply', 'app:fx-a=Would apply', 'app:fx-b=Would apply')
            $d.summary | Should -Be '4 changes ready. Nothing applied.'
            $d.reg.One | Should -Be '<<absent>>'
            $d.stateExists | Should -BeFalse
        }
    }

    It 'applies the plan with live status and log lines, and cancel stops after the running item' {
        $a = $script:flow.steps.apply
        $script:flow.steps.cancelWhileRunning | Should -BeTrue
        @($a.rows) | Should -Be @('tweak:t-one=Applied', 'tweak:t-two=Applied', 'app:fx-a=Applied', 'app:fx-b=Not run')
        $a.title | Should -Be 'Cancelled'
        $a.summary | Should -Match '1 not run \(cancelled\)'
        $a.reg.One | Should -Be '1'
        $a.log | Should -Match 'tweak:t-one applied'      # streamed from the job to the log panel
        $script:flow.logFileText | Should -Match 'tweak:t-one applied'   # and written to the log file by the UI thread
        $a.undoVisible | Should -BeTrue
        $script:flow.steps.applyButtons.BtnUndoLast.enabled | Should -BeTrue
    }

    It 'undoes the run newest change first, says apps stay, and then has nothing left to undo' {
        $u = $script:flow.steps.undo
        @($u.rows) | Should -Be @('tweak:t-two=Reverted', 'tweak:t-one=Reverted')
        $u.summary | Should -Match 'Undo complete.*Installed apps stay installed'
        $u.reg.One | Should -Be '<<absent>>'
        $u.reg.Two | Should -Be '<<absent>>'
        $script:flow.steps.undoAfter.BtnUndoLast.enabled | Should -BeFalse
    }

    It 'stages a tweak and applies it; unverified tweaks cannot be staged; an applied tweak cannot be switched off' {
        $script:flow.steps.stagedBefore.exp | Should -BeFalse
        $script:flow.steps.stagedBefore.one | Should -BeTrue
        $script:flow.steps.stagedBar.visible | Should -BeTrue
        $script:flow.steps.stagedBar.button.BtnStageApply.enabled | Should -BeTrue
        @($script:flow.steps.stage.rows) | Should -Be @('tweak:t-one=Applied')
        $script:flow.steps.stage.reg.Exp | Should -Be '<<absent>>'
        $after = $script:flow.steps.stageAfter
        $after.baseline | Should -BeTrue
        $after.enabled | Should -BeFalse
        $after.reason | Should -Match '^On\.'
    }

    It 'installs only the ticked apps' {
        @($script:flow.steps.install.rows) | Should -Be @('app:fx-a=Applied')
    }

    It 'waits for the running item when the window is closed during a real run, then closes' {
        $script:flow.steps.visibleAfterClose | Should -BeTrue   # Close() was refused while an app was installing
        $script:flow.closedByRun | Should -BeTrue
        @($script:flow.steps.closeRun.rows) | Should -Be @('tweak:t-one=Skipped', 'tweak:t-two=Applied', 'app:fx-a=Applied', 'app:fx-b=Not run')
    }
}

Describe 'Run view styling' {
    It 'uses themed templates for every control in the run view' {
        # The NotAdmin run is the short one: it shows the Run view after a dry run, which is all this needs.
        $out = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $script:root 'tests\UiRunHarness.ps1') -Mode NotAdmin 2>&1 | Out-String
        $scan = ($out.Trim() | ConvertFrom-Json).steps.runViewScan
        $scan.checked | Should -BeGreaterThan 3
        @($scan.defaultLooking) -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'Copy rules (docs/04-ui-design-spec.md)' {
    It 'has no exclamation marks, emojis, non-ASCII text or hype words in the window copy' {
        $files = Get-ChildItem (Join-Path $script:root 'src\UI') -Include *.xaml, UI.ps1 -Recurse
        $bad = foreach ($f in $files) {
            $text = [IO.File]::ReadAllText($f.FullName)
            if ($f.Extension -eq '.xaml') {
                # Only attribute values and text nodes that are shown: Text, Content, Header, ToolTip, Name.
                foreach ($m in [regex]::Matches($text, '(?:Text|Content|Header|ToolTip|AutomationProperties\.Name)="([^"{][^"]*)"')) {
                    if ($m.Groups[1].Value -match '!|awesome|amazing|oops') { '{0}: {1}' -f $f.Name, $m.Groups[1].Value }
                }
            }
            else {
                foreach ($m in [regex]::Matches($text, "(?:Set-TabulaStatus|\.Text\s*=|Reason\s*=|\`$text\s*\+?=)\s*[\(]?'([^']*)'")) {
                    if ($m.Groups[1].Value -match '!|awesome|amazing|oops') { '{0}: {1}' -f $f.Name, $m.Groups[1].Value }
                }
            }
            if ($text -match '[^\x00-\x7F]') { '{0}: non-ASCII character' -f $f.Name }
        }
        @($bad) -join '; ' | Should -BeNullOrEmpty
    }
}

Describe 'Keyboard, layout and error states (off-screen window)' {
    BeforeAll {
        $run = { param($mode) ((& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $script:root 'tests\UiRunHarness.ps1') -Mode $mode 2>&1 | Out-String).Trim() | ConvertFrom-Json) }
        $script:kb = & $run 'NotAdmin'
        $script:nowinget = & $run 'NoWinget'
        $script:unsup = & $run 'Unsupported'
    }

    It 'opens as a per-monitor DPI aware process so it is not bitmap-scaled' {
        $script:kb.steps.initial.dpi | Should -Be 'per-monitor'
    }

    It 'every stop in the tab order has a name, and each page has at least one stop beyond the rail' {
        @($script:kb.errors) | Should -BeNullOrEmpty
        foreach ($p in $script:kb.steps.tabOrder.PSObject.Properties) {
            $p.Value.unnamed | Should -Be 0 -Because $p.Name
            @($p.Value.names).Count | Should -BeGreaterThan 5 -Because $p.Name
            @($p.Value.names | Where-Object { $_ -like 'System.*' }) | Should -BeNullOrEmpty -Because $p.Name
        }
    }

    It 'nothing sticks out of the window at the smallest allowed size, on any page or view' {
        $script:kb.steps.minSize | Should -Be '860x560'
        foreach ($p in $script:kb.steps.overflow.PSObject.Properties) { @($p.Value) -join ', ' | Should -BeNullOrEmpty -Because $p.Name }
    }

    It 'says why when winget is missing: status per app, a summary line, and a reason on each failed row' {
        @($script:nowinget.errors) | Should -BeNullOrEmpty
        @($script:nowinget.steps.appStatus) | Should -Be @('fx-a=No winget', 'fx-b=No winget')
        $script:nowinget.steps.apply.title | Should -Be 'Finished with problems'
        @($script:nowinget.steps.apply.rows) | Should -Be @('tweak:t-one=Applied', 'tweak:t-two=Applied', 'app:fx-a=Failed', 'app:fx-b=Failed')
    }

    It 'blocks setup with the reason on an unsupported machine' {
        $u = $script:unsup.steps.unsupported
        $u.machine | Should -Be 'Windows Server is not supported.'
        $u.buttons.BtnSetup.enabled | Should -BeFalse
        $u.buttons.BtnReview.enabled | Should -BeFalse
    }
}
