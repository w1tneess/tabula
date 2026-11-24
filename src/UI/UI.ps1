# WPF window: theme, pages, background jobs. Needs an STA thread; Start-TabulaGui moves itself onto one if the host is MTA.
# All UI state lives in $script:TabulaUi because event handlers do not see the locals of the function that attached them.

$script:TabulaUi = $null
$script:TabulaJobs = New-Object System.Collections.ArrayList

function Initialize-TabulaUiTypes {
    [CmdletBinding()]
    param()
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not ('TabulaRow' -as [type])) {
        # Row model for the list pages. PowerShell objects cannot raise the change notifications WPF bindings need.
        Add-Type -TypeDefinition @'
using System.ComponentModel;
public class TabulaRow : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private void Raise(string name) { PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(name)); }
    private string status = ""; private string statusKind = "dim"; private string reason = "";
    private bool isChecked; private bool isEnabled = true;
    public string Id { get; set; }
    public string Name { get; set; }
    public string Description { get; set; }
    public string Sub { get; set; }
    public string Url { get; set; }
    public string Risk { get; set; }
    public string Category { get; set; }
    public string Kind { get; set; }
    public string Hint { get; set; }
    public bool Baseline { get; set; }
    public string Status { get { return status; } set { status = value; Raise("Status"); } }
    public string StatusKind { get { return statusKind; } set { statusKind = value; Raise("StatusKind"); } }
    public string Reason { get { return reason; } set { reason = value; Raise("Reason"); } }
    public bool IsChecked { get { return isChecked; } set { isChecked = value; Raise("IsChecked"); } }
    public bool IsEnabled { get { return isEnabled; } set { isEnabled = value; Raise("IsEnabled"); } }
}
'@
    }
}

# ---- XAML and theme ---------------------------------------------------------------------------------

function Get-TabulaXaml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $emb = Get-Variable -Name TabulaXaml -Scope Script -ErrorAction SilentlyContinue
    if ($emb -and $emb.Value.ContainsKey($Name)) { return $emb.Value[$Name] }
    $f = Get-ChildItem (Join-Path $script:TabulaRoot 'src\UI') -Filter $Name -Recurse | Select-Object -First 1
    if (-not $f) { throw "XAML '$Name' not found" }
    [IO.File]::ReadAllText($f.FullName)
}

function Import-TabulaXaml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    [Windows.Markup.XamlReader]::Parse((Get-TabulaXaml -Name $Name))
}

function Test-TabulaLightTheme {
    [CmdletBinding()]
    param()
    try { [Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0) -eq 1 }
    catch { $false }
}

function Set-TabulaTheme {
    # The palette is its own dictionary, so switching theme replaces one dictionary and every DynamicResource follows.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Window, [switch]$Light)
    $palette = Import-TabulaXaml -Name $(if ($Light) { 'Theme.Light.xaml' } else { 'Theme.Dark.xaml' })
    $md = $Window.Resources.MergedDictionaries
    if ($md.Count -eq 0) { [void]$md.Add($palette); [void]$md.Add((Import-TabulaXaml -Name 'Theme.xaml')) }
    else { $md[0] = $palette }
}

# ---- background jobs --------------------------------------------------------------------------------

function New-TabulaSessionState {
    # A fresh runspace sees none of this script. Copy the Tabula functions and read-only data into it.
    [CmdletBinding()]
    param([switch]$IncludeLog)
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in (Get-ChildItem Function:\ | Where-Object { $_.Name -like '*-Tabula*' })) {
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($f.Name, $f.Definition)))
    }
    $skip = 'TabulaCancel', 'TabulaUi', 'TabulaJobs'
    if (-not $IncludeLog) { $skip += 'TabulaLog' }
    foreach ($v in @(Get-Variable -Scope Script -Name 'Tabula*' -ErrorAction SilentlyContinue)) {
        if ($skip -contains $v.Name) { continue }
        $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry($v.Name, $v.Value, '')))
    }
    $iss
}

