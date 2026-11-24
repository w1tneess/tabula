# Runs inside Windows Sandbox (administrator, winget bootstrapped). Opens the real Tabula window and clicks the real buttons
# with the real engine: no stubs, real HKLM, real winget installs. The sandbox is thrown away afterwards.
# Writes C:\Out\gui-run.json, gui-run.log and screenshots.
$ErrorActionPreference = 'Stop'
$repo = 'C:\TabulaRepo'
$script:TabulaBuild = @{ Version = 'sandbox'; Built = 'n/a'; Commit = 'n/a' }
foreach ($f in (Get-ChildItem "$repo\src\Core" -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
. "$repo\src\UI\UI.ps1"
Set-StrictMode -Version 2.0
$script:TabulaRoot = $repo
[void](Initialize-TabulaLog -Path 'C:\Out\gui-run.log' -Quiet)

$script:result = [ordered]@{ errors = @(); steps = [ordered]@{}; elevated = (Test-TabulaElevated) }
function Click($name) { $script:TabulaUi[$name].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
function Get-Reg($key, $name) { $v = [Microsoft.Win32.Registry]::GetValue($key, $name, $null); if ($null -eq $v) { '<<absent>>' } else { "$v" } }
function Get-Snap {
    $u = $script:TabulaUi
    $items = @(); if ($u.RunList.ItemsSource) { $items = @($u.RunList.ItemsSource) }   # empty before the first run
    [ordered]@{
        title = $u.RunTitle.Text; summary = $u.RunSummary.Text
        rows = @($items | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Id, $_.Status })
        reasons = @($items | Where-Object { $_.Reason } | ForEach-Object { '{0}: {1}' -f $_.Id, $_.Reason })
        undoVisible = ($u.BtnRunUndo.Visibility -eq 'Visible')
        reg = [ordered]@{
            EnableActivityFeed = (Get-Reg 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed')
            PublishUserActivities = (Get-Reg 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities')
            UploadUserActivities = (Get-Reg 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities')
            AllowTelemetry = (Get-Reg 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry')
        }
        installed = [ordered]@{
            '7zip' = (Test-Path 'C:\Program Files\7-Zip\7z.exe')
            notepadpp = (Test-Path 'C:\Program Files\Notepad++\notepad++.exe')
            vlc = (Test-Path 'C:\Program Files\VideoLAN\VLC\vlc.exe')
        }
        stateExists = [IO.File]::Exists((Get-TabulaStatePath))
    }
}
function Save-Shot([string]$Name) {
    $u = $script:TabulaUi; $c = $u.Window.Content; $u.Window.UpdateLayout()
    $w = [int]$c.ActualWidth; $h = [int]$c.ActualHeight
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen(); $dc.DrawRectangle($u.Window.Background, $null, (New-Object Windows.Rect 0, 0, $w, $h)); $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv); $rtb.Render($c)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create("C:\Out\gui-$Name.png")
    try { $enc.Save($fs) } finally { $fs.Close() }
}
function Set-Ticked([string[]]$KeepApps) {
    foreach ($r in $script:TabulaUi.PlanRows) { if ($r.Kind -eq 'app' -and $KeepApps -notcontains $r.Id) { $r.IsChecked = $false } }
}
$finished = { $u = $script:TabulaUi; (-not $u.Running) -and ($u.BtnRunBack.Visibility -eq 'Visible') -and [bool]$u.RunSummary.Text }
$idle = { $u = $script:TabulaUi; (-not $u.Running) -and (-not $u.CheckJob) -and (-not $u.DetectJob) -and (-not $u.PendingRun) }

$script:steps = New-Object System.Collections.Generic.List[hashtable]
function Add-Step([string]$Name, [scriptblock]$Do, [scriptblock]$Until = { $true }) { $script:steps.Add(@{ Name = $Name; Do = $Do; Until = $Until; Started = $false; T0 = $null }) }

Add-Step 'ready' { } { $u = $script:TabulaUi; [bool]$u.Profile -and (& $idle) }
Add-Step 'initial' {
    $u = $script:TabulaUi
    $script:result.steps.initial = [ordered]@{ admin = [bool]$u.Profile.IsAdmin; applyEnabled = $false; winget = [bool](Get-TabulaWingetPath); before = (Get-Snap) }
}
Add-Step 'plan-1' { Click 'BtnSetup' } { $script:TabulaUi.PlanView.Visibility -eq 'Visible' }
Add-Step 'tick-1' {
    Set-Ticked @('7zip')
    $u = $script:TabulaUi
    $script:result.steps.plan1 = [ordered]@{ ticked = @($u.PlanRows | Where-Object { $_.IsChecked } | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Id }); applyEnabled = [bool]$u.BtnApply.IsEnabled }
}
Add-Step 'apply-1' { Click 'BtnApply' } $finished
Add-Step 'apply-1-snap' { Save-Shot 'apply-1'; $script:result.steps.apply1 = Get-Snap }
Add-Step 'undo-1' { Click 'BtnRunUndo' } $finished
Add-Step 'undo-1-snap' { Save-Shot 'undo-1'; $script:result.steps.undo1 = Get-Snap }
Add-Step 'plan-2' { Click 'BtnRunBack'; Click 'BtnSetup' } { $script:TabulaUi.PlanView.Visibility -eq 'Visible' }
Add-Step 'apply-2' { Set-Ticked @('notepadpp', 'vlc'); Click 'BtnApply' } { $r = $script:TabulaUi.RunRowById['app:notepadpp']; $r -and $r.Status -eq 'Running' }
Add-Step 'cancel-2' { Click 'BtnRunCancel' } $finished
Add-Step 'cancel-2-snap' { Save-Shot 'cancel-2'; $script:result.steps.cancel2 = Get-Snap }
Add-Step 'undo-2' { Click 'BtnRunUndo' } $finished
Add-Step 'undo-2-snap' { $script:result.steps.undo2 = Get-Snap }
Add-Step 'end' { $script:TabulaUi.Window.Close() }

$onReady = {
    param($w, $ui)
    $ui.AutoConfirm = $true   # the script has nobody to click the confirmation
    $script:i = 0
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:hTimer = $t
    $t.Add_Tick({
            if ($script:i -ge $script:steps.Count) { return }
            $s = $script:steps[$script:i]
            try {
                if (-not $s.Started) { $s.Started = $true; $s.T0 = [DateTime]::UtcNow; & $s.Do }
                if (& $s.Until) { $script:i++ }
                elseif (([DateTime]::UtcNow - $s.T0).TotalSeconds -gt 900) { throw 'timed out' }
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
Show-TabulaWindow -Theme Dark -OnReady $onReady -AutoCloseMs 3000000
$script:hTimer.Stop()
$script:result.logFileText = [IO.File]::ReadAllText('C:\Out\gui-run.log')
$script:result | ConvertTo-Json -Compress -Depth 8 | Set-Content -Encoding UTF8 'C:\Out\gui-run.json'
'gui-run finished' | Add-Content -Encoding UTF8 'C:\Out\probe.txt'
