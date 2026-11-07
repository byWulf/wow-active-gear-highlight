# AGENTS.md

## Language

All documentation in this repository (README, AGENTS.md, code comments, commit messages) is written in **English**.

## Project

WoW addon `SmartGearSwitcher` (shown as "Smart Gear Switcher"): one smart macro per equipment set that equips the set, or saves/re-equips it when the player changed the set they're wearing. Marks the button of the worn set on any action bar with a static border (and a glow while changed).

- `SmartGearSwitcher.toc`: addon manifest, interface `16001` (WoW Forever only, Classic Era is not supported), SavedVariables `SmartGearSwitcherDB` (account-wide options) and `SmartGearSwitcherCharDB` (per character: `current` = set ID of the worn set, `names[setID]` = last known set names for rename detection)
- `Locales.lua`: all user-facing strings. English is the base table, other locales only override keys. Exposed as `ns.L`. Covers every text locale of the WoW Forever client (product `wowf`, `supported_text_locales` in its product config): enUS, deDE, frFR, esES, esMX (copy of esES with a few overrides), ptBR, ruRU, koKR, zhCN, zhTW. There is no itIT client. The TOC has a localized `Notes-xxXX` for each.
- `Core.lua`: options defaults, set helpers (`ns.Diff` compares equipped items with a set slot by slot, honoring ignored slots), tracking of the worn set, the actions (`ns.Smart`, `ns.Equip`, `ns.Save`, `ns.RequestSave`), the `/sgs` command and all events
- `Macros.lua`: parsing `/sgs` macros, creating them (character macros first), and keeping them in sync (set icon, renamed sets, the "current set" macro's name and icon). Macros can't be created or edited in combat; syncing is deferred to `PLAYER_REGEN_ENABLED`.
- `Buttons.lua`: finding action buttons of all bar addons (named lists, Blizzard's `ActionBarButtonEventsFrame.frames`, LibActionButton registries, plus one walk over all frames), reading the action slot of a button, the border/glow overlay, and the action tooltip hook (`GameTooltip:SetAction`)
- `Dialog.lua`: the save/re-equip window listing the changed slots
- `EquipmentManager.lua`: hooks `PaperDollEquipmentManagerPane_InitButton` so dragging a set from the Equipment Manager picks up our macro (Shift-drag keeps Blizzard's set button)
- `Options.lua`: options page with Blizzard's Settings API (vertical layout)

Key behavior:

- "Worn set" = the set equipped last (`EQUIPMENT_SWAP_FINISHED` carries the set ID). If the gear stops matching it but matches another set exactly, that set takes over. During a swap (`EQUIPMENT_SWAP_PENDING` until `..._FINISHED`) nothing is re-evaluated.
- A macro belongs to us when a line starts with `/sgs` or `/smartgear`. Managed set macros have the exact body `/sgs <set name>`; the "current set" macro is `/sgs current`. A set name always wins over the keywords (`save`, `restore`, `equip`, `macro`, `current`).
- Saving sets the save-ignore flags to the set's ignored slots, calls `C_EquipmentSet.SaveEquipmentSet`, then restores the previous flags (the Equipment Manager uses them for its own display).
- None of the C_EquipmentSet functions used are protected in Forever, but armor can't be swapped in combat: equipping in combat is queued until combat ends.

The Forever UI source is mirrored at https://github.com/Gethe/wow-ui-source (branch `forever`, game type "Camelot"). Check it before relying on Blizzard frame or function names.

When adding a user-facing string, add the key to the English base table and to every locale in `Locales.lua`.

## Installed copies

The addon is installed as a plain copy (not a clone) in:

- `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\SmartGearSwitcher`

After changing the `.toc` or any `.lua`, copy them to the Forever installation. The folder name must stay `SmartGearSwitcher`.

## Testing

There is no automated test setup. Changes are verified in game with `/reload`; Lua errors show up with `/console scriptErrors 1`. A syntax check is possible with `luajit -bl <file>.lua`.

## Releasing

Releases are built by `.github/workflows/release.yml` with the BigWigs packager (`.pkgmeta` sets the folder name and leaves out `AGENTS.md`/`CLAUDE.md`). The CurseForge project doesn't exist yet; once it does, add `## X-Curse-Project-ID: <ID>` to the TOC and the CurseForge link to the README installation section.

1. Commit and push the changes to `main`.
2. Tag and push: `git tag -a vX.Y.Z -m "X.Y.Z"` and `git push origin vX.Y.Z` (semantic versioning).
3. The workflow packages the addon, replaces `@project-version@` in the TOC with the tag, uploads the zip to CurseForge (game version from the TOC interface, WoW Forever) and creates the GitHub release.

The CurseForge upload needs the repository secret `CF_API_TOKEN`. Never edit `## Version` in the TOC by hand; installed dev copies show `@project-version@`.