function Start-TabulaUiJob {
    # Runs $Script in a background runspace. The script gets ($queue, $ctl, ...$Arguments): it enqueues messages for
    # OnMessage and may watch $ctl.Cancel. Both callbacks run on the UI thread from a timer, never on the job thread.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Script, [object[]]$Arguments = @(),
        [scriptblock]$OnMessage, [scriptblock]$OnDone
    )
    $q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $ctl = [hashtable]::Synchronized(@{ Cancel = $false })
    $rs = [runspacefactory]::CreateRunspace((New-TabulaSessionState))
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $wrapper = @'
param($q, $ctl, $body, $jobArgs)
$script:TabulaLog = @{ Path = $null; Lines = (New-Object System.Collections.Generic.List[string]); Debug = $false; Quiet = $true }
& ([scriptblock]::Create($body)) $q $ctl @jobArgs
'@
    [void]$ps.AddScript($wrapper).AddArgument($q).AddArgument($ctl).AddArgument($Script.ToString()).AddArgument($Arguments)
    $job = @{ PS = $ps; Runspace = $rs; Handle = $ps.BeginInvoke(); Queue = $q; Ctl = $ctl; OnMessage = $OnMessage; OnDone = $OnDone }
    [void]$script:TabulaJobs.Add($job)
    $job
}

function Update-TabulaUiJobs {
    [CmdletBinding()]
    param()
    foreach ($job in @($script:TabulaJobs)) {
        $msg = $null
        $drain = {
            while ($job.Queue.TryDequeue([ref]$msg)) {
                if ($job.OnMessage) {
                    try { & $job.OnMessage $msg }
                    catch { Write-TabulaLog ('job message handler failed: ' + $_.Exception.Message) -Level ERROR }
                }
            }
        }
        & $drain
        if (-not $job.Handle.IsCompleted) { continue }
        & $drain   # anything enqueued between the first drain and completion
        $result = $null; $err = $null
        try { $result = $job.PS.EndInvoke($job.Handle) } catch { $err = $_.Exception.Message }
        if (-not $err -and $job.PS.Streams.Error.Count -gt 0) { $err = $job.PS.Streams.Error[0].ToString() }
        $job.PS.Dispose(); $job.Runspace.Dispose()
        $script:TabulaJobs.Remove($job)
        if ($job.OnDone) {
            try { & $job.OnDone $result $err }
            catch { Write-TabulaLog ('job completion handler failed: ' + $_.Exception.Message) -Level ERROR }
        }
    }
}

function Stop-TabulaUiJobs {
    [CmdletBinding()]
    param()
    foreach ($job in @($script:TabulaJobs)) {
        $job.Ctl['Cancel'] = $true
        try { $job.PS.Stop() } catch { Write-TabulaLog ('could not stop a job: ' + $_.Exception.Message) -Level WARN }
        try { $job.PS.Dispose(); $job.Runspace.Dispose() } catch { Write-TabulaLog ('could not dispose a job: ' + $_.Exception.Message) -Level WARN }
    }
    $script:TabulaJobs.Clear()
}

# ---- small helpers ----------------------------------------------------------------------------------

function Set-TabulaStatus {
    # Progress -1 hides the bar. Called on the UI thread only.
    [CmdletBinding()]
    param([string]$Text, [double]$Progress = -1)
    $ui = $script:TabulaUi
    $ui.StatusText.Text = $Text
    if ($Progress -lt 0) { $ui.StatusProgress.Visibility = 'Hidden' }
    else { $ui.StatusProgress.Visibility = 'Visible'; $ui.StatusProgress.Value = $Progress }
}

function New-TabulaRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Property)
    $r = New-Object TabulaRow
    foreach ($k in $Property.Keys) { $r.$k = $Property[$k] }
    $r
}

function ConvertTo-TabulaRestartHint {
    param([string]$Restart)
    switch ($Restart) { 'explorer' { 'Restarts Explorer' } 'signout' { 'Needs sign-out' } 'reboot' { 'Needs restart' } default { '' } }
}

function Set-TabulaPage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $ui = $script:TabulaUi
    $page = $ui.Pages[$Name]
    $ui.PageHost.Content = $page
    $ui.Current = $Name
    # 150 ms fade with an 8 px slide, skipped when Windows has animations turned off.
    if ([Windows.SystemParameters]::ClientAreaAnimation) {
        $tt = New-Object Windows.Media.TranslateTransform(0, 8)
        $page.RenderTransform = $tt
        $ease = New-Object Windows.Media.Animation.CubicEase
        $ease.EasingMode = 'EaseOut'
        $fade = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(150))
        $slide = New-Object Windows.Media.Animation.DoubleAnimation(8, 0, [TimeSpan]::FromMilliseconds(150))
        $fade.EasingFunction = $ease; $slide.EasingFunction = $ease
        $page.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
        $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $slide)
    }
}

# ---- Setup page -------------------------------------------------------------------------------------

