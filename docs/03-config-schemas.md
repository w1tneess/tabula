# 03 Config schemas

Config is data. No code in JSON. Validate against JSON Schema in `config/schema/` at build time and at runtime start.

## apps.json

```json
{
  "schemaVersion": 1,
  "apps": [
    {
      "id": "vscode",
      "name": "Visual Studio Code",
      "category": "Development",
      "description": "Code editor.",
      "source": "winget",
      "wingetId": "Microsoft.VisualStudioCode",
      "publisher": "Microsoft",
      "officialUrl": "https://code.visualstudio.com/",
      "defaultSelected": true,
      "scope": "machine",
      "extraArgs": [],
      "requires": [],
      "notes": ""
    },
    {
      "id": "example-nonwinget",
      "name": "Example Vendor Tool",
      "category": "Utilities",
      "source": "manual",
      "officialUrl": "https://vendor.example/download",
      "defaultSelected": false,
      "notes": "Not in winget. Opens the official download page."
    }
  ]
}
```

Fields:
| Field | Req | Notes |
|---|---|---|
| `id` | yes | Unique, lowercase, kebab-case. Stable (used in presets and `-Apps`). |
| `name` | yes | Display name. |
| `category` | yes | One of: Browsers, Development, Communication, Media, Gaming, Utilities, Network, Productivity, Creative. Extendable. |
| `description` | no | One short line. |
| `source` | yes | `winget` or `manual`. (`msstore` allowed later, not in v1.) |
| `wingetId` | if winget | Exact official ID. Verified by `winget show --id <id> -e`. |
| `publisher` | no | Expected publisher string, used as a sanity check against `winget show`. |
| `officialUrl` | yes | The vendor's own site. Shown in the UI as a link. |
| `defaultSelected` | yes | Whether the `Standard` preset ticks it. |
| `scope` | no | `machine` (default) or `user`. Pass `--scope` when supported. |
| `extraArgs` | no | Extra winget args from an allow-list (`--override` is **not** allowed in v1). |
| `requires` | no | IDs of other apps to install first (e.g. a runtime). |
| `notes` | no | Free text. |

Install command pattern (engine builds it, never from JSON strings):
```
winget install --id <wingetId> -e --accept-package-agreements --accept-source-agreements --silent [--scope machine]
```
Detection: `winget list --id <wingetId> -e` (exit code and output). Treat "already installed, no upgrade" as `skipped`.

## tweaks.json

```json
{
  "schemaVersion": 1,
  "tweaks": [
    {
      "id": "classic-context-menu",
      "name": "Classic right-click menu",
      "category": "Interface",
      "description": "Restores the full context menu on Windows 11 without 'Show more options'.",
      "risk": "low",
      "appliesTo": { "minBuild": 22000, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "requiresRestart": "explorer",
      "defaultOn": true,
      "verified": false,
      "testedBuilds": [],
      "actions": [
        {
          "type": "registry",
          "hive": "HKCU",
          "path": "Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\\InprocServer32",
          "name": "(Default)",
          "valueType": "String",
          "value": "",
          "createKey": true
        }
      ],
      "detect": "actions",
      "undo": "restore-prior"
    }
  ]
}
```

Fields:
| Field | Req | Notes |
|---|---|---|
| `id`, `name`, `category`, `description` | yes | Categories: Privacy, Performance, Interface, Power, Network, Updates, Gaming. |
| `risk` | yes | `low`, `medium`, `high`. `high` is never default-on and needs a confirmation dialog. |
| `appliesTo` | no | `minBuild`, `maxBuild`, `editions`, `chassis` (`laptop`/`desktop`), `storage` (`ssd`/`hdd`). If the profile does not match, the tweak is shown greyed with the reason and skipped. |
| `requiresRestart` | no | `none` (default), `explorer`, `signout`, `reboot`. UI collects these and offers one action at the end. |
| `defaultOn` | yes | Whether `Standard` ticks it. |
| `verified` | yes | `true` only after VM-tested. Unverified tweaks live under "Experimental" and are off by default. |
| `testedBuilds` | no | Windows build numbers it was tested on. |
| `actions` | yes | Ordered list of structured actions (below). |
| `detect` | yes | `actions` (compare current state to the target values) or a named detector function from the allow-list. |
| `undo` | yes | `restore-prior` (use recorded prior state) or `explicit` (with `undoActions`). Prefer `restore-prior`. |

