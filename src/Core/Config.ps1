# Config validation. Test-Json is PowerShell 7 only, so the rules in docs/03-config-schemas.md are checked here.
# config/schema/*.json describe the same shapes for editors and other tools; this file is what actually runs.

$script:TabulaAppCategories = 'Browsers', 'Development', 'Communication', 'Media', 'Gaming', 'Utilities', 'Network', 'Productivity', 'Creative'
$script:TabulaTweakCategories = 'Privacy', 'Performance', 'Interface', 'Power', 'Network', 'Updates', 'Gaming'

function Test-TabulaConfig {
    # Returns a list of error strings, empty when the config is valid.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $e = New-Object System.Collections.Generic.List[string]
    $idPattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
    $has = { param($h, $k) $null -ne $h[$k] -and ([string]$h[$k]) -ne '' }

    $checkApplies = {
        param($owner, $a)
        if (-not $a['appliesTo']) { return }
        foreach ($k in @($a['appliesTo'].Keys)) {
            if ($k -notin 'minBuild', 'maxBuild', 'editions', 'chassis', 'storage') { $e.Add("${owner}: appliesTo has unknown key '$k'") }
        }
        if ($a['appliesTo']['chassis'] -and $a['appliesTo']['chassis'] -notin 'laptop', 'desktop') { $e.Add("${owner}: appliesTo.chassis must be laptop or desktop") }
        if ($a['appliesTo']['storage'] -and $a['appliesTo']['storage'] -notin 'ssd', 'hdd') { $e.Add("${owner}: appliesTo.storage must be ssd or hdd") }
        foreach ($ed in @($a['appliesTo']['editions'] | Where-Object { $null -ne $_ })) {
            if ($ed -notin 'Home', 'Pro', 'Enterprise', 'Education') { $e.Add("${owner}: unknown edition '$ed'") }
        }
    }

    # ---- apps
    $appIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($a in $Config['apps']) {
        $id = [string]$a['id']; $o = "app '$id'"
        if ($id -notmatch $idPattern) { $e.Add("app id '$id' must be lowercase kebab-case"); continue }
        if (-not $appIds.Add($id)) { $e.Add("duplicate app id '$id'") }
        foreach ($f in 'name', 'category', 'source', 'officialUrl') { if (-not (& $has $a $f)) { $e.Add("${o}: missing $f") } }
        if ($null -eq $a['defaultSelected'] -or $a['defaultSelected'] -isnot [bool]) { $e.Add("${o}: defaultSelected must be true or false") }
        if ($a['category'] -and $script:TabulaAppCategories -notcontains $a['category']) { $e.Add("${o}: unknown category '$($a['category'])'") }
        if ($a['source'] -notin 'winget', 'manual') { $e.Add("${o}: source must be winget or manual") }
        if ($a['source'] -eq 'winget') {
            if (-not (& $has $a 'wingetId')) { $e.Add("${o}: winget app needs wingetId") }
            elseif (([string]$a['wingetId']) -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { $e.Add("${o}: invalid wingetId") }
        }
        if ($a['officialUrl'] -and ([string]$a['officialUrl']) -notmatch '^https://[^\s/]+') { $e.Add("${o}: officialUrl must be https") }
        if ($a['scope'] -and $a['scope'] -notin 'machine', 'user') { $e.Add("${o}: scope must be machine or user") }
        $extra = @($a['extraArgs'] | Where-Object { $null -ne $_ })
        for ($i = 0; $i -lt $extra.Count; $i += 2) {
            if ($script:TabulaWingetExtraFlags -notcontains $extra[$i]) { $e.Add("${o}: extraArgs flag '$($extra[$i])' is not allowed") }
        }
        & $checkApplies $o $a
    }
    foreach ($a in $Config['apps']) {
        foreach ($r in @($a['requires'] | Where-Object { $null -ne $_ })) {
            if (-not $appIds.Contains([string]$r)) { $e.Add("app '$($a['id'])': requires unknown app '$r'") }
            if ($r -eq $a['id']) { $e.Add("app '$($a['id'])': requires itself") }
        }
    }

    # ---- tweaks
    $tweakIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($t in $Config['tweaks']) {
        $id = [string]$t['id']; $o = "tweak '$id'"
        if ($id -notmatch $idPattern) { $e.Add("tweak id '$id' must be lowercase kebab-case"); continue }
        if (-not $tweakIds.Add($id)) { $e.Add("duplicate tweak id '$id'") }
        foreach ($f in 'name', 'category', 'description', 'risk') { if (-not (& $has $t $f)) { $e.Add("${o}: missing $f") } }
        if ($t['category'] -and $script:TabulaTweakCategories -notcontains $t['category']) { $e.Add("${o}: unknown category '$($t['category'])'") }
        if ($t['risk'] -notin 'low', 'medium', 'high') { $e.Add("${o}: risk must be low, medium or high") }
        foreach ($f in 'defaultOn', 'verified') { if ($t[$f] -isnot [bool]) { $e.Add("${o}: $f must be true or false") } }
        if ($t['risk'] -eq 'high' -and $t['defaultOn'] -eq $true) { $e.Add("${o}: high risk tweaks cannot be default-on") }
        if ($t['verified'] -eq $false -and $t['defaultOn'] -eq $true) { $e.Add("${o}: unverified tweaks cannot be default-on") }
        if ($t['verified'] -eq $true -and @($t['testedBuilds'] | Where-Object { $null -ne $_ }).Count -eq 0) { $e.Add("${o}: verified needs testedBuilds") }
        if ($t['requiresRestart'] -and $t['requiresRestart'] -notin 'none', 'explorer', 'signout', 'reboot') { $e.Add("${o}: unknown requiresRestart") }
        # Only the paths the engine implements are accepted, so a config never promises more than it can do.
        if ($t['detect'] -ne 'actions') { $e.Add("${o}: detect must be 'actions' (named detectors are not in v1)") }
        if ($t['undo'] -ne 'restore-prior') { $e.Add("${o}: undo must be 'restore-prior' (explicit undo is not in v1)") }
        & $checkApplies $o $t

        $actions = @($t['actions'] | Where-Object { $null -ne $_ })
        if ($actions.Count -eq 0) { $e.Add("${o}: needs at least one action") }
        foreach ($a in $actions) {
            switch ($a['type']) {
                'registry' {
                    foreach ($f in 'hive', 'path', 'name', 'valueType') { if (-not (& $has $a $f)) { $e.Add("${o}: registry action missing $f") } }
                    if ($null -eq $a['value']) { $e.Add("${o}: registry action missing value") }
                    if ($a['valueType'] -and $a['valueType'] -notin 'DWord', 'String', 'ExpandString', 'QWord', 'Binary', 'MultiString') { $e.Add("${o}: unknown valueType '$($a['valueType'])'") }
                }
                'service' {
                    if (-not (& $has $a 'name')) { $e.Add("${o}: service action missing name") }
                    if ($a['startType'] -notin 'Automatic', 'Manual', 'Disabled') { $e.Add("${o}: service startType must be Automatic, Manual or Disabled") }
                }
                'scheduledTask' {
                    foreach ($f in 'path', 'name') { if (-not (& $has $a $f)) { $e.Add("${o}: scheduledTask action missing $f") } }
                    if ($a['state'] -notin 'Enabled', 'Disabled') { $e.Add("${o}: scheduledTask state must be Enabled or Disabled") }
                }
                'powercfg' {
                    switch ($a['op']) {
                        'setActiveScheme' { if (-not (& $has $a 'scheme')) { $e.Add("${o}: setActiveScheme needs scheme") } }
                        'duplicateScheme' { foreach ($f in 'scheme', 'guid') { if (-not (& $has $a $f)) { $e.Add("${o}: duplicateScheme needs $f") } } }
                        'hibernate' { if ($a['value'] -notin 'on', 'off') { $e.Add("${o}: hibernate value must be on or off") } }
                        default { $e.Add("${o}: powercfg op '$($a['op'])' is not supported") }
                    }
                }
                'function' { }   # allow-list check happens in the protected-list guard below
                default { $e.Add("${o}: unknown action type '$($a['type'])'") }
            }
        }
        $why = Test-TabulaProtected -Tweak $t
        if ($why) { $e.Add("${o}: $why") }
    }

    # ---- presets
    $presetIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $Config['presets']) {
        $pid_ = [string]$p['id']; $o = "preset '$pid_'"
        if (-not $pid_) { $e.Add('preset without id'); continue }
        if (-not $presetIds.Add($pid_)) { $e.Add("duplicate preset id '$pid_'") }
        foreach ($pair in @(@('apps', 'defaultSelected', $appIds, 'app'), @('tweaks', 'defaultOn', $tweakIds, 'tweak'))) {
            $v = $p[$pair[0]]
            if ($null -eq $v) { $e.Add("${o}: missing $($pair[0])"); continue }
            if ($v -is [string]) { if ($v -ne $pair[1]) { $e.Add("${o}: $($pair[0]) must be '$($pair[1])' or a list") } }
            else { foreach ($i in @($v)) { if (-not $pair[2].Contains([string]$i)) { $e.Add("${o}: unknown $($pair[3]) '$i'") } } }
        }
        if ($p['overrides']) {
            foreach ($trait in @($p['overrides'].Keys)) {
                if ($trait -notin 'laptop', 'desktop', 'win10', 'win11', 'hdd', 'ssd') { $e.Add("${o}: unknown override trait '$trait'") }
                foreach ($pair in @(@('addTweaks', $tweakIds), @('excludeTweaks', $tweakIds), @('addApps', $appIds), @('excludeApps', $appIds))) {
                    foreach ($i in @($p['overrides'][$trait][$pair[0]] | Where-Object { $null -ne $_ })) {
                        if (-not $pair[1].Contains([string]$i)) { $e.Add("${o}: override $trait.$($pair[0]) names unknown id '$i'") }
                    }
                }
            }
        }
    }
    # Callers wrap the call in @(): an empty result unrolls to nothing, which is what "no errors" should be.
    $e.ToArray()
}
