# Apps verification

Checked 2026-11-24 on Windows 11 Pro build 26300 with winget v1.29.380, using `winget show --id <id> -e --accept-source-agreements` (read-only). Nothing was installed.

"Publisher" is what winget reports. "Match" is whether it fits the publisher expected in `docs/06-apps-catalog.md`.

| id | winget ID | Found | Publisher (winget) | Match | Version seen |
|---|---|---|---|---|---|
| chrome | Google.Chrome | yes | Google LLC | yes | 158.0.8127.37 |
| brave | Brave.Brave | yes | Brave Software Inc | yes | 158.1.100.58 |
| vscode | Microsoft.VisualStudioCode | yes | Microsoft Corporation | yes | 1.146.0 |
| git | Git.Git | yes | The Git Development Community | yes | 2.56.1 |
| github-cli | GitHub.cli | yes | GitHub, Inc. | yes | 2.105.0 |
| nodejs | OpenJS.NodeJS.LTS | yes | Node.js Foundation | **no** (brief guessed "OpenJS Foundation") | 26.13.1 |
| python | Python.Python.3.15 | yes | Python Software Foundation | yes | 3.15.2 |
| windows-terminal | Microsoft.WindowsTerminal | yes | Microsoft Corporation | yes | 1.25.3131.0 |
| powershell7 | Microsoft.PowerShell | yes | Microsoft Corporation | yes | 7.7.0.0 |
| notepadpp | Notepad++.Notepad++ | yes | Notepad++ Team | yes | 8.9.9.1 |
| 7zip | 7zip.7zip | yes | Igor Pavlov | yes | 26.06 |
| powertoys | Microsoft.PowerToys | yes | Microsoft Corporation | yes | 0.102.3101 |
| everything | voidtools.Everything | yes | voidtools | yes | 1.4.1.1032 |
| vlc | VideoLAN.VLC | yes | VideoLAN | yes | 3.0.24 |
| obs | OBSProject.OBSStudio | yes | OBS Project | yes | 33.0.3 |
| spotify | Spotify.Spotify | yes | Spotify AB | yes | 1.3.10.2586.g81a118a22460 |
| discord | Discord.Discord | yes | Discord Inc. | yes | 1.0.9270 |
| telegram | Telegram.TelegramDesktop | yes | Telegram FZ-LLC | yes | 7.4.6 |
| steam | Valve.Steam | yes | Valve Corporation | yes | 2.10.91.91 |
| tailscale | Tailscale.Tailscale | yes | Tailscale Inc. | yes | 1.104.7 |
| cloudflare-warp | Cloudflare.Warp | yes | Cloudflare, Inc. | yes | 26.8.2115.0 |
| qbittorrent | qBittorrent.qBittorrent | yes | The qBittorrent project | yes | 5.3.0 |

## Notes
- 22 of 22 IDs exist. One publisher string differs from the brief (Node.js); the package itself is the right one, so `apps.json` records the string winget reports.
- Python: the catalog's `Python.Python.3.13` is no longer the newest. `winget search Python.Python` lists 3.15 (3.15.2) and 3.14 (3.14.10), both published by the Python Software Foundation. `apps.json` uses 3.15. Change it to `Python.Python.3.14` if you want the previous minor.
- Git: winget's homepage is gitforwindows.org; `officialUrl` keeps git-scm.com, the project site.
- `officialUrl` values come from the catalog, not from winget. Only HTTPS and the host were reviewed; the URLs were not fetched.
- Not checked: whether each package installs silently, installs under an elevated session (Spotify and Discord are per-user installers), or supports `--scope machine`. That needs a real install in a VM.