function Update-TabulaSetupSummary {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    if (-not $ui.Profile) { $ui.SummaryLine.Text = ''; return }
    $plan = Resolve-TabulaPlan -Config $ui.Config -Profile $ui.Profile -Preset $ui.Preset
    $dot = [string][char]0x00B7
    $tw = @($plan | Where-Object { $_.Kind -eq 'tweak' -and -not $_.Hold }).Count
    $ap = @($plan | Where-Object { $_.Kind -eq 'app' -and -not $_.Hold }).Count
    $held = @($plan | Where-Object { $_.Hold }).Count
    $text = "$tw tweaks $dot $ap apps $dot restore point on"
    if ($held -gt 0) { $text += " $dot $held held back" }
    $ui.SummaryLine.Text = $text
    $ui.Plan = $plan
}

function Show-TabulaPlan {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    if (-not $ui.Profile) { Set-TabulaStatus 'Still detecting your machine.'; return }
    Update-TabulaSetupSummary
    $rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($item in $ui.Plan) {
        $reason = if ($item.Hold) { [string]$item.Hold } elseif ($item.Kind -eq 'tweak') { [string]$item.Item['description'] } else { [string]$item.Item['description'] }
        [void]$rows.Add((New-TabulaRow @{
                    Id = $item.Id; Name = $item.Name; Kind = $item.Kind; Reason = $reason; Risk = $item.Risk.ToUpper()
                    IsChecked = (-not $item.Hold); IsEnabled = (-not $item.Hold)
                }))
    }
    $ui.PlanList.ItemsSource = $rows
    $held = @($ui.Plan | Where-Object { $_.Hold }).Count
    $ui.PlanSummary.Text = ('{0} items. {1} held back. Nothing applied yet.' -f @($ui.Plan).Count, $held)
    $ui.HomeView.Visibility = 'Collapsed'
    $ui.PlanView.Visibility = 'Visible'
    $ui.BtnCancelPlan.Focus() | Out-Null
}

function Initialize-TabulaSetupPage {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $p = $ui.Pages['Setup']
    foreach ($n in 'HomeView', 'PlanView', 'MachineLine', 'SummaryLine', 'PresetPanel', 'PlanList', 'PlanSummary', 'BtnSetup', 'BtnReview', 'BtnCancelPlan', 'BtnApply', 'ElevBanner', 'ElevCommand', 'BtnCopyCommand') {
        $ui[$n] = $p.FindName($n)
    }
    $ui.Preset = 'Standard'
    foreach ($preset in $ui.Config['presets']) {
        $chip = New-Object Windows.Controls.RadioButton
        $chip.SetResourceReference([Windows.Controls.Control]::StyleProperty, 'Chip')
        $chip.Content = [string]$preset['name']
        $chip.Tag = [string]$preset['id']
        $chip.GroupName = 'Preset'
        $chip.IsChecked = ($preset['id'] -eq $ui.Preset)
        [Windows.Automation.AutomationProperties]::SetName($chip, 'Preset ' + [string]$preset['name'])
        $chip.Add_Checked({ param($s, $e) $script:TabulaUi.Preset = [string]$s.Tag; Update-TabulaSetupSummary })
        [void]$ui.PresetPanel.Children.Add($chip)
    }
    $ui.BtnSetup.Add_Click({ Show-TabulaPlan })
    $ui.BtnReview.Add_Click({ Show-TabulaPlan })
    $ui.BtnCancelPlan.Add_Click({
            $u = $script:TabulaUi
            $u.PlanView.Visibility = 'Collapsed'; $u.HomeView.Visibility = 'Visible'
            $u.BtnSetup.Focus() | Out-Null
        })
    $ui.ElevCommand.Text = 'Start-Process powershell -Verb RunAs'
    $ui.BtnCopyCommand.Add_Click({ [Windows.Clipboard]::SetText($script:TabulaUi.ElevCommand.Text); Set-TabulaStatus 'Command copied.' })
}

# ---- Apps page --------------------------------------------------------------------------------------

function Update-TabulaAppsSummary {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $sel = @($ui.AppRows | Where-Object { $_.IsChecked }).Count
    $ui.AppsSummary.Text = ('{0} apps. {1} selected.' -f $ui.AppRows.Count, $sel)
}

