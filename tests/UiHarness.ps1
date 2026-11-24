# Run in its own STA process by UI.Tests.ps1. Opens the real window off-screen, checks it, prints one JSON line.
param([string]$Theme = 'Dark')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
foreach ($f in (Get-ChildItem "$repo\src\Core" -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
. "$repo\src\UI\UI.ps1"
Set-StrictMode -Version 2.0
$script:TabulaBuild = @{ Version = 'test'; Built = 'n/a'; Commit = 'n/a' }
$script:TabulaRoot = $repo
[void](Initialize-TabulaLog -Path (Join-Path $env:TEMP 'tabula-ui-harness.log') -Quiet)

$script:result = [ordered]@{ pages = @{}; checked = 0; defaultLooking = @(); ticks = 0; maxGapMs = 0; elapsedMs = 0; demoDone = $false; light = $false }

function Get-VisualDescendant($root) {
    $q = New-Object System.Collections.Queue; $q.Enqueue($root)
    while ($q.Count -gt 0) {
        $e = $q.Dequeue(); $e
        if ($e -is [Windows.Media.Visual] -or $e -is [Windows.Media.Media3D.Visual3D]) {
            for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($e); $i++) { $q.Enqueue([Windows.Media.VisualTreeHelper]::GetChild($e, $i)) }
        }
    }
}

$script:phase = 'pages'
$onReady = {
    param($w, $ui)
    $w.WindowStartupLocation = 'Manual'; $w.Left = -4000; $w.Top = 100; $w.ShowInTaskbar = $false
    $script:result.light = [bool]$ui.Light
    $script:pageQueue = New-Object System.Collections.Queue
    foreach ($n in 'Setup', 'Apps', 'Tweaks', 'Tools', 'About') { $script:pageQueue.Enqueue($n) }
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:hTimer = $t
    $t.Add_Tick({
            $u = $script:TabulaUi
            switch ($script:phase) {
                'pages' {
                    if ($script:pageQueue.Count -eq 0) { $script:phase = 'demo'; return }
                    $n = $script:pageQueue.Dequeue()
                    Set-TabulaPage $n
                    $u.Window.UpdateLayout()
                    $page = $u.Pages[$n]
                    $script:result.pages[$n] = [pscustomobject]@{ w = [int]$page.ActualWidth; h = [int]$page.ActualHeight }
                    if ($n -eq 'Tweaks') { $u.ExperimentalExpander.IsExpanded = $true; $u.Window.UpdateLayout() }
                    foreach ($e in (Get-VisualDescendant $u.Window)) {
                        if ($e -is [Windows.Controls.Primitives.ButtonBase] -or $e -is [Windows.Controls.TextBox] -or $e -is [Windows.Controls.ProgressBar] -or $e -is [Windows.Controls.Primitives.ScrollBar] -or $e -is [Windows.Controls.Expander] -or $e -is [Windows.Controls.ToolTip]) {
                            $script:result.checked++
                            $src = [Windows.DependencyPropertyHelper]::GetValueSource($e, [Windows.Controls.Control]::TemplateProperty).BaseValueSource
                            if ($src -eq 'DefaultStyle' -or $src -eq 'Default') { $script:result.defaultLooking += ('{0} on {1}' -f $e.GetType().Name, $n) }
                        }
                    }
                }
                'demo' {
                    $script:phase = 'running'
                    $script:swDemo = [Diagnostics.Stopwatch]::StartNew()
                    $script:lastTick = $script:swDemo.ElapsedMilliseconds
                    [void](Start-TabulaDemoTask -OnDone { param($r, $err) $script:result.demoDone = (-not $err); $script:result.elapsedMs = $script:swDemo.ElapsedMilliseconds; $script:phase = 'done' })
                    # a fast ticker on the UI thread: if a job blocked the thread, the gaps would show here
                    $script:hTimer.Interval = [TimeSpan]::FromMilliseconds(40)
                }
                'running' {
                    $now = $script:swDemo.ElapsedMilliseconds
                    $gap = $now - $script:lastTick; $script:lastTick = $now
                    $script:result.ticks++
                    if ($gap -gt $script:result.maxGapMs) { $script:result.maxGapMs = $gap }
                }
                'done' { $script:hTimer.Stop(); $u.Window.Close() }
            }
        })
    $t.Start()
}
Show-TabulaWindow -Theme $Theme -OnReady $onReady -AutoCloseMs 90000   # watchdog: a stuck run must not leave a window open
$script:result | ConvertTo-Json -Compress -Depth 4
