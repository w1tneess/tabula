# Runs inside Windows Sandbox (as its administrator user). For each tweak: read state, apply it through the real engine,
# read state, undo through the real engine, read state. Writes C:\Out\verify-tweaks.json. The sandbox is thrown away afterwards.
# This proves the apply and undo mechanics and that the keys exist on this build. It does not prove a setting does what its
# description says, and it does not replace checking the key against a Microsoft or other reliable source.
$ErrorActionPreference = 'Stop'
$repo = 'C:\TabulaRepo'
$script:TabulaBuild = @{ Version = 'sandbox'; Built = 'n/a'; Commit = 'n/a' }
foreach ($f in (Get-ChildItem "$repo\src\Core" -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
Set-StrictMode -Version 2.0
$script:TabulaRoot = $repo
[void](Initialize-TabulaLog -Path 'C:\Out\verify-tweaks.log' -Quiet)

$cfg = Get-TabulaConfig
$prof = Get-TabulaProfile
$out = New-Object System.Collections.Generic.List[object]
foreach ($t in $cfg['tweaks']) {
    $id = [string]$t['id']
    $rec = [ordered]@{ id = $id; build = $prof.Os.Build; edition = [string]$prof.Os.Edition }
    try {
        $before = Get-TabulaTweakState -Tweak $t -Profile $prof
        $rec.before = $before.State; $rec.beforeReason = $before.Reason
        if ($before.State -ne 'Unset') { $rec.result = 'inconclusive'; $rec.note = 'not in the "unset" state to begin with'; $out.Add([pscustomobject]$rec); continue }
        # Hold is cleared on purpose: this is the one place an unverified tweak may be applied, in a disposable machine.
        $item = [pscustomobject]@{ Kind = 'tweak'; Id = $id; Name = [string]$t['name']; Risk = [string]$t['risk']; Item = $t; Hold = $null }
        $apply = @(Invoke-TabulaPlan -Plan @($item) -Profile $prof -NoRestorePoint)[0]
        $rec.apply = $apply.Status; $rec.applyReason = $apply.Reason
        $rec.afterApply = (Get-TabulaTweakState -Tweak $t -Profile $prof).State
        $undo = @(Invoke-TabulaUndo -Tweaks $cfg['tweaks'])
        # Invoke-TabulaUndo returns a one-item array holding an empty array when there is nothing to revert.
        $rec.undo = (@($undo | ForEach-Object { @($_) } | ForEach-Object { $_.Status }) -join ',')
        $rec.afterUndo = (Get-TabulaTweakState -Tweak $t -Profile $prof).State
        $rec.result = if ($apply.Status -eq 'applied' -and $rec.afterApply -eq 'Set' -and $rec.undo -eq 'reverted' -and $rec.afterUndo -eq 'Unset') { 'pass' } else { 'fail' }
    }
    catch { $rec.result = 'error'; $rec.note = $_.Exception.Message }
    $out.Add([pscustomobject]$rec)
}
$out | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 'C:\Out\verify-tweaks.json'
'verify-tweaks finished: {0}' -f ((@($out) | Group-Object result | ForEach-Object { '{0} {1}' -f $_.Count, $_.Name }) -join ', ') | Add-Content -Encoding UTF8 'C:\Out\probe.txt'