function Start-TabulaInstalledCheck {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $targets = @($ui.AppRows | Where-Object { $_.Kind -eq 'winget' -and $_.IsEnabled } | ForEach-Object { $_.Id })
    foreach ($r in $ui.AppRows) { if ($r.Kind -eq 'winget' -and $r.IsEnabled) { $r.Status = 'Checking'; $r.StatusKind = 'dim' } }
    if ($targets.Count -eq 0) { return }
    $list = @($targets | ForEach-Object { $id = $_; $app = $ui.AppById[$id]; @{ id = $id; wingetId = [string]$app['wingetId'] } })
    Set-TabulaStatus 'Checking installed apps.' 0
    [void](Start-TabulaUiJob -Arguments @(, $list) -Script {
            param($q, $ctl, $apps)
            if (-not (Get-TabulaWingetPath)) { $q.Enqueue(@{ Kind = 'unavailable' }); return }
            $i = 0
            foreach ($a in $apps) {
                if ($ctl.Cancel) { return }
                $i++
                $found = $false
                try { $found = [bool](Test-TabulaAppInstalled -WingetId $a.wingetId) } catch { $found = $null }
                $q.Enqueue(@{ Kind = 'app'; Id = $a.id; Installed = $found; Done = $i; Total = @($apps).Count })
            }
        } -OnMessage {
            param($m)
            $u = $script:TabulaUi
            if ($m.Kind -eq 'unavailable') {
                foreach ($r in $u.AppRows) { if ($r.Status -eq 'Checking') { $r.Status = 'No winget'; $r.StatusKind = 'warn' } }
                return
            }
            $row = $u.AppRowById[$m.Id]
            if ($null -eq $m.Installed) { $row.Status = 'Unknown'; $row.StatusKind = 'warn' }
            elseif ($m.Installed) { $row.Status = 'Installed'; $row.StatusKind = 'ok' }
            else { $row.Status = 'Not installed'; $row.StatusKind = 'dim' }
            Set-TabulaStatus ('Checking installed apps ({0} of {1}).' -f $m.Done, $m.Total) (100 * $m.Done / $m.Total)
        } -OnDone {
            param($r, $err)
            if ($err) { Write-TabulaLog "installed check failed: $err" -Level ERROR; Set-TabulaStatus 'Could not check installed apps.' } else { Set-TabulaStatus 'Ready.' }
        })
}

