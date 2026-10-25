# Architecture

## Components

UE4SS provides the runtime mod-loading foundation. Clan Loader adds a package installer and a Mods screen built from the game's native menu widgets. Clan Tools supplies the gameplay features. We do not maintain a replacement engine loader.

The external manager is C# hosting Windows PowerShell 5.1 with WPF/XAML. Its package logic is separate from the visual interface so installation and removal can be tested with filesystem fixtures. Game fonts and textures are read from exact hash-verified blocks into a local cache. The icons are vector emblems exported to PNG and ICO.

In-game modules are Lua scripts running through UE4SS. They coordinate menus, selections, state validation, and native bridge calls. Build-specific C DLLs expose the operations that need native access. They validate supported signatures and object state before touching the game. A compiled DLL is not a standalone installable feature by itself.

## Repository boundaries

- `mods/ClanLoader` owns the package format, external manager, and native Mods screen.
- `mods/ClanTools` owns gameplay modules, shared native UI, catalogs, and C bridges.
- `mods/ClanParty/native/bridge.c` is the existing party bridge used by Clan Tools. It is retained at its current path for build compatibility, not offered as another public manager.

These components share one repository for coordinated fixes, tests, and versioned release bundles. The package format already gives Clan Loader and Clan Tools separate IDs and versions. Future independently maintained mods can be added as sibling packages without splitting this repository immediately.

## State and persistence

Program files live in `Scripts`, `bin`, and `data`. Mutable state such as skins, presets, aliases, waypoints, and preferences stays outside those owned program paths. Updates preserve personal state and next-launch enablement. Removing a mod preserves modified owned files rather than silently deleting them.

Loaded native patches are not hot-unloaded. Enable/disable changes require a restart. The game installation and game saves are never treated as source files for this repository.

## Distribution

Source code lives in Git. Ready-to-run ZIPs are attached to GitHub Releases. Release candidates remain marked as prereleases. Their manifests record SHA256 hashes for installed program files. The manager checks exact game-build compatibility and refuses unsupported binaries or conflicting bootstrap files.
