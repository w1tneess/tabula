# 01 Vision and scope

## Why this exists
Wit resets his PC every 3 to 4 months. Each time he reinstalls apps one by one and reconfigures Windows by hand. Tabula removes that: one command, a tuned Windows, all apps back, nothing sketchy.

Base inspiration: ChrisTitusTech/winutil (MIT). Same idea (curated Windows tweaks + installs), but smaller, personal, better looking, and rebuilt around the "post-reset" workflow.

## The core user story
> I just reset Windows. I open PowerShell as admin, paste one line, press one button (or add one flag). Twenty minutes later, my PC is tuned and my apps are installed. If I dislike anything, I undo it.

## Goals
1. **One-command rebuild**: `irm <url> | iex` then a single "Set up this PC" action. Also fully unattended via flags.
2. **Auto-adapt**: detect Windows 10 or 11, build number, edition (Home/Pro), laptop or desktop, SSD or HDD, RAM, GPU vendor. Choose sensible tweaks per machine.
3. **Safe by default**: restore point, per-tweak undo, dry run, logs. Conservative defaults.
4. **Official apps only**: winget with official IDs; vendor links for the rest.
5. **Minimal and polished UI**: dark, calm, fast, nothing busy.
6. **Self-documenting**: the README's tweak table is generated from `tweaks.json`.
7. **Personal backup**: "Export my installed apps" writes back into the app list, so the list never rots.

## Non-goals
- Not a general-purpose tool for every Windows user (yet).
- Not a debloater that rips Windows apart.
- Not an activation, licensing or "tweak the unlocker" tool. Ever.
- Not a driver updater, not an antivirus, not a cleaner that "boosts RAM".
- No cloud account, no sync service, no auto-updater daemon.

## Anti-goals (a failure even if it technically works)
- A tweak that cannot be undone.
- A run that leaves the PC in a half-changed state with no log.
- UI that looks like a hacker toy, a 2009 utility, or a crowded dashboard.
- Marketing language in the copy. Placebo "speed boost" tweaks.
- Anything that downloads software from a non-official source.
- Silent behaviour: the user must always be able to see what will change before it changes.

## Personality (the "vibe")
Reserved, observant, analytical. Quietly capable. Dry humour, never try-hard. Think a sharp assistant who does the job and says little.

- Name: **Tabula**. Tagline: *Clean slate, on demand.*
- Copy examples: "Detecting your machine." / "47 changes ready. Nothing applied yet." / "Done. 3 skipped, 0 failed." / "Undo complete. Windows is as you left it."
- No exclamation marks, no emojis, no motivational filler.
- Humour budget: one dry line on the About page, one in an empty state. Not more.

## Success looks like
- A fresh Windows 11 VM goes from first boot to "fully set up" in one run with no clicks beyond the first.
- Wit can read every line of the code and change it himself.
- Nothing in it surprises him.

## Phase 2 ideas (out of scope for the first release; do not build, do not block)
- Plug-in hook for his own tools (for example a file-declutter tool).
- Profiles (`-Profile Dev`, `-Profile Minimal`).
- Config pulled from his own GitHub gist or repo so the app list lives separately from the code.
