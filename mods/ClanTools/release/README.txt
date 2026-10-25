CLAN TOOLS - 0.3.0-rc1

An unofficial offline mod for Warrior Cats: Clans of the Forest.
Supported: Steam app 3960600, build 24847281, Windows x64.
This is a local release candidate for user testing. It has not been uploaded to
Steam Workshop. Read VALIDATION.txt for tested behavior and remaining coverage.

INSTALL
1. Save and close the game. Extract the entire ZIP into a normal folder.
2. Run Install.cmd. For a custom Steam library:
   Install.cmd "D:\SteamLibrary\steamapps\common\Warrior Cats Clans of the Forest"
3. Start the game and load an offline campaign.
   P: native pause menu. F6: Clan Tools. Controller: Y / Triangle in pause.
   F7: Controls. F8: Frame Rate. Both also appear through native settings.
   Arrows / D-pad / left stick navigate. Enter / A (Cross) selects; Backspace /
   B (Circle) goes back. 1 / 2 or LB / RB switches tabs. On-screen menu hints
   follow your current bindings; each tool also explains its specific actions.
   All mod interface text is English. Native fonts, portraits, buttons, sounds,
   backgrounds and your current clan emblem load from your installed game.

Windows PowerShell 5.1 or newer is required. Launchers set execution policy only
for their own process. The installer checks the exact game executable and refuses
other builds. Existing settings, other mods and an identical UE4SS loader remain.
A different existing loader is preserved and installation stops. Nothing downloads.
For a read-only installation check:
 powershell.exe -NoProfile -File Install.ps1 -GameDirectory "YOUR GAME FOLDER" -ValidateOnly

FEATURES
- Player skins: Appearance > Your cat / Skins. Shared named library with portraits,
  favorites, rename, delete, import/export and all/coat/eyes/shape previews.
  Apply uses the original editor; Cancel preserves your current appearance.
  In the original new-player creator, F6 / Y opens the same shared skin library.
  Name, clan, rank and progression are never copied. Accessories/scars are excluded.
  Export writes skin-export.json; place a shared JSON at skin-import.json and choose
  Import skin, or use the external Clan Loader app for file selection.
- Sky / lighting: Photo tools > Automatic / Day / Night. Native visual presets
  during offline exploration, applied after closing menus. Resets for combat or
  scene transitions. No simulated clock or dynamic weather is added.
- Party: zero, one or two living clanmates; saved party presets; story restoration.
- Exploration followers: native nearby name/rank, Follow/Stay/Regroup, distance.
  Companions use separate staggered positions along your recent route, local
  separation, smoother arrivals and stable positions while you turn in place.
  Their capsules retain wall/terrain collision but do not push other pawns.
  Each companion has its own randomized idle-break timing, renewed after native
  animation cycles and stops, so nearby cats do not share a fixed idle rhythm.
  Navigation tries the native pathfinder first; terrain without navigation can
  require a direct route, so followers may wait behind obstacles. No forced
  teleporting. They suspend in dens, combat and unsuitable locations.
- Clan cats: native appearance editor, original randomization, free name entry,
  generated names, cosmetic presets/copy/restore and original/edited comparison.
  Hold Q / E or the right stick to rotate the preview, including while paused.
  Tab / Y (Triangle) switches between editor controls and the bottom actions.
  R / X (Square) randomizes; Apply saves, Cancel discards the preview.
  Aliases appear on supported NPC labels, dialogue headings, combat character
  labels and pause party slots. Some native lists and authored text retain names.
- Item feedback: actual consumption, remaining count, resource change and sound.
- Offline admin: flight, noclip, speed, heal, invulnerability, item/enemy spawns,
  owned-spawn cleanup, XP, profile-wide individual move unlocks, attributes,
  damage multiplier/one-hit, infinite stamina and native training encounters.
