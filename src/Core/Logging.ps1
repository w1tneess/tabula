# Logging: file sink, in-memory sink for the UI, console echo.

$script:TabulaLog = @{
    Path  = $null
    Lines = (New-Object System.Collections.Generic.List[string])
    Debug = $false
    Quiet = $false
    Queue = $null   # set in a window job: lines go to the UI thread, which is the only writer of the log file
}

function Get-TabulaTimestamp {
    # Custom format strings use the culture's time separator, which gave 14.30.35 once. Pin the culture.
    (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
}

function Initialize-TabulaLog {
    [CmdletBinding()]
    param([string]$Path, [switch]$DebugEnabled, [switch]$Quiet)

    $isDefault = -not $Path
    if ($isDefault) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
        $Path = Join-Path $env:LOCALAPPDATA ('Tabula\logs\tabula-{0}.log' -f $stamp)
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $script:TabulaLog.Path = $Path
    $script:TabulaLog.Lines.Clear()
    $script:TabulaLog.Debug = [bool]$DebugEnabled
    $script:TabulaLog.Quiet = [bool]$Quiet

    if ($isDefault) {
        # Keep the last 10. Only for the default folder, so a user-chosen path never loses other files.
        Get-ChildItem -LiteralPath $dir -Filter 'tabula-*.log' | Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $Path
}

function Write-TabulaLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )
    if ($Level -eq 'DEBUG' -and -not $script:TabulaLog.Debug) { return }

    $line = '{0} [{1}] {2}' -f (Get-TabulaTimestamp), $Level, $Message
    $script:TabulaLog.Lines.Add($line)

    if ($script:TabulaLog.ContainsKey('Queue') -and $script:TabulaLog.Queue) {
        $script:TabulaLog.Queue.Enqueue(@{ TabulaLogLine = $line })
        return
    }
    if ($script:TabulaLog.Path) {
        try { [IO.File]::AppendAllText($script:TabulaLog.Path, $line + "`r`n") }
        catch { $script:TabulaLog.Path = $null }   # a broken log path must not stop the run; stop retrying
    }
    if (-not $script:TabulaLog.Quiet) {
        $color = switch ($Level) { 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'DEBUG' { 'DarkGray' } default { 'Gray' } }
        Write-Host $line -ForegroundColor $color
    }
}

function Add-TabulaLogLine {
    # A line that a job already formatted. Called on the UI thread so the file has one writer.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line)
    $script:TabulaLog.Lines.Add($Line)
    if ($script:TabulaLog.Path) {
        try { [IO.File]::AppendAllText($script:TabulaLog.Path, $Line + "`r`n") }
        catch { $script:TabulaLog.Path = $null }
    }
}

function Get-TabulaLogLines {
    [CmdletBinding()]
    param()
    , $script:TabulaLog.Lines.ToArray()
}
