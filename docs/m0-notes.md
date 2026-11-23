# M0 notes

Checked on Windows 11 Pro build 26300, Windows PowerShell 5.1.26100.9818. Not checked on Windows 10 or any clean VM.

## Launch spikes (stub script, no real engine yet)
| Check | Result |
|---|---|
| `Get-Content -Raw dist\tabula.ps1 \| Invoke-Expression` with a `[CmdletBinding()] param()` block | Works, runs default mode |
| `& ([scriptblock]::Create(...)) -Mode Auto -DryRun` | Works, parameters bind |
| WPF window from `iex` in the default (STA) console | Works |
| WPF window from an MTA console (`powershell -MTA`) via a new STA runspace | Works. Pattern to reuse in M3: if the apartment is not STA, open the window in an STA runspace |

Not checked: the real `irm` over HTTPS, PowerShell ISE, PowerShell 7 as the host.

## Findings that affect later work
- `$PSScriptRoot` is empty in `param()` defaults on 5.1. Resolve paths inside the body.
- After `iex`, `$script:` scope is the caller's global scope, so `$TabulaBuild` and the bundled functions persist in the user's session. Acceptable for now. Revisit if it becomes a problem.
- PS7-only syntax is reported by a 5.1 PSScriptAnalyzer as `ParseError`, not by `PSUseCompatibleSyntax`. The settings file and CI now include `ParseError`.
- Culture-specific time formatting produced `14.30.35` in the build header. The build now uses the invariant culture.

## Deviations from the docs
- Pester 6.2.0 was installed, not 5.x (the install took the latest). Tests use only the Pester 5 API. CI pins `-MinimumVersion 5.5`.
- Config validation in `build.ps1` is structural only (valid JSON, `schemaVersion` 1, array present). `Test-Json` does not exist on 5.1, so full schema validation is written by hand in M2.
- Sources must be ASCII. The build fails on anything else.