### Action types (v1)
- `registry`: `hive` (HKCU, HKLM), `path`, `name`, `valueType` (DWord, String, ExpandString, QWord, Binary, MultiString), `value`, `createKey`. Prior state records: key existed, value existed, old value and type.
- `service`: `name`, `startType` (Automatic, Manual, Disabled). Prior start type recorded. Never stop or disable services in the protected list.
- `scheduledTask`: `path`, `name`, `state` (Enabled, Disabled). Prior state recorded.
- `powercfg`: structured, e.g. `{ "type": "powercfg", "op": "setActiveScheme", "scheme": "SCHEME_BALANCED" }`. Allowed ops: `setActiveScheme`, `duplicateScheme` (with GUID), `hibernate` (on/off), `setValue` (scheme, subgroup, setting, ac/dc, value). Record prior active scheme / values.
- `function`: `name` from an allow-list in the engine for the rare thing that cannot be expressed as data. Must expose `Apply`, `Undo`, `Detect`.

Registry writes to HKLM need admin. HKCU writes made by an elevated process apply to the elevated user. If the admin account differs from the logged-in standard user, the tweak must target the right user hive. v1 assumes the user runs Tabula as themselves with elevation, and logs a warning if the elevated user is not the interactive user.

## presets.json

```json
{
  "schemaVersion": 1,
  "presets": [
    {
      "id": "Standard",
      "name": "Standard",
      "description": "Safe defaults for a daily-driver PC.",
      "apps": "defaultSelected",
      "tweaks": "defaultOn",
      "overrides": {
        "laptop": { "excludeTweaks": ["ultimate-performance-plan"] }
      }
    },
    {
      "id": "Minimal",
      "name": "Minimal",
      "description": "Only low-risk, visible-benefit changes. Core apps.",
      "apps": ["chrome", "7zip", "vlc", "vscode"],
      "tweaks": ["file-extensions", "hidden-files", "disable-ad-id", "classic-context-menu"]
    }
  ]
}
```
`apps` / `tweaks` accept either `"defaultSelected"`/`"defaultOn"` (use the flags) or an explicit ID list. `overrides` keyed by profile traits (`laptop`, `desktop`, `win10`, `win11`, `hdd`, `ssd`) add or remove IDs.

## state.json (written by the engine)
```json
{
  "schemaVersion": 1,
  "runs": [
    {
      "runId": "20261123-201500",
      "startedAt": "2026-11-23T20:15:00+05:30",
      "profile": { "os": "Windows 11 Pro", "build": 26100, "chassis": "laptop" },
      "restorePoint": { "created": true, "sequence": 123 },
      "changes": [
        {
          "tweakId": "classic-context-menu",
          "status": "applied",
          "prior": [
            { "type": "registry", "hive": "HKCU", "path": "...", "name": "(Default)", "keyExisted": false, "valueExisted": false }
          ]
        }
      ]
    }
  ]
}
```
Undo walks `changes` in reverse and restores `prior`. A tweak recorded `skipped` is not touched on undo. Writing state happens **before** applying each tweak's change (write-ahead), so a crash mid-run still leaves enough to revert.

## Validation rules (build-time tests)
- Unique IDs across each file; presets reference existing IDs only.
- Every `winget` app has `wingetId`; every `manual` app has `officialUrl`; every app has `officialUrl`.
- `officialUrl` must be `https`.
- Every tweak has `undo` and at least one action; `high` risk has `defaultOn: false`.
- `verified: false` implies `defaultOn: false`.
- No tweak touches the protected list (`docs/07-tweaks-catalog.md`).
