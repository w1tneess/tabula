# CLAUDE.md: repo rules for Tabula

## Project
Tabula: personal Windows 10/11 setup and optimisation tool. PowerShell 5.1 + WPF. See `MASTER_PROMPT.md` and `docs/`.

## Rules
- Target **Windows PowerShell 5.1**. No PS7-only syntax.
- Understand the existing code before changing it. Make the smallest change that solves the problem.
- Never state that code works unless it was run. Say what was and was not tested.
- Do not invent winget IDs, registry paths, flags or APIs. Verify against `winget show`, Microsoft docs, or a VM.
- Every tweak needs `apply`, `undo`, `detect` (current state), and metadata (see `docs/03-config-schemas.md`).
- Never touch the protected list in `docs/07-tweaks-catalog.md`.
- Official sources only for software.
- No telemetry, no secrets, no personal paths in the repo.
- No new dependencies without asking.

## Style
- Functions: `Verb-TabulaNoun`, approved verbs only. One responsibility each.
- Strict mode on (`Set-StrictMode -Version 2.0`). `$ErrorActionPreference = 'Stop'` inside engine functions, handled per item.
- Comments explain why, not what.
- UI copy: dry, short, understated. No exclamation marks, no emojis, no "awesome".

## Git
- Branch per milestone: `m0-scaffold`, `m1-engine`, ...
- Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- Do not commit `dist/`, logs, or state files. `dist/` is attached to releases.

## Commands
- Build: `./build.ps1`
- Lint: `Invoke-ScriptAnalyzer -Path src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
- Test: `Invoke-Pester ./tests`
- Dry run: `./dist/tabula.ps1 -Mode Auto -DryRun`

## When unsure
Ask one focused question. Keep working on everything that does not depend on the answer.
