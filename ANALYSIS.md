# Tabula: analysis of the briefing pack

Source: `tabula-brief.zip`, extracted to `tabula-brief/` next to this file. All 11 files read in full (README, MASTER_PROMPT, CLAUDE, docs 01 to 08).

## 1. What it is

A personal Windows 10/11 post-reset tool. One command, then: detect the machine, apply reversible tweaks, reinstall apps from winget, with a small dark WPF GUI and full undo. Tagline "Clean slate, on demand." A trimmed, tasteful take on WinUtil for one user (Wit).

- Stack: Windows PowerShell 5.1, WPF (XAML in here-strings), winget, Pester 5 and PSScriptAnalyzer (dev only).
- Shipped as one file, `dist/tabula.ps1`, built from a modular `src/` by `build.ps1`. Launched with `irm <url> | iex`.
- Data-driven: `apps.json`, `tweaks.json`, `presets.json`, `state.json`. No code in JSON; tweak actions are structured (registry, service, scheduledTask, powercfg) plus an allow-listed `function` escape hatch.
- Six milestones, M0 scaffold to M6 release, with a report format after each.

## 2. What is strong about the brief

- Safety model is concrete: restore point, write-ahead state, reverse-order undo, dry run, protected list enforced at build time and runtime.
- Scope discipline: explicit non-goals and anti-goals, no Appx debloat in v1, no Defender/Update/UAC/boot tweaks.
- "Never claim it works unless it ran" and "verified: false means hidden and off" keep unverified registry values from reaching a real machine.
- Per-item failure handling and exit codes (0/1/2/3) are defined.
- Copy and UI rules are specific enough to build against (tokens, sizes, radii, motion, page-by-page layout).

## 3. Gaps and contradictions found

| # | Issue | Where | Suggested resolution |
|---|---|---|---|
| 1 | Rule "`verified: false` implies `defaultOn: false`" conflicts with the catalog, where nearly every tweak is unverified yet "on" by default. On day one the Standard preset would tick nothing. | 03 validation rules vs 07 | Treat catalog "on" as the *intended* default. Set `defaultOn` true only as each tweak gets verified. `-Mode Auto` will have almost no tweaks until M2 verification is done. |
| 2 | The definition of done needs `-Mode Auto` to apply default tweaks on a clean VM, but verification needs VMs. | MASTER 7, 08 | See section 4. This is the real blocker. |
| 3 | Apps have no `appliesTo`, but the Windows Terminal note says to mark it Windows 10 only. | 03 vs 06 | Add an optional `appliesTo` (minBuild/maxBuild) to the app schema, or rely on "already installed" and drop the note. Prefer the schema field. |
| 4 | `-IncludeHighRisk` is introduced in doc 05 but is missing from the parameter table in doc 02. `-Profile`, `-Mode Export` details are also thin. | 02 vs 05 | Add to the table. Trivial. |
| 5 | Python winget ID is version-specific (`Python.Python.3.13`). The brief's date is Nov 2026, so 3.14 or later is likely current. | 06 | Check with `winget search Python.Python` at M2. The brief already asks for a build-time warning. |
| 6 | Default scope is `machine`, but several default apps (Spotify, Discord, Telegram, Steam) are per-user or self-updating. Spotify's installer has historically refused to run elevated. | 03, 06 | Test per app in M2. Allow `scope: user` per app, and fall back to an `already installed`/skip result rather than a hard failure. |
| 7 | `irm | iex` with a `param()` block: parameters cannot be passed that way, and `param()` behaviour under `iex` is a known edge. The brief documents the script-block form but does not say the GUI path was tested. | 02 | Prove both launch forms in M0, with a stub script, before anything is built on them. |
| 8 | STA requirement for WPF under `iex` (the brief flags it). | 02 | Treat as an M0 spike, not an M3 surprise. |
| 9 | HKCU tweaks when the elevated account differs from the interactive user. v1 only logs a warning. | 03, 05 | Acceptable for a one-user tool. Make the warning visible in the GUI, not only the log. |
| 10 | "Undo this run" semantics when a later run records `skipped` for something an earlier run applied. Undoing run 2 will not revert run 1. | 03 | Define it: Undo applies to the last run with changes, or per tweak across runs. Small design decision, worth one line in the spec. |
| 11 | Telemetry tweak can only promise "required minimum" on Home/Pro. | 05, 07 | Already called out. Keep the UI text honest. |
| 12 | Both Chrome and Brave are default-selected, and Tailscale, Steam, etc. are default-on. | 06 | Wit's call. Starter list only. |

## 4. Environment reality on this machine