- Flight: native horizontal movement and camera bindings; V / RB (R1) ascend,
  B / L3 descend. Release movement to brake. Conflicting remaps are reported.
  Horizontal orbit remains available in flight through arrows / right stick,
  with your remapped yaw bindings and invert-X setting. Native pitch, zoom,
  camera smoothing and obstacle arm remain active.
- Ignore Enemies suppresses ordinary roaming detection and proximity encounters.
  Scripted story battles are unchanged. Disabling near enemies waits until you
  move clear before restoring their detection components.
- Travel: original world map F9 / L3 previews the selected point; press again
  to confirm. Move the map's native cursor with keyboard/controller. Destinations
  require loaded safe ground and clear space; invalid points show a reason.
  Return travel, named destinations and personal named waypoints are included.
- Inventory: searchable 52-item consumable/material catalog, quantities, bundles,
  native icons, capacity/count checks and confirmation.
- Clan upkeep: fresh-kill fill/lock, bond edits/restore and quest completion.
- Den crafting: 1x/2x/5x/10x/Instant and complete current projects. Normal material
  rules remain; timer acceleration applies while inside the den.
- Den workshop: F6 > Den crafting > Craft any item. Browse 60 decorations,
  25 consumables, 27 materials, six fresh-kill types and 71 accessories, with
  native icons, search, categories and quantities from 1 to 99. Enter your den
  to craft. Cost: Materials uses the original decoration recipe; Cost: Free
  consumes nothing. Supplies/accessories have no original recipe and require
  Free mode. Review counts and costs before confirming; a backup is made first.
  Decorations are ready immediately in the game's decoration inventory. Use
  Place at a compatible den spot. Original placement/space restrictions apply.
  Quest tokens and empty accessory slots are not craftable items.
- Den layout: move/rotate/duplicate completed decorations; preview, Apply,
  Cancel and Undo. Layouts are stored by Clan Tools; copies have no collision.
- Photo tools: original photo mode with FOV, roll, hide UI/names and freeze cats.
  Settings apply only during photo mode; changed runtime state restores on exit.
- Keyboard/controller binding editor, conflicts/reset; custom/unlimited FPS and
  optional counter. VSync may still cap output. Favorites and dark/light themes.

Permanent progression, inventory and cosmetic actions use confirmations/backups.
Move unlocks are profile-wide. The game may recalculate attributes on level-up.
One-hit preserves misses and zero-damage effects. Training uses the native Spar
rules. Temporary admin toggles reset on campaign/scene transitions.

BACKUPS / UPGRADE / REMOVAL
Installation, disable and uninstall back up ClanTools and SaveGames under
%LOCALAPPDATA%\ClanTools\Backups. Upgrades preserve names, presets, favorites,
waypoints, layouts, bindings, settings and backups. Only manifest-owned program
files and four static data catalogs are replaced. Failed installs roll back.
Save and close the game before Disable.cmd or Uninstall.cmd. Uninstall leaves
modified files, personal state, other mods and UE4SS. An older manual installation
without a receipt should use Disable. Removing the mod does not undo game-save
changes such as item grants, XP or quest completion.

To restore a save, close the game, archive the current SaveGames folder, and copy
the chosen backup's SaveGames contents to %LOCALAPPDATA%\Wrc\Saved\SaveGames.
Coordinate any Steam Cloud conflict with that choice. Installers never restore
saves automatically. Keep independent backups outside Steam Cloud.

The included UE4SS prerequisite is v3.0.1-1181-g83330635 (MIT license included).
Fresh-install settings disable the unused HookInitGameState to avoid the observed
GameMode-default discovery startup failure. Existing loader settings are retained.

PACKAGE CONTENTS
Original mod Lua/native bridge source, interoperability identifiers/labels,
installer and licensed loader only. No game executable, cooked art, decompiled
game source, personal saves, debug commands, runtime mailboxes or user state.
See SOURCE-MANIFEST.txt and manifest.json. Include release/build, reproduction
steps and reviewed log excerpts when reporting issues.
