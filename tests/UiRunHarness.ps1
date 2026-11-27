# Run in its own STA process by UI.Tests.ps1. Opens the real window off-screen, clicks the real buttons and prints one JSON line.
# Everything the engine changes lives under HKCU:\Software\TabulaTest. winget, the restore point and the elevation flag are
# stubbed here (functions defined before the window opens are copied into its job runspaces), so nothing real is installed.
param([ValidateSet('Flow', 'NotAdmin', 'Real', 'NoWinget', 'Unsupported', 'Shots')][string]$Mode = 'Flow', [ValidateSet('Dark', 'Light')][string]$Theme = 'Dark', [string]$ShotDir)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\TestHelper.ps1"
. "$repo\src\UI\UI.ps1"
Set-StrictMode -Version 2.0
$script:TabulaRoot = $repo

$work = Join-Path $env:TEMP ('tabula-run-harness-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Initialize-TestEnvironment $work   # state.json, test.log and a clean scratch registry key
$script:logFile = Join-Path $work 'test.log'

# ---- fixture config: two verified tweaks, one unverified, two apps ----
$cfgDir = Join-Path $work 'config'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$tweak = {
    param($id, $name, $verified, $valueName)
    $tested = if ($verified) { '[26100]' } else { '[]' }
    '{{ "id": "{0}", "name": "{1}", "category": "Interface", "description": "Fixture tweak.", "risk": "low", "requiresRestart": "explorer", "defaultOn": {2}, "verified": {2}, "testedBuilds": {3}, "detect": "actions", "undo": "restore-prior", "actions": [ {{ "type": "registry", "hive": "HKCU", "path": "Software\\TabulaTest\\Ui", "name": "{4}", "valueType": "DWord", "value": 1, "createKey": true }} ] }}' -f $id, $name, $verified.ToString().ToLower(), $tested, $valueName
}
$tweaks = @((& $tweak 't-one' 'Fixture one' $true 'One'), (& $tweak 't-two' 'Fixture two' $true 'Two'), (& $tweak 't-exp' 'Fixture experimental' $false 'Exp')) -join ','
[IO.File]::WriteAllText((Join-Path $cfgDir 'tweaks.json'), '{ "schemaVersion": 1, "tweaks": [' + $tweaks + '] }')
$app = '{{ "id": "{0}", "name": "{1}", "category": "Utilities", "description": "Fixture app.", "source": "winget", "wingetId": "{2}", "publisher": "Fixture", "officialUrl": "https://example.com/", "defaultSelected": true }}'
[IO.File]::WriteAllText((Join-Path $cfgDir 'apps.json'), '{ "schemaVersion": 1, "apps": [' + ((($app -f 'fx-a', 'Fixture A', 'Fixture.A'), ($app -f 'fx-b', 'Fixture B', 'Fixture.B')) -join ',') + '] }')
[IO.File]::WriteAllText((Join-Path $cfgDir 'presets.json'), '{ "schemaVersion": 1, "presets": [ { "id": "Standard", "name": "Standard", "description": "Fixture.", "apps": "defaultSelected", "tweaks": "defaultOn" } ] }')

# ---- stubs (copied into the job runspaces by name) ----
$origProfile = (Get-Command Get-TabulaProfile).ScriptBlock.ToString()
$admin = if ($Mode -in 'Flow', 'NoWinget') { '$true' } else { '$false' }
$supported = if ($Mode -eq 'Unsupported') { '$false' } else { '$true' }
if ($Mode -ne 'Real') {
Set-Item -Path Function:\Get-TabulaProfile -Value ([scriptblock]::Create("`$p = & { $origProfile }`n`$p.IsAdmin = $admin`n`$p.Supported = $supported`n`$p.SupportReason = 'Windows Server is not supported.'`n`$p"))
function Get-TabulaWingetPath { 'winget.exe' }
function Assert-TabulaWinget { $true }
function Test-TabulaAppInstalled { param($WingetId) $false }
function New-TabulaRestorePoint { param($RunId, [switch]$AllowEnable) @{ created = $true; sequence = 1; reason = $null } }
function Install-TabulaApp {
    param($App, [switch]$DryRun, [int]$TimeoutSec = 900)
    $id = [string]$App['id']; $name = [string]$App['name']
    if ($DryRun) { return New-TabulaResult -Kind app -Id $id -Name $name -Status dryrun -Reason 'would install' }
    Start-Sleep -Milliseconds 800
    Write-TabulaLog "app:$id installed (stub)"
    New-TabulaResult -Kind app -Id $id -Name $name -Status applied
}
if ($Mode -eq 'NoWinget') {
function Get-TabulaWingetPath { $null }
function Assert-TabulaWinget { $false }
}
if ($Mode -eq 'Shots') {
    # Documentation screenshots: the real catalog and window, but nothing read from this PC. No app counts as installed,
    # every tweak reads as off, and the log folder shows a neutral path.
    function Get-TabulaTweakState { param($Tweak, $Profile) [pscustomobject]@{ State = 'Unset'; Reason = '' } }
    $env:LOCALAPPDATA = 'C:\Users\you\AppData\Local'
    $script:TabulaBuild = @{ Version = '0.1.0'; Built = '2026-11-24'; Commit = 'dab9c8f' }
}
}   # Mode Real keeps the real profile, winget and catalog: dry run only, read-only checks

# ---- helpers ----
$script:result = [ordered]@{ mode = $Mode; errors = @(); steps = [ordered]@{}; closedByRun = $false }
function Click($name) {
    $b = $script:TabulaUi[$name]
    $b.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
}
function Get-ButtonState([string[]]$Names) {
    $o = [ordered]@{}
    foreach ($n in $Names) { $b = $script:TabulaUi[$n]; $o[$n] = [ordered]@{ enabled = [bool]$b.IsEnabled; tip = [string]$b.ToolTip } }
    $o
}
function Get-RunSnapshot {
    $u = $script:TabulaUi
    [ordered]@{
        title = $u.RunTitle.Text; summary = $u.RunSummary.Text
        rows = @($u.RunList.ItemsSource | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Id, $_.Status })
        log = $u.RunLog.Text; undoVisible = ($u.BtnRunUndo.Visibility -eq 'Visible'); cancelVisible = ($u.BtnRunCancel.Visibility -eq 'Visible')
        reg = [ordered]@{ One = "$(Get-TestRegValue 'Ui' 'One')"; Two = "$(Get-TestRegValue 'Ui' 'Two')"; Exp = "$(Get-TestRegValue 'Ui' 'Exp')" }
        stateExists = [IO.File]::Exists($script:TabulaStatePath)
    }
}
function Save-Shot([string]$Name) {
    # Documentation screenshots only (-ShotDir). Renders the window content on a painted background, like the M3 screenshots.
    if (-not $ShotDir) { return }
    $u = $script:TabulaUi; $c = $u.Window.Content; $u.Window.UpdateLayout()
    $w = [int]$c.ActualWidth; $h = [int]$c.ActualHeight
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen(); $dc.DrawRectangle($u.Window.Background, $null, (New-Object Windows.Rect 0, 0, $w, $h)); $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv); $rtb.Render($c)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $ShotDir ('{0}-{1}.png' -f $Name, $Theme.ToLower())))
    try { $enc.Save($fs) } finally { $fs.Close() }
}
function Get-TabOrder {
    # Logical focus works without the off-screen window being active. Walks Tab until it wraps.
    $w = $script:TabulaUi.Window
    $req = New-Object Windows.Input.TraversalRequest([Windows.Input.FocusNavigationDirection]::First)
    $names = New-Object System.Collections.Generic.List[string]; $unnamed = 0; $seen = New-Object System.Collections.Generic.HashSet[object]
    [void]$w.MoveFocus($req)
    $req = New-Object Windows.Input.TraversalRequest([Windows.Input.FocusNavigationDirection]::Next)
    for ($i = 0; $i -lt 150; $i++) {
        $f = $w.Dispatcher.Invoke([Func[object]] { [Windows.Input.Keyboard]::FocusedElement })
        if ($null -eq $f) { $f = [Windows.Input.FocusManager]::GetFocusedElement($w) }
        if ($null -eq $f -or -not $seen.Add($f)) { break }
        $n = [Windows.Automation.AutomationProperties]::GetName($f)
        if (-not $n -and $f -is [Windows.Controls.ContentControl]) { $n = [string]$f.Content }
        if (-not $n -and $f -is [Windows.Controls.TextBox]) { $n = [string]$f.Text }
        if (-not $n) { $unnamed++; $n = '<' + $f.GetType().Name + '>' }
        $names.Add($n)
        if (-not $f.MoveFocus($req)) { break }
    }
    [ordered]@{ names = $names.ToArray(); unnamed = $unnamed }
}
function Get-Overflow {
    # Visible elements that stick out past the right edge of the window content. Vertical overflow is scrolled, not clipped.
    $u = $script:TabulaUi; $root = $u.PageHost; $limit = $u.Window.Content.ActualWidth
    $bad = @()
    $q = New-Object System.Collections.Queue; $q.Enqueue($root)
    while ($q.Count -gt 0) {
        $e = $q.Dequeue()
        if ($e -is [Windows.UIElement] -and -not $e.IsVisible) { continue }
        if ($e -is [Windows.FrameworkElement] -and $e -isnot [Windows.Controls.ScrollViewer] -and $e.ActualWidth -gt 0 -and $e.ActualHeight -gt 0 -and $e -is [Windows.Controls.Control]) {
            $r = $e.TransformToAncestor($u.Window.Content).TransformBounds((New-Object Windows.Rect 0, 0, $e.ActualWidth, $e.ActualHeight))
            if ($r.Right -gt $limit + 1) { $bad += ('{0} right={1:N0}>{2:N0}' -f $e.GetType().Name, $r.Right, $limit) }
        }
        if ($e -is [Windows.Media.Visual]) { for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($e); $i++) { $q.Enqueue([Windows.Media.VisualTreeHelper]::GetChild($e, $i)) } }
    }
    $bad
}
$finished = { $u = $script:TabulaUi; (-not $u.Running) -and ($u.BtnRunBack.Visibility -eq 'Visible') -and [bool]$u.RunSummary.Text }
$idle = { $u = $script:TabulaUi; (-not $u.Running) -and (-not $u.CheckJob) -and (-not $u.DetectJob) -and (-not $u.PendingRun) }

