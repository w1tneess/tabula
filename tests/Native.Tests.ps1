BeforeAll { . $PSScriptRoot\TestHelper.ps1 }

Describe 'Invoke-TabulaNative (real processes)' {
    BeforeEach { Initialize-TestEnvironment $TestDrive }

    It 'refuses a bare program name' {
        { Invoke-TabulaNative -FilePath 'cmd.exe' } | Should -Throw '*full path*'
    }

    It 'returns output and exit code' {
        $r = Invoke-TabulaNative -FilePath (Get-TabulaSystemExe 'cmd.exe') -ArgumentList @('/c', 'echo hi & exit 3')
        $r.ExitCode | Should -Be 3
        $r.Output | Should -Match 'hi'
    }

    It 'enforces the timeout even when a child process holds the output pipe' {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-TabulaNative -FilePath (Get-TabulaSystemExe 'cmd.exe') -ArgumentList @('/c', 'ping -n 30 127.0.0.1') -TimeoutSec 2
        $sw.Stop()
        $r.TimedOut | Should -BeTrue
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 12
    }
}
