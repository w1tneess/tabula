# Tabula: briefing pack

*Clean slate, on demand.*

Everything Claude Code needs to build Tabula, a personal Windows setup tool (a personal, smaller, better-looking take on ChrisTitusTech/winutil).

## How to use
1. Create a new empty folder for the project, for example `tabula`.
2. Copy this whole pack into it (keep the `docs/` folder).
3. Open Claude Code in that folder.
4. Paste the contents of `MASTER_PROMPT.md` as your first message.
5. Review each milestone report. Answer its one or two questions.

## Files
| File | Purpose |
|---|---|
| `MASTER_PROMPT.md` | The prompt to paste. Rules, milestones, definition of done. |
| `CLAUDE.md` | Standing repo rules Claude Code reads automatically. |
| `docs/01-vision-and-scope.md` | Why, goals, non-goals, anti-goals, personality |
| `docs/02-architecture.md` | Layout, build, launch, concurrency |
| `docs/03-config-schemas.md` | `apps.json`, `tweaks.json`, `presets.json`, `state.json` |
| `docs/04-ui-design-spec.md` | Look, feel, pages, copy, accessibility |
| `docs/05-detection-and-safety.md` | Machine detection, restore points, undo, winget |
| `docs/06-apps-catalog.md` | Starter app list (IDs unverified) |
| `docs/07-tweaks-catalog.md` | Starter tweak list (unverified) and protected list |
| `docs/08-build-test-plan.md` | Milestone acceptance, tests, VM matrix, CI |

## Known open points
- App list is a starting guess, Wit edits it.
- All winget IDs and registry values need verification (M2).
- Appx debloat (removing preinstalled apps) is deliberately excluded from v1.
- Hosting: one-liner assumes GitHub raw. A short link on his own domain is optional.
- Name "Tabula" is a proposal. Renaming later is a find-and-replace.
