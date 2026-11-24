# Run in its own STA process by UI.Tests.ps1. Opens the real window off-screen, clicks the real buttons and prints one JSON line.
# Everything the engine changes lives under HKCU:\Software\TabulaTest. winget, the restore point and the elevation flag are
# stubbed here (functions defined before the window opens are copied into its job runspaces), so nothing real is installed.
param([ValidateSet('Flow', 'NotAdmin', 'Real')][string]$Mode = 'Flow', [ValidateSet('Dark', 'Light')][string]$Theme = 'Dark', [string]$ShotDir)
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
$admin = if ($Mode -eq 'Flow') { '$true' } else { '$false' }
if ($Mode -ne 'Real') {
Set-Item -Path Function:\Get-TabulaProfile -Value ([scriptblock]::Create("`$p = & { $origProfile }`n`$p.IsAdmin = $admin`n`$p"))
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
$finished = { $u = $script:TabulaUi; (-not $u.Running) -and ($u.BtnRunBack.Visibility -eq 'Visible') -and [bool]$u.RunSummary.Text }
$idle = { $u = $script:TabulaUi; (-not $u.Running) -and (-not $u.CheckJob) -and (-not $u.DetectJob) -and (-not $u.PendingRun) }

$script:steps = New-Object System.Collections.Generic.List[hashtable]
function Add-Step([string]$Name, [scriptblock]$Do, [scriptblock]$Until = { $true }) { $script:steps.Add(@{ Name = $Name; Do = $Do; Until = $Until; Started = $false; T0 = $null }) }

Add-Step 'ready' { } { $u = $script:TabulaUi; [bool]$u.Profile -and (& $idle) }
Add-Step 'initial' {
    $script:result.steps.initial = [ordered]@{ buttons = (Get-ButtonState 'BtnApply', 'BtnDry', 'BtnInstall', 'BtnStageApply', 'BtnUndoLast'); admin = [bool]$script:TabulaUi.Profile.IsAdmin }
}
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
else {
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
$cfgArgs = if ($Mode -eq 'Real') { @{} } else { @{ ConfigRoot = $cfgDir } }
Show-TabulaWindow -Theme $Theme -OnReady $onReady -AutoCloseMs 120000 @cfgArgs
$script:hTimer.Stop()
$script:result.logFileText = [IO.File]::ReadAllText($script:logFile)
if ($Mode -eq 'Flow') { $script:result.steps.closeRun = Get-RunSnapshot }
Remove-TestRegistry
$script:result | ConvertTo-Json -Compress -Depth 8
