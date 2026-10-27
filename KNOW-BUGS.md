Status for rc11, October 26, 2026.

- Downloaded theme DLL: fixed in rc11. Windows could block `ThemeAssets.dll` with error `0x80131515` on startup. The loader now removes the download marker from its bundled theme helper automatically, without changing system execution policies.

- Manual package import: fixed in rc10. "Add mod package" still checked the old executable hash in rc7 through rc9, rejecting Performance and other packages on the supported game build. Open the rc10 desktop loader to import packages; updating the in-game mods alone does not update an older desktop copy.
- Windows ZIP paths: fixed in rc10. Packages created with Windows path separators, including the published Performance ZIP, are now accepted. Undeclared files, duplicate paths and traversal paths are still rejected.

1. Rename Apply crash: fixed the unavailable button template and removed the unnecessary native appearance refresh for name-only edits. A local Rename / Apply test passed. Reports on other saves still need confirmation.
2. Save loading and switching: reproduced in rc7 and corrected in rc8. The selected character was being read from FlowManager instead of GameConfig, silently returning slot 0 for other characters. Two distinct campaigns passed a ThunderClan → WindClan → ThunderClan test without restarting: correct player names, 24/22 clan rosters and matching native cat data. A renamed cat retained its name in the correct campaign after returning. Confirmation on affected players' installations is still welcome. Older party settings, party presets and display names are preserved but not reused because their character ownership is uncertain. Game saves and saved skins are unaffected.
3. Character creation shortcut conflict: fixed in rc7. Skins now uses F6 / L3, leaving Y / Triangle for the game's confirmation.

Also fixed in rc9:

- Reusing a deleted character slot could inherit its old mod settings. Character-specific names, party selections, party presets, original appearances, den layouts and waypoints now use the game's character identity. Older ambiguous settings remain on disk but are not reapplied. Shared appearance presets and player skins remain available.
- A temporary character-identity lookup failure no longer leaves the Party Manager blocked after loading finishes.
- Mods installed with an `enabled.txt` marker could keep running after being disabled or removed in the manager. Activation handling now accounts for that marker and the exact mod ID spelling used by UE4SS.
- Followers now refresh their appearance when their clanmate is edited. The keybinding editor also reserves the mod menu shortcuts.
