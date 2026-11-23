# state.json: runs, per-change prior values. Written before each change (write-ahead).
# State is plain hashtables and ArrayLists so strict mode never trips on missing JSON properties.

$script:TabulaStatePath = $null

function Get-TabulaStatePath {
    [CmdletBinding()]
    param()
    if ($script:TabulaStatePath) { return $script:TabulaStatePath }
    Join-Path $env:ProgramData 'Tabula\state.json'
}

function Assert-TabulaStateFolder {
    # The state file is what an elevated Undo acts on, so only SYSTEM and Administrators may write to its folder.
    # %ProgramData% lets standard users create files in new subfolders by default, so the folder gets an explicit
    # ACL, and an existing one is refused if someone else owns it or can write to it. Skipped when a path override
    # is set (tests); the override owner is responsible for it.
    [CmdletBinding()]
    param([switch]$Create, [string]$Folder)
    if ($Folder) { $dir = $Folder }
    else {
        if ($script:TabulaStatePath) { return }
        $dir = Split-Path -Parent (Get-TabulaStatePath)
    }
    $sid = { param($s) New-Object Security.Principal.SecurityIdentifier $s }
    $system = & $sid 'S-1-5-18'
    $admins = & $sid 'S-1-5-32-544'
    $trusted = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')

    if (-not (Test-Path -LiteralPath $dir)) {
        if (-not $Create) { return }
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($s in $system, $admins) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        }
        [void][IO.Directory]::CreateDirectory($dir, $acl)
        return
    }

    $acl = Get-Acl -LiteralPath $dir
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($trusted -notcontains $owner -and $owner -ne $me) { throw "state folder $dir is owned by $owner, not trusted" }
    $writeBits = [int][Security.AccessControl.FileSystemRights]'WriteData, AppendData, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        $who = $rule.IdentityReference.Value
        if ($rule.AccessControlType -ne 'Allow' -or $trusted -contains $who -or $who -eq 'S-1-3-0' -or $who -eq $me) { continue }
        if (([int]$rule.FileSystemRights -band $writeBits) -ne 0) { throw "state folder $dir grants write access to $who, not trusted" }
    }
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
    Assert-TabulaStateFolder
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
    Assert-TabulaStateFolder -Create
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
