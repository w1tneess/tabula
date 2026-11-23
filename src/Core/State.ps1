# state.json: runs, per-change prior values. Written before each change (write-ahead).
# State is plain hashtables and ArrayLists so strict mode never trips on missing JSON properties.

$script:TabulaStatePath = $null

function Get-TabulaStatePath {
    [CmdletBinding()]
    param()
    if ($script:TabulaStatePath) { return $script:TabulaStatePath }
    Join-Path $env:ProgramData 'Tabula\state.json'
}

function ConvertTo-TabulaData {
    [CmdletBinding()]
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-TabulaData $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($i in $InputObject) { [void]$list.Add((ConvertTo-TabulaData $i)) }
        return , $list
    }
    if ($InputObject -is [pscustomobject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-TabulaData $p.Value }
        return $h
    }
    $InputObject
}

function Get-TabulaState {
    [CmdletBinding()]
    param()
    $path = Get-TabulaStatePath
    if (Test-Path -LiteralPath $path) {
        $raw = [IO.File]::ReadAllText($path)
        if ($raw.Trim()) {
            # An unreadable state file is the undo record. Fail loudly rather than start a new one over it.
            try { $state = ConvertTo-TabulaData ($raw | ConvertFrom-Json) }
            catch { throw "state file is unreadable ($path): $($_.Exception.Message)" }
            if ($state['schemaVersion'] -ne 1) { throw "state file has unsupported schemaVersion '$($state['schemaVersion'])'" }
            return $state
        }
    }
    @{ schemaVersion = 1; runs = (New-Object System.Collections.ArrayList) }
}

function Save-TabulaState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $path = Get-TabulaStatePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = "$path.tmp"
    $json = ConvertTo-Json -InputObject $State -Depth 12
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function New-TabulaRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Profile)
    $run = @{
        runId        = (Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
        startedAt    = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        profile      = @{ os = $Profile.Os.Caption; build = $Profile.Os.Build; chassis = $Profile.Chassis }
        restorePoint = $null
        status       = 'running'
        changes      = (New-Object System.Collections.ArrayList)
    }
    [void]$State['runs'].Add($run)
    Save-TabulaState $State
    $run
}

function Add-TabulaChange {
    # Called before the tweak touches anything, so a crash still leaves the prior values on disk.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$TweakId, [Parameter(Mandatory)]$Prior)
    $change = @{ tweakId = $TweakId; status = 'pending'; prior = $Prior }
    [void]$Run['changes'].Add($change)
    Save-TabulaState $State
    $change
}

function Set-TabulaChangeStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Change, [Parameter(Mandatory)][string]$Status)
    $Change['status'] = $Status
    Save-TabulaState $State
}

function Complete-TabulaRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Run)
    $Run['status'] = 'complete'
    Save-TabulaState $State
}

function Get-TabulaRevertibleRun {
    # Latest run that still has changes to revert (applied, or pending after a crash).
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $runs = $State['runs']
    for ($i = $runs.Count - 1; $i -ge 0; $i--) {
        foreach ($c in $runs[$i]['changes']) {
            if ($c['status'] -eq 'applied' -or $c['status'] -eq 'pending') { return $runs[$i] }
        }
    }
    $null
}

function Find-TabulaIncompleteRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    foreach ($r in $State['runs']) { if ($r['status'] -eq 'running') { return $r } }
    $null
}
