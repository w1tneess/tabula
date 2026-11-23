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
            try { $p.Kill() } catch { Write-TabulaLog "could not kill timed-out process: $($_.Exception.Message)" -Level WARN }
        }
        $p.WaitForExit()
        [pscustomobject]@{
            ExitCode = $p.ExitCode
            Output   = ($outTask.Result + $errTask.Result)
            TimedOut = $timedOut
        }
    }
    finally { $p.Dispose() }
}

function Get-TabulaOutputTail {
    # Last few meaningful lines, with winget's spinner and progress-bar noise removed.
    [CmdletBinding()]
    param([string]$Text, [int]$Lines = 5)
    $keep = @(($Text -split "\r?\n") | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^[\\|/\-\s]+$' -and $_ -notmatch '^[\u2580-\u259F\s\d%\.\/KMGB]+$' })
    ($keep | Select-Object -Last $Lines) -join ' | '
}