Checked read-only, nothing changed:

| Item | Found |
|---|---|
| OS | Windows 11 Pro, build 26300 (newer than 26100/24H2) |
| Windows PowerShell | 5.1.26100.9818 (the target runtime, good) |
| winget | v1.29.380 (can verify IDs for real) |
| git | 2.56.0 |
| Pester | 3.4.0 only (brief requires Pester 5, dev-time install needed) |
| PSScriptAnalyzer | not installed (dev-time install needed) |
| Windows Sandbox | not present |
| Hyper-V manager / VirtualBox | not present |

Consequence: **there is no safe place to test tweaks here.** The brief forbids running unverified tweaks on Wit's real system. Without Sandbox, Hyper-V or VirtualBox, these cannot be done honestly:

- M1 apply/undo round-trip of real tweaks (the registry wrapper can still be tested on a scratch key under `HKCU:\Software\TabulaTest`).
- M2 tweak verification and `testedBuilds`.
- The M6 clean-VM matrix.

What can be done here with no risk:

- Apps verification: `winget show --id <id> -e` for every app, which writes `apps-verification.md`.
- Schemas, validation rules, build script, lint, parse check on 5.1.
- Pester tests with mocked CIM and a scratch registry key.
- Dry-run planning and profile detection (read-only).
- The whole GUI shell, theme and navigation (M3), since it can run against a fake engine.

Options for the testing gap: enable Windows Sandbox (Pro supports it; needs a feature enable and reboot, so your call), install VirtualBox or Hyper-V with a Windows 11 evaluation ISO, or accept that tweak verification stays "unverified, hidden under Experimental" until you test on a VM yourself.

## 5. Where the effort and risk sit

1. **WPF theme and control restyling** (M3 and M5) is the largest chunk. Custom Button, CheckBox, ToggleSwitch, ScrollBar, TextBox, ProgressBar, ToolTip, list rows, in two themes, with scaling and keyboard access. Plan for most of the build time here.
2. **Runspace concurrency** in PowerShell 5.1: UI thread never blocked, synchronised queue, dispatcher updates, cancel flag. Easy to get subtly wrong.
3. **Single-file build**: embedding XAML and JSON as here-strings, the `'@` line-start trap, and parsing the bundle on 5.1.
4. **State and undo correctness**: write-ahead state, absent-key versus absent-value handling, crash recovery. This is the part that must be right, and the part that unit tests can cover well.
5. **winget in an unattended run**: exit-code mapping changes between versions, per-package timeout, per-user installers under elevation.

## 6. Proposed build approach

Follow the brief's milestones, with these adjustments:

- **M0 plus spikes**: scaffold, then prove two things before anything else: `irm | iex` and the script-block launch both work with a stub, and a WPF window opens from an `iex` console via an STA runspace.
- **M1**: engine and CLI. Test the registry wrapper, write-ahead state and undo against the scratch key only. Dry run is safe to run on the real machine. No real tweak is applied here.
- **M2**: run the app verification for real (`winget show`). Build the tweak catalog as `verified: false`, all off, all Experimental, until a VM exists.
- **M3 to M5**: GUI against the engine, with a fake long task first.
- **M6**: only possible once a VM matrix exists. Otherwise stop at "release candidate, untested on clean VMs" and say so.
- Dev-time installs needed: Pester 5 and PSScriptAnalyzer (both listed in the brief, user-scope install).
- Project would become a git repo in `D:\Code\Mine\tabula` (branch per milestone, conventional commits, no `dist/`, logs or state committed), per `CLAUDE.md`.

## 7. Decisions needed from you before building

1. **Testing**: enable Windows Sandbox, set up a VM, or build with tweaks held as unverified until you test? This decides whether M1 round-trips on real tweaks and M2 verification can happen at all.
2. **Where it lives**: build inside `D:\Code\Mine\tabula` directly (the pack currently sits in `tabula-brief/`), with the briefing docs moved into the repo root as the README intends?
3. **GitHub**: the one-liner assumes `raw.githubusercontent.com/<user>/tabula`. Which username/repo, or leave a placeholder for now?
4. **App list**: keep the starter list as is, or edit it first (both Chrome and Brave default-on, a password manager, PDF reader, Git GUI, WSL, Docker are listed as "ask before adding")?
5. **Name**: keep "Tabula".

## 8. Verdict

The brief is unusually complete and internally consistent apart from the items in section 3. None of them block starting. The one real constraint is verification: this machine has the right shell, winget and git, but no disposable Windows to test tweaks in. Starting at M0 and M1 is safe now; M2 tweak verification and M6 depend on decision 1.