function Initialize-TabulaAppsPage {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $p = $ui.Pages['Apps']
    foreach ($n in 'AppsSummary', 'SearchBox', 'CategoryChips', 'AppList', 'AppsEmpty', 'BtnPreset', 'BtnExport', 'BtnRefresh') { $ui[$n] = $p.FindName($n) }
    $ui.AppRows = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $ui.AppRowById = @{}
    $ui.AppById = @{}
    $ui.Category = 'All'
    $ui.Search = ''
    $cats = New-Object System.Collections.Generic.List[string]
    foreach ($a in $ui.Config['apps']) {
        $ui.AppById[[string]$a['id']] = $a
        $isWinget = ($a['source'] -eq 'winget')
        $row = New-TabulaRow @{
            Id = [string]$a['id']; Name = [string]$a['name']; Description = [string]$a['description']; Sub = [string]$a['publisher']
            Url = [string]$a['officialUrl']; Category = [string]$a['category']; Kind = $(if ($isWinget) { 'winget' } else { 'manual' })
            IsChecked = [bool]$a['defaultSelected']; Status = $(if ($isWinget) { 'Checking' } else { 'Manual' })
        }
        $row.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'IsChecked') { Update-TabulaAppsSummary } })
        [void]$ui.AppRows.Add($row)
        $ui.AppRowById[$row.Id] = $row
        if (-not $cats.Contains($row.Category)) { $cats.Add($row.Category) }
    }
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($ui.AppRows)
    $view.Filter = [System.Predicate[object]] {
        param($o)
        $u = $script:TabulaUi
        if ($u.Category -ne 'All' -and $o.Category -ne $u.Category) { return $false }
        if ($u.Search -and ($o.Name + ' ' + $o.Description + ' ' + $o.Sub) -notlike ('*' + $u.Search + '*')) { return $false }
        $true
    }
    $ui.AppView = $view
    $ui.AppList.ItemsSource = $view

    foreach ($c in (@('All') + @($cats | Sort-Object))) {
        $chip = New-Object Windows.Controls.RadioButton
        $chip.SetResourceReference([Windows.Controls.Control]::StyleProperty, 'Chip')
        $chip.Content = $c; $chip.Tag = $c; $chip.GroupName = 'AppCategory'; $chip.IsChecked = ($c -eq 'All')
        [Windows.Automation.AutomationProperties]::SetName($chip, 'Category ' + $c)
        $chip.Add_Checked({
                param($s, $e)
                $u = $script:TabulaUi
                $u.Category = [string]$s.Tag
                $u.AppView.Refresh()
                $u.AppsEmpty.Visibility = $(if ($u.AppView.IsEmpty) { 'Visible' } else { 'Collapsed' })
            })
        [void]$ui.CategoryChips.Children.Add($chip)
    }
    $ui.SearchBox.Add_TextChanged({
            $u = $script:TabulaUi
            $u.Search = $u.SearchBox.Text.Trim()
            $u.AppView.Refresh()
            $u.AppsEmpty.Visibility = $(if ($u.AppView.IsEmpty) { 'Visible' } else { 'Collapsed' })
        })
    # One handler for every row's "Site" button.
    $ui.AppList.AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler] {
            param($s, $e)
            $b = $e.OriginalSource
            if ($b -is [Windows.Controls.Button] -and ([string]$b.Tag) -match '^https://') { Start-Process ([string]$b.Tag) }
        })
    $ui.BtnPreset.Add_Click({
            $u = $script:TabulaUi
            if (-not $u.Profile) { Set-TabulaStatus 'Still detecting your machine.'; return }
            $plan = Resolve-TabulaPlan -Config $u.Config -Profile $u.Profile -Preset $u.Preset -Scope Apps
            $ids = @($plan | Where-Object { -not $_.Hold } | ForEach-Object { $_.Id })
            foreach ($r in $u.AppRows) { if ($r.IsEnabled) { $r.IsChecked = ($ids -contains $r.Id) } }
            Set-TabulaStatus ('Ticked the apps in the {0} preset.' -f $u.Preset)
        })
    $ui.BtnRefresh.Add_Click({ Start-TabulaInstalledCheck })
    $ui.BtnExport.Add_Click({
            $u = $script:TabulaUi
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.FileName = 'apps.export.json'; $dlg.Filter = 'JSON (*.json)|*.json'; $dlg.Title = 'Export installed apps'
            if (-not $dlg.ShowDialog()) { return }
            Set-TabulaStatus 'Exporting installed apps.' 0
            [void](Start-TabulaUiJob -Arguments @($dlg.FileName, @($u.Config['apps'])) -Script {
                    param($q, $ctl, $path, $existing)
                    Export-TabulaApps -OutputPath $path -ExistingApps $existing
                } -OnDone {
                    param($r, $err)
                    if ($err) { Write-TabulaLog "export failed: $err" -Level ERROR; Set-TabulaStatus ('Export failed: ' + $err) }
                    else { $x = $r | Select-Object -Last 1; Set-TabulaStatus ('Exported {0} apps ({1} new) to {2}.' -f $x.Total, $x.New, $x.Path) }
                })
        })
    Update-TabulaAppsSummary
}

# ---- Tweaks page ------------------------------------------------------------------------------------

function Update-TabulaStageBar {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $n = @($ui.TweakRows | Where-Object { $_.IsEnabled -and $_.IsChecked -ne $_.Baseline }).Count
    if ($n -gt 0) { $ui.StageText.Text = ('{0} change(s) staged.' -f $n); $ui.StageBar.Visibility = 'Visible' }
    else { $ui.StageBar.Visibility = 'Collapsed' }
}

