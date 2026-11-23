# One place that runs external programs, so winget and powercfg can be mocked in tests
# and every command line lands in the log.

function ConvertTo-TabulaArgString {
    [CmdletBinding()]
    param([string[]]$ArgumentList = @())
    $quoted = foreach ($a in $ArgumentList) {
        if ($a -eq '' -or $a -match '[\s"]') {
            # Double the backslashes that precede a quote, then escape the quote (CommandLineToArgvW rules).
            '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
        }
        else { $a }
    }
    $quoted -join ' '
}

function Invoke-TabulaNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSec = 0,
        [switch]$Utf8
    )
    # A bare name would be searched for on PATH and the current folder, from an elevated process.
    if (-not [IO.Path]::IsPathRooted($FilePath)) { throw "Refusing to run '$FilePath': use a full path" }
    $argString = ConvertTo-TabulaArgString $ArgumentList
    Write-TabulaLog ('run: {0} {1}' -f $FilePath, $argString)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Utf8) {
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    }

    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        # Read both streams asynchronously or a full pipe buffer deadlocks the child.
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $timedOut = $false
        $ms = if ($TimeoutSec -gt 0) { $TimeoutSec * 1000 } else { -1 }
        if (-not $p.WaitForExit($ms)) {
            $timedOut = $true
            Stop-TabulaProcessTree -ProcessId $p.Id
        }
        $p.WaitForExit()
        # A grandchild that inherited the pipe (an installer) can hold it open after winget exits or is killed.
        # Waiting forever would defeat the timeout, so give the readers a few seconds and move on.
        $out = if ($outTask.Wait(5000)) { $outTask.Result } else { Write-TabulaLog 'output pipe still held by a child process, output dropped' -Level WARN; '' }
        $err = if ($errTask.Wait(1000)) { $errTask.Result } else { '' }
        [pscustomobject]@{
            ExitCode = $p.ExitCode
            Output   = ($out + $err)
            TimedOut = $timedOut
        }
    }
    finally { $p.Dispose() }
}

function Get-TabulaSystemExe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Join-Path ([Environment]::SystemDirectory) $Name
}

function Stop-TabulaProcessTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId)
    try { $null = & (Get-TabulaSystemExe 'taskkill.exe') /PID $ProcessId /T /F 2>$null }
    catch { Write-TabulaLog "could not kill process tree: $($_.Exception.Message)" -Level WARN }
}

function Get-TabulaOutputTail {
    # Last few meaningful lines, with winget's spinner and progress-bar noise removed.
    [CmdletBinding()]
    param([string]$Text, [int]$Lines = 5)
    $keep = @(($Text -split "\r?\n") | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^[\\|/\-\s]+$' -and $_ -notmatch '^[\u2580-\u259F\s\d%\.\/KMGB]+$' })
    ($keep | Select-Object -Last $Lines) -join ' | '
}
