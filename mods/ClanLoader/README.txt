CLAN LOADER + CLAN TOOLS
See bundle-manifest.json and ClanTools/manifest.json for the bundled versions.

Unofficial community mod suite for Warrior Cats: Clans of the Forest.
Windows x64, Steam app 3960600, game build 26184573 only.
Local release candidate, prepared for community testing. Not published to Steam
Workshop and not an official Workshop subscription manager.

GET STARTED
1. Save and close the game. Extract this entire ZIP to a normal writable folder.
2. Open ClanLoader.exe. The installed Steam game should be detected automatically.
   Otherwise choose the folder containing Wrc, not Wrc/Binaries/Win64.
   Use the EXE rather than opening Manager.ps1 directly. The EXE configures its
   own PowerShell session; it does not change your Windows execution policy.
   Organization-managed policies still apply. If blocked, share the exact error,
   the file you opened and the version from bundle-manifest.json.
3. Select Install / update suite. Nothing is downloaded. The bundled UE4SS
   bootstrap and native in-game Mods menu are installed with Clan Tools.
4. Start the game. Open its main or pause menu and use Mods [F10 / R3].
   Arrows / D-pad choose, Enter / A (Cross) selects, Backspace / B (Circle) returns.
   In a loaded campaign, F6 / Y (Triangle) in pause opens Clan Tools.

The in-game interface uses the game's own fonts, buttons and animated background.
The external app handles installation, package updates, removal and recovery.
All mod text is English. No game art, fonts, saves or decompiled source are bundled.
Native assets are referenced from each user's installed game.
The external manager reads verified original textures and fonts into a local
cache under %LOCALAPPDATA%/ClanTools/ThemeCache. Its dark theme is fixed.
The icons folder contains SVG and PNG clan emblems for the loader and tools,
using the blank clan silhouette supplied by kyotozx and custom central symbols.
Credits: kyotozx

PLAYER SKINS
Load your cat, then F6 > Appearance > Your cat / Skins.
Save the current look with a name. The shared library supports genuine rendered
portraits, favorites, rename, delete, preview and applying all/coat/eyes/shape.
Applying opens the original appearance editor: Apply commits, Cancel discards.
Name, clan, rank, XP, quests and inventory are not copied by a skin.
To create another player cat with the same appearance, choose an empty save slot,
select a clan, and use Skins [F6 / L3] in the original appearance creator. Select a
saved look, continue editing, then finish the original creator normally.
Skins do not copy accessories/scars. The original creator still owns the new save.

SHARING SKINS
In the gallery, select a skin and choose Export skin. In the external manager,
Export prepared skin saves that JSON to a location you choose.
Import skin in the external app stages a compatible JSON; choose Import skin in
the in-game gallery to add it. Skin files contain only a label and cosmetic values.
There is no executable code in the supported skin format. Maximum 128 saved skins.
Personal library: Wrc/Binaries/Win64/ue4ss/Mods/ClanTools/skins.json.

SKY / LIGHTING
F6 > Offline admin > Photo tools > Sky / lighting: Automatic, Day, Night.
Uses authored native lighting presets during offline exploration. Applies after
closing menus and resets during combat or scene changes. Automatic restores the
game's zone lighting. This is a visual override, not a clock or dynamic weather.

MOD PACKAGES
Install mod package accepts a ClanLoader ZIP with mod.json at its root. Package
hashes, build, dependency IDs and paths are checked before installation. Mods
contain executable code; install packages only from authors you trust.
Install/update/removal require the game closed. The in-game manager writes only
next-launch preferences; loaded Lua and native patches are never hot-unloaded.
A star means a restart is required. Open settings is available in a loaded
campaign for Clan Tools. The manager's own toggle stays locked inside the game.

RECOVERY / REMOVAL
Open the external app with the game closed, select a mod, and disable or uninstall
it. Disable dependent mods first. To remove this suite, uninstall Clan Tools,
then Clan Loader. Personal state, other mods, modified files and UE4SS remain.
If a mod prevents startup, edit ue4ss/Mods/mods.txt while the game is closed and
set its line to ModId : 0. Start with ClanTools : 0 to isolate suite issues.
Backups are under %LOCALAPPDATA%/ClanTools/Backups (Open backups in the app).
Restoring old saves is a separate, explicit choice; installers never roll saves
back automatically. Removing mods does not reverse saved XP/items/quest changes.
The bundled standalone ClanTools/Install.cmd and Uninstall.cmd remain available.

Windows PowerShell 5.1 / .NET Framework are used by the external GUI. Installation
requires write access to the chosen game folder. No administrator prompt is
requested. Unsupported game builds or conflicting bootstrap files stop installation.
Read ClanTools/README.txt for the full existing feature list and
ClanTools/VALIDATION.txt for tested behavior and remaining coverage limitations.
See DEVELOPERS.txt for the package format and example/ for a minimal Lua mod.

LICENSE / CONTENTS
Original mod scripts, bridge source, manager source and a licensed UE4SS bootstrap.
UE4SS license/notices: ClanTools/loader/ue4ss/LICENSE and
ClanTools/THIRD-PARTY-NOTICES.txt. No permission for game assets is implied.
The standalone texture decoder uses ooz (GPL-3.0); its license, notice and
complete helper source are in theme-tools/. It does not include a proprietary
Oodle DLL. See theme-tools/NOTICE.txt for the rebuild command.
bundle-manifest.json lists every shipped file and its SHA256.