function Initialize-TabulaTweaksPage {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $p = $ui.Pages['Tweaks']
    foreach ($n in 'TweaksSummary', 'TweakGroups', 'TweaksEmpty', 'ExperimentalExpander', 'ExperimentalGroups', 'StageBar', 'StageText', 'BtnStageDiscard') { $ui[$n] = $p.FindName($n) }
    $ui.TweakRows = New-Object System.Collections.Generic.List[object]
    $ui.TweakRowById = @{}
    $template = $p.Resources['TweakRow']

    $byCat = [ordered]@{ true = @{}; false = @{} }
    foreach ($t in $ui.Config['tweaks']) {
        $verified = [bool]$t['verified']
        $row = New-TabulaRow @{
            Id = [string]$t['id']; Name = [string]$t['name']; Description = [string]$t['description']; Category = [string]$t['category']
            Risk = ([string]$t['risk']).ToUpper(); Hint = (ConvertTo-TabulaRestartHint ([string]$t['requiresRestart']))
            Reason = $(if ($verified) { '' } else { 'Unverified. Not tested on Windows yet.' }); IsEnabled = $false
        }
        $row.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'IsChecked') { Update-TabulaStageBar } })
        $ui.TweakRows.Add($row)
        $ui.TweakRowById[$row.Id] = $row
        $key = $verified.ToString().ToLower()
        if (-not $byCat[$key].ContainsKey($row.Category)) { $byCat[$key][$row.Category] = New-Object System.Collections.ObjectModel.ObservableCollection[object] }
        [void]$byCat[$key][$row.Category].Add($row)
    }
    $mk = {
        param($rows)
        $ic = New-Object Windows.Controls.ItemsControl
        $ic.ItemTemplate = $template; $ic.ItemsSource = $rows; $ic.Focusable = $false
        $ic
    }
    foreach ($cat in @($byCat['true'].Keys | Sort-Object)) {
        $exp = New-Object Windows.Controls.Expander
        $exp.Header = $cat.ToUpper(); $exp.IsExpanded = $true
        $exp.Content = (& $mk $byCat['true'][$cat])
        [Windows.Automation.AutomationProperties]::SetName($exp, $cat)
        [void]$ui.TweakGroups.Children.Add($exp)
    }
    foreach ($cat in @($byCat['false'].Keys | Sort-Object)) {
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = $cat.ToUpper(); $h.SetResourceReference([Windows.Controls.TextBlock]::StyleProperty, 'Section'); $h.Margin = '2,10,0,8'
        [void]$ui.ExperimentalGroups.Children.Add($h)
        [void]$ui.ExperimentalGroups.Children.Add((& $mk $byCat['false'][$cat]))
    }
    $verifiedCount = @($ui.Config['tweaks'] | Where-Object { $_['verified'] }).Count
    $ui.TweaksSummary.Text = ('{0} tweaks, {1} verified. Switches show the current state of this PC.' -f $ui.TweakRows.Count, $verifiedCount)
    if ($verifiedCount -eq 0) { $ui.TweaksEmpty.Visibility = 'Visible' }
    $ui.BtnStageDiscard.Add_Click({
            foreach ($r in $script:TabulaUi.TweakRows) { $r.IsChecked = $r.Baseline }
            Update-TabulaStageBar
        })
}

function Start-TabulaTweakDetect {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $items = @($ui.Config['tweaks'] | ForEach-Object { $_ })
    [void](Start-TabulaUiJob -Arguments @($items, $ui.Profile) -Script {
            param($q, $ctl, $tweaks, $prof)
            foreach ($t in $tweaks) {
                if ($ctl.Cancel) { return }
                $s = Get-TabulaTweakState -Tweak $t -Profile $prof
                $q.Enqueue(@{ Id = [string]$t['id']; State = $s.State; Reason = $s.Reason })
            }
        } -OnMessage {
            param($m)
            $row = $script:TabulaUi.TweakRowById[$m.Id]
            switch ($m.State) {
                'Set' { $row.Baseline = $true; $row.IsChecked = $true; $row.IsEnabled = $true }
                'Unset' { $row.Baseline = $false; $row.IsChecked = $false; $row.IsEnabled = $true }
                default { $row.IsEnabled = $false; $row.Reason = [string]$m.Reason }
            }
        } -OnDone {
            param($r, $err)
            if ($err) { Write-TabulaLog "tweak detection failed: $err" -Level ERROR }
        })
}

# ---- Tools and About pages --------------------------------------------------------------------------

function Start-TabulaDemoTask {
    # A fake three second task, used to check that the window stays responsive while a job runs.
    [CmdletBinding()]
    param([scriptblock]$OnDone)
    Set-TabulaStatus 'Running the responsiveness check.' 0
    $script:TabulaDemoDone = $OnDone
    Start-TabulaUiJob -Script {
        param($q, $ctl)
        for ($i = 1; $i -le 30; $i++) {
            if ($ctl.Cancel) { return }
            Start-Sleep -Milliseconds 100
            $q.Enqueue($i)
        }
        'finished'
    } -OnMessage {
        param($i)
        Set-TabulaStatus 'Running the responsiveness check.' ($i / 30 * 100)
    } -OnDone {
        param($r, $err)
        Set-TabulaStatus $(if ($err) { 'The check failed.' } else { 'Responsiveness check finished.' })
        if ($script:TabulaDemoDone) { & $script:TabulaDemoDone $r $err }
    }
}