$script:steps = New-Object System.Collections.Generic.List[hashtable]
function Add-Step([string]$Name, [scriptblock]$Do, [scriptblock]$Until = { $true }) { $script:steps.Add(@{ Name = $Name; Do = $Do; Until = $Until; Started = $false; T0 = $null }) }

Add-Step 'ready' { } { $u = $script:TabulaUi; [bool]$u.Profile -and (& $idle) }
Add-Step 'initial' {
    $script:result.steps.initial = [ordered]@{ buttons = (Get-ButtonState 'BtnApply', 'BtnDry', 'BtnInstall', 'BtnStageApply', 'BtnUndoLast'); admin = [bool]$script:TabulaUi.Profile.IsAdmin; dpi = (Set-TabulaDpiAwareness) }
}
if ($Mode -ne 'Unsupported') {
Add-Step 'plan' { Click 'BtnSetup' } { $script:TabulaUi.PlanView.Visibility -eq 'Visible' }
Add-Step 'plan-snap' {
    $u = $script:TabulaUi
    $script:result.steps.plan = [ordered]@{ rows = @($u.PlanRows | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Id }); buttons = (Get-ButtonState 'BtnApply', 'BtnDry') }
}
Add-Step 'dry' { Click 'BtnDry' } $finished
Add-Step 'dry-snap' {
    $script:result.steps.dry = Get-RunSnapshot
    Save-Shot 'Run-dry'
    # The Run view is new and was collapsed during the M3 scan: check that its controls use the themed templates.
    $u = $script:TabulaUi; $u.Window.UpdateLayout()
    $q = New-Object System.Collections.Queue; $q.Enqueue($u.RunView); $seen = 0; $bad = @()
    while ($q.Count -gt 0) {
        $e = $q.Dequeue()
        if ($e -is [Windows.Controls.Primitives.ButtonBase] -or $e -is [Windows.Controls.TextBox] -or $e -is [Windows.Controls.Primitives.ScrollBar]) {
            $seen++
            $src = [Windows.DependencyPropertyHelper]::GetValueSource($e, [Windows.Controls.Control]::TemplateProperty).BaseValueSource
            if ($src -eq 'DefaultStyle' -or $src -eq 'Default') { $bad += $e.GetType().Name }
        }
        if ($e -is [Windows.Media.Visual]) { for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($e); $i++) { $q.Enqueue([Windows.Media.VisualTreeHelper]::GetChild($e, $i)) } }
    }
    $script:result.steps.runViewScan = [ordered]@{ checked = $seen; defaultLooking = $bad }
}
}

