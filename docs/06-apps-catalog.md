# 06 Apps catalog (starter list)

**Status: unverified.** IDs below were written from memory of the winget repository. Before any ID goes into `apps.json`, run `winget show --id <id> -e` and confirm it exists and the publisher matches. Replace or drop anything that fails. Do not guess replacements; use `winget search <name>` and pick the official publisher.

`Default` means ticked in the `Standard` preset. This is a starting list: Wit edits it. The "Export installed apps" feature exists so he can regenerate it from a PC he already trusts.

| id | Name | Category | winget ID (verify) | Publisher | Official URL | Default |
|---|---|---|---|---|---|---|
| chrome | Google Chrome | Browsers | `Google.Chrome` | Google | https://www.google.com/chrome/ | yes |
| brave | Brave | Browsers | `Brave.Brave` | Brave Software | https://brave.com/ | yes |
| vscode | Visual Studio Code | Development | `Microsoft.VisualStudioCode` | Microsoft | https://code.visualstudio.com/ | yes |
| git | Git | Development | `Git.Git` | The Git Development Community | https://git-scm.com/ | yes |
| github-cli | GitHub CLI | Development | `GitHub.cli` | GitHub | https://cli.github.com/ | yes |
| nodejs | Node.js LTS | Development | `OpenJS.NodeJS.LTS` | OpenJS Foundation | https://nodejs.org/ | yes |
| python | Python 3 | Development | `Python.Python.3.13` (check the current stable minor version; the ID is version-specific) | Python Software Foundation | https://www.python.org/ | yes |
| windows-terminal | Windows Terminal | Development | `Microsoft.WindowsTerminal` | Microsoft | https://aka.ms/terminal | yes (Win10 only, Win11 has it) |
| powershell7 | PowerShell 7 | Development | `Microsoft.PowerShell` | Microsoft | https://github.com/PowerShell/PowerShell | no |
| notepadpp | Notepad++ | Utilities | `Notepad++.Notepad++` | Notepad++ Team | https://notepad-plus-plus.org/ | yes |
| 7zip | 7-Zip | Utilities | `7zip.7zip` | Igor Pavlov | https://www.7-zip.org/ | yes |
| powertoys | PowerToys | Utilities | `Microsoft.PowerToys` | Microsoft | https://github.com/microsoft/PowerToys | yes |
| everything | Everything | Utilities | `voidtools.Everything` | voidtools | https://www.voidtools.com/ | yes |
| vlc | VLC media player | Media | `VideoLAN.VLC` | VideoLAN | https://www.videolan.org/vlc/ | yes |
| obs | OBS Studio | Media | `OBSProject.OBSStudio` | OBS Project | https://obsproject.com/ | no |
| spotify | Spotify | Media | `Spotify.Spotify` | Spotify AB | https://www.spotify.com/download/ | yes |
| discord | Discord | Communication | `Discord.Discord` | Discord Inc. | https://discord.com/download | yes |
| telegram | Telegram Desktop | Communication | `Telegram.TelegramDesktop` | Telegram FZ-LLC | https://desktop.telegram.org/ | yes |
| steam | Steam | Gaming | `Valve.Steam` | Valve | https://store.steampowered.com/about/ | yes |
| tailscale | Tailscale | Network | `Tailscale.Tailscale` | Tailscale Inc. | https://tailscale.com/download | yes |
| cloudflare-warp | Cloudflare WARP | Network | `Cloudflare.Warp` | Cloudflare | https://one.one.one.one/ | no |
| qbittorrent | qBittorrent | Network | `qBittorrent.qBittorrent` | The qBittorrent project | https://www.qbittorrent.org/ | no |

## Notes
- Python: because the winget ID encodes the version, store `wingetId` for the current stable, and add a build-time warning if `winget search Python.Python` shows a newer minor.
- Windows Terminal ships with Windows 11. Mark `appliesTo` Windows 10 only, or let the install report "already installed".
- Discord, Spotify, Steam, Telegram install per-user or self-update. Treat "already installed" and "no applicable upgrade" as `skipped`.
- Anything else Wit adds later that is not in winget goes in as `source: manual` with the vendor's official page. The UI opens the page, it does not download.
- Optional additions to discuss with Wit (not in the list yet): a password manager of his choice, a PDF reader, a Git GUI, WSL, Docker Desktop. Ask before adding.
- GPU drivers (NVIDIA, AMD, Intel): out of scope for v1. The profile detects the GPU, the Apps page may show a vendor-official link as a suggestion only (NVIDIA app, AMD Software, Intel Driver & Support Assistant), and does not install it.

## Verification report (M2 deliverable)
Produce `docs/apps-verification.md`: a table of id, winget ID, `winget show` result (found / not found), publisher match (yes / no), date checked, winget version used.