function Initialize-TabulaToolsPage {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $p = $ui.Pages['Tools']
    foreach ($n in 'BtnOpenRestore', 'BtnOpenStartup', 'BtnOpenFeatures', 'BtnOpenUninstall', 'ToolLog', 'DemoCard', 'BtnToolDemo') { $ui[$n] = $p.FindName($n) }
    $ui.BtnOpenRestore.Add_Click({ Start-Process (Join-Path $env:WINDIR 'System32\SystemPropertiesProtection.exe') })
    $ui.BtnOpenStartup.Add_Click({ Start-Process 'ms-settings:startupapps' })
    $ui.BtnOpenFeatures.Add_Click({ Start-Process 'ms-settings:optionalfeatures' })
    $ui.BtnOpenUninstall.Add_Click({ Start-Process (Join-Path $env:WINDIR 'System32\control.exe') -ArgumentList 'appwiz.cpl' })
    if ($env:TABULA_UI_DEMO -eq '1') { $ui.DemoCard.Visibility = 'Visible' }
    $ui.BtnToolDemo.Add_Click({ [void](Start-TabulaDemoTask) })
}

function Initialize-TabulaAboutPage {
    [CmdletBinding()]
    param()
    $ui = $script:TabulaUi
    $p = $ui.Pages['About']
    $b = $script:TabulaBuild
    $p.FindName('AboutVersion').Text = [string]$b.Version
    $p.FindName('AboutBuild').Text = ('built {0}, commit {1}' -f $b.Built, $b.Commit)
    $logDir = Join-Path $env:LOCALAPPDATA 'Tabula\logs'
    $p.FindName('AboutLogs').Text = $logDir
    $p.FindName('BtnOpenLogs').Add_Click({
            $d = Join-Path $env:LOCALAPPDATA 'Tabula\logs'
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
            Start-Process (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"{0}"' -f $d)
        })
}

# ---- window -----------------------------------------------------------------------------------------

function Show-TabulaWindow {
    # OnReady runs once after the first render with the window and the UI state; it exists for tests.
    [CmdletBinding()]
    param([ValidateSet('Auto', 'Dark', 'Light')][string]$Theme = 'Auto', [scriptblock]$OnReady, [int]$AutoCloseMs = 0)
    Initialize-TabulaUiTypes
    # A fresh STA runspace gets the functions but not this file's top-level state.
    if ($null -eq $script:TabulaJobs) { $script:TabulaJobs = New-Object System.Collections.ArrayList }
    $cfg = Get-TabulaConfig
    $problems = @(Test-TabulaConfig -Config $cfg)
    if ($problems.Count -gt 0) { throw ('config is invalid: ' + ($problems -join '; ')) }

    $win = Import-TabulaXaml -Name 'Window.xaml'
    $light = switch ($Theme) { 'Light' { $true } 'Dark' { $false } default { Test-TabulaLightTheme } }
    Set-TabulaTheme -Window $win -Light:$light

    $ui = @{ Window = $win; Config = $cfg; Profile = $null; Plan = @(); Pages = @{}; Light = $light; Current = 'Setup'; OnReady = $OnReady; Started = $false }
    $script:TabulaUi = $ui
    foreach ($n in 'PageHost', 'MachineText', 'StatusText', 'StatusProgress', 'NavSetup', 'NavApps', 'NavTweaks', 'NavTools', 'NavAbout') { $ui[$n] = $win.FindName($n) }
    foreach ($n in 'Setup', 'Apps', 'Tweaks', 'Tools', 'About') { $ui.Pages[$n] = Import-TabulaXaml -Name "$n.xaml" }

    Initialize-TabulaSetupPage
    Initialize-TabulaAppsPage
    Initialize-TabulaTweaksPage
    Initialize-TabulaToolsPage
    Initialize-TabulaAboutPage

    foreach ($nav in $ui.NavSetup, $ui.NavApps, $ui.NavTweaks, $ui.NavTools, $ui.NavAbout) {
        $nav.Add_Checked({ param($s, $e) Set-TabulaPage ([string]$s.Content) })
    }
    Set-TabulaPage 'Setup'

    # Jobs report through a queue; this timer is the only thing that touches the UI from them.
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(60)
    $timer.Add_Tick({ Update-TabulaUiJobs })
    $timer.Start()
    $ui.Timer = $timer

    $win.Add_PreviewKeyDown({
            param($s, $e)
            $u = $script:TabulaUi
            if ($e.Key -eq 'F' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -and $u.Current -eq 'Apps') {
                $u.SearchBox.Focus() | Out-Null; $u.SearchBox.SelectAll(); $e.Handled = $true
            }
        })
    $win.Add_Closed({ $script:TabulaUi.Timer.Stop(); Stop-TabulaUiJobs })

    $win.Add_ContentRendered({
            $u = $script:TabulaUi
            if ($u.Started) { return }
            $u.Started = $true
            Set-TabulaStatus 'Detecting your machine.'
            # Detection runs off the UI thread: it takes a few seconds and the window must open first.
            [void](Start-TabulaUiJob -Script { param($q, $ctl) Get-TabulaProfile } -OnDone {
                    param($r, $err)
                    $u = $script:TabulaUi
                    $prof = if ($r) { $r | Select-Object -Last 1 } else { $null }
                    if ($err -or -not $prof) {
                        Set-TabulaStatus 'Could not detect this machine.'; Write-TabulaLog "detection failed: $err" -Level ERROR
                        foreach ($row in $u.AppRows) { if ($row.Status -eq 'Checking') { $row.Status = 'Unknown'; $row.StatusKind = 'warn' } }
                        return
                    }
                    $u.Profile = $prof
                    $dot = ' ' + [string][char]0x00B7 + ' '
                    $summary = (Get-TabulaProfileSummary -Profile $prof) -replace ' \| ', $dot
                    $u.MachineText.Text = $summary
                    $u.MachineLine.Text = $summary
                    if (-not $prof.Supported) {
                        $u.MachineLine.Text = $prof.SupportReason; Set-TabulaStatus $prof.SupportReason
                        $u.BtnSetup.IsEnabled = $false; $u.BtnReview.IsEnabled = $false
                        return
                    }
                    if (-not $prof.IsAdmin) { $u.ElevBanner.Visibility = 'Visible' }
                    foreach ($row in $u.AppRows) {
                        $app = $u.AppById[$row.Id]
                        $ap = Test-TabulaApplies -Tweak $app -Profile $prof
                        if (-not $ap.Applies) { $row.IsEnabled = $false; $row.IsChecked = $false; $row.Status = 'Not applicable'; $row.StatusKind = 'dim'; $row.Reason = $ap.Reason; $row.Sub = $ap.Reason }
                    }
                    Update-TabulaSetupSummary
                    Update-TabulaAppsSummary
                    Set-TabulaStatus 'Ready.'
                    Start-TabulaInstalledCheck
                    Start-TabulaTweakDetect
                })
            if ($u.OnReady) { & $u.OnReady $u.Window $u }
        })

    if ($AutoCloseMs -gt 0) {
        $close = New-Object Windows.Threading.DispatcherTimer
        $close.Interval = [TimeSpan]::FromMilliseconds($AutoCloseMs)
        $close.Add_Tick({ $script:TabulaUi.Window.Close() })
        $close.Start()
    }
    [void]$win.ShowDialog()
}

function Start-TabulaGui {
    [CmdletBinding()]
    param([ValidateSet('Auto', 'Dark', 'Light')][string]$Theme = 'Auto', [scriptblock]$OnReady, [int]$AutoCloseMs = 0)
    Initialize-TabulaUiTypes
    # Lets an automated check open the real window and have it close itself. Not a user setting.
    if ($AutoCloseMs -le 0 -and $env:TABULA_UI_AUTOCLOSE_MS -match '^\d+$') { $AutoCloseMs = [int]$env:TABULA_UI_AUTOCLOSE_MS }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        Show-TabulaWindow -Theme $Theme -OnReady $OnReady -AutoCloseMs $AutoCloseMs
        return
    }
    # WPF needs an STA thread. A console started with -MTA (or some hosts) is not one, so run the window on its own.
    Write-TabulaLog 'This host is not STA. Opening the window on its own STA runspace.'
    $rs = [runspacefactory]::CreateRunspace((New-TabulaSessionState -IncludeLog))
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    try {
        [void]$ps.AddScript('param($theme, $ms) Show-TabulaWindow -Theme $theme -AutoCloseMs $ms').AddArgument($Theme).AddArgument($AutoCloseMs)
        [void]$ps.Invoke()
        if ($ps.Streams.Error.Count -gt 0) { throw $ps.Streams.Error[0].ToString() }
    }
    finally { $ps.Dispose(); $rs.Dispose() }
}