if ($Mode -eq 'Flow') {
    Add-Step 'back-1' { Click 'BtnRunBack'; Click 'BtnSetup' } { $script:TabulaUi.PlanView.Visibility -eq 'Visible' }
    Add-Step 'apply' { Click 'BtnApply' } { $r = $script:TabulaUi.RunResults; $r -and $r.Count -ge 2 }
    Add-Step 'cancel' {
        $script:result.steps.cancelWhileRunning = [bool]$script:TabulaUi.Running
        Click 'BtnRunCancel'
    } $finished
    Add-Step 'apply-snap' { Save-Shot 'Run-cancelled'; $script:result.steps.apply = Get-RunSnapshot; $script:result.steps.applyButtons = Get-ButtonState 'BtnUndoLast' }
    Add-Step 'undo' { Click 'BtnRunUndo' } $finished
    Add-Step 'undo-snap' { $script:result.steps.undo = Get-RunSnapshot }
    Add-Step 'back-2' { Click 'BtnRunBack' } { $script:TabulaUi.HomeView.Visibility -eq 'Visible' -and (& $idle) }
    Add-Step 'undo-after' { $script:result.steps.undoAfter = Get-ButtonState 'BtnUndoLast' }
    Add-Step 'stage' {
        $u = $script:TabulaUi
        $u.NavTweaks.IsChecked = $true
        $script:result.steps.stagedBefore = [ordered]@{ exp = [bool]$u.TweakRowById['t-exp'].IsEnabled; one = [bool]$u.TweakRowById['t-one'].IsEnabled; button = (Get-ButtonState 'BtnStageApply') }
        $u.TweakRowById['t-one'].IsChecked = $true
        $script:result.steps.stagedBar = [ordered]@{ visible = ($u.StageBar.Visibility -eq 'Visible'); button = (Get-ButtonState 'BtnStageApply') }
        Click 'BtnStageApply'
    } $finished
    Add-Step 'stage-snap' { $script:result.steps.stage = Get-RunSnapshot } $idle
    Add-Step 'stage-after' {
        $u = $script:TabulaUi
        $row = $u.TweakRowById['t-one']
        $script:result.steps.stageAfter = [ordered]@{ baseline = [bool]$row.Baseline; enabled = [bool]$row.IsEnabled; reason = [string]$row.Reason; button = (Get-ButtonState 'BtnStageApply', 'BtnUndoLast') }
    }
    Add-Step 'install' {
        $u = $script:TabulaUi
        $u.NavApps.IsChecked = $true
        foreach ($r in $u.AppRows) { $r.IsChecked = ($r.Id -eq 'fx-a') }
        $script:result.steps.installButton = Get-ButtonState 'BtnInstall'
        Click 'BtnInstall'
    } $finished
    Add-Step 'install-snap' { $script:result.steps.install = Get-RunSnapshot } $idle
    Add-Step 'back-3' { Click 'BtnRunBack'; Click 'BtnSetup' } { $script:TabulaUi.PlanView.Visibility -eq 'Visible' }
    # Close the window in the middle of a real run: it must wait for the current item, not kill it.
    Add-Step 'close-run' { Click 'BtnApply' } { $r = $script:TabulaUi.RunRowById['app:fx-a']; $r -and $r.Status -eq 'Running' }
    Add-Step 'close-request' {
        $script:TabulaUi.Window.Close()
        $script:result.steps.visibleAfterClose = [bool]$script:TabulaUi.Window.IsVisible
        $script:result.closedByRun = $true
    } { $false }
}
elseif ($Mode -eq 'Shots') {
    # Each page takes two steps: switch and wait out the 150 ms page transition, then render.
    $script:steps.Add(@{ Name = 'home'; Do = { Click 'BtnRunBack'; Set-TabulaStatus 'Ready.'; $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 700 }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-Setup'; Do = { Save-Shot 'Setup' }; Until = { $true }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'plan'; Do = { Click 'BtnSetup'; $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 700 }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-Plan'; Do = { Save-Shot 'Plan' }; Until = { $true }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'apps'; Do = { $script:TabulaUi.NavApps.IsChecked = $true; $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 700 -and (& $idle) }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-Apps'; Do = { Save-Shot 'Apps' }; Until = { $true }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'tweaks'; Do = { $script:TabulaUi.NavTweaks.IsChecked = $true; $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 700 -and (& $idle) }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-Tweaks'; Do = { Save-Shot 'Tweaks' }; Until = { $true }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'tweaks-exp'; Do = { $script:TabulaUi.ExperimentalExpander.IsExpanded = $true; $script:TabulaUi.Window.UpdateLayout(); $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 500 }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-TweaksExp'; Do = { Save-Shot 'TweaksExp' }; Until = { $true }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'tools'; Do = { $script:TabulaUi.NavTools.IsChecked = $true; $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 700 }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-Tools'; Do = { Save-Shot 'Tools' }; Until = { $true }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'about'; Do = { $script:TabulaUi.NavAbout.IsChecked = $true; $script:mark = [DateTime]::UtcNow }; Until = { ([DateTime]::UtcNow - $script:mark).TotalMilliseconds -gt 700 }; Started = $false; T0 = $null })
    $script:steps.Add(@{ Name = 'shot-About'; Do = { Save-Shot 'About' }; Until = { $true }; Started = $false; T0 = $null })
    Add-Step 'end' { $script:TabulaUi.Window.Close() }
}
elseif ($Mode -eq 'NoWinget') {
    Add-Step 'rows' { $script:result.steps.appStatus = @($script:TabulaUi.AppRows | ForEach-Object { '{0}={1}' -f $_.Id, $_.Status }) }
    Add-Step 'back-1' { Click 'BtnRunBack'; Click 'BtnSetup' } { $script:TabulaUi.PlanView.Visibility -eq 'Visible' }
    Add-Step 'apply' { Click 'BtnApply' } $finished
    Add-Step 'apply-snap' { $script:result.steps.apply = Get-RunSnapshot; Save-Shot 'Run-problems' }
    Add-Step 'end' { $script:TabulaUi.Window.Close() }
}
elseif ($Mode -eq 'Unsupported') {
    Add-Step 'snap' {
        $u = $script:TabulaUi
        $script:result.steps.unsupported = [ordered]@{ machine = $u.MachineLine.Text; status = $u.StatusText.Text; buttons = (Get-ButtonState 'BtnSetup', 'BtnReview'); banner = ($u.ElevBanner.Visibility -eq 'Visible') }
        Save-Shot 'Unsupported'
    }
    Add-Step 'end' { $script:TabulaUi.Window.Close() }
}
else {
    # Keyboard order and layout at the smallest allowed window, on every page and on the Plan and Run views.
    Add-Step 'keys' {
        $u = $script:TabulaUi
        $o = [ordered]@{}
        foreach ($p in 'Setup', 'Apps', 'Tweaks', 'Tools', 'About') { $u["Nav$p"].IsChecked = $true; $u.Window.UpdateLayout(); $o[$p] = Get-TabOrder }
        $script:result.steps.tabOrder = $o
    }
    Add-Step 'small' {
        $u = $script:TabulaUi
        $u.Window.Width = $u.Window.MinWidth; $u.Window.Height = $u.Window.MinHeight; $u.Window.UpdateLayout()
        $o = [ordered]@{}
        foreach ($p in 'Setup', 'Apps', 'Tweaks', 'Tools', 'About') { $u["Nav$p"].IsChecked = $true; $u.Window.UpdateLayout(); $o[$p] = Get-Overflow; Save-Shot "Small-$p" }
        $u.NavSetup.IsChecked = $true; $u.Window.UpdateLayout()
        $o['Run'] = Get-Overflow; Save-Shot 'Small-Run'
        Click 'BtnRunBack'; Click 'BtnSetup'; $u.Window.UpdateLayout()
        $o['Plan'] = Get-Overflow; Save-Shot 'Small-Plan'
        $script:result.steps.overflow = $o
        $script:result.steps.minSize = "$($u.Window.MinWidth)x$($u.Window.MinHeight)"
    }
    Add-Step 'end' { $script:TabulaUi.Window.Close() }
}

$onReady = {
    param($w, $ui)
    $w.WindowStartupLocation = 'Manual'; $w.Left = -4000; $w.Top = 100; $w.ShowInTaskbar = $false
    $ui.AutoConfirm = $true   # no message box: the harness has nobody to click it
    $script:i = 0
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(120)
    $script:hTimer = $t
    $t.Add_Tick({
            if ($script:i -ge $script:steps.Count) { return }
            $s = $script:steps[$script:i]
            try {
                if (-not $s.Started) { $s.Started = $true; $s.T0 = [DateTime]::UtcNow; & $s.Do }
                if (& $s.Until) { $script:i++ }
                elseif (([DateTime]::UtcNow - $s.T0).TotalSeconds -gt $(if ($Mode -eq 'Real') { 180 } else { 30 })) { throw 'timed out' }
            }
            catch {
                $script:result.errors += ('{0}: {1}' -f $s.Name, $_.Exception.Message)
                $script:i = $script:steps.Count
                $script:TabulaUi.CloseWhenDone = $true
                $script:TabulaUi.Window.Close()
            }
        })
    $t.Start()
}
$cfgArgs = if ($Mode -in 'Real', 'Shots') { @{} } else { @{ ConfigRoot = $cfgDir } }
Show-TabulaWindow -Theme $Theme -OnReady $onReady -AutoCloseMs 120000 @cfgArgs
$script:hTimer.Stop()
$script:result.logFileText = [IO.File]::ReadAllText($script:logFile)
if ($Mode -eq 'Flow') { $script:result.steps.closeRun = Get-RunSnapshot }
Remove-TestRegistry
$script:result | ConvertTo-Json -Compress -Depth 8
