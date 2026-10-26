<p align="center"><img src="mods/ClanLoader/manager/icons/loader.png" width="96" alt="Clan Loader emblem"></p>

# Warrior Cats Clan Tools

Community mods and a mod manager for **Warrior Cats: Clans of the Forest**. Customize your clan, save your cat's looks, manage your party, and explore with offline tools through menus styled to match the game.

**Pull requests are welcome.** Bug fixes, new features, documentation improvements, and compatibility work are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

[Download the release candidate](https://github.com/kyotozx/warrior-cats-clan-tools/releases) · [Report a bug](https://github.com/kyotozx/warrior-cats-clan-tools/issues/new?template=bug_report.yml) · [Suggest a feature](https://github.com/kyotozx/warrior-cats-clan-tools/issues/new?template=feature_request.yml)

![Clan Loader desktop manager](docs/images/loader.jpg)

## In-game gallery

Actual screenshots from the supported game build. The menus reuse the game's fonts, portraits, buttons, and animated backgrounds.

| Party Manager | Clan appearance |
| --- | --- |
| ![Party Manager with clanmate portraits](docs/images/party.jpg) | ![Clan appearance selection](docs/images/appearance.jpg) |

| Player skins | Offline Admin |
| --- | --- |
| ![Saved player skins](docs/images/skins.jpg) | ![Offline admin tools](docs/images/admin.jpg) |

<details>
<summary>Native Mods menu, item feedback, and den crafting</summary>

![Native Mods menu](docs/images/mods-menu.jpg)

![Item-use feedback settings and example notification](docs/images/item-feedback.jpg)

![Den crafting tools](docs/images/crafting.jpg)

</details>

## Compatibility

| Requirement | Supported version |
| --- | --- |
| Platform | Windows x64, Steam |
| Game | Warrior Cats: Clans of the Forest |
| Steam app | `3960600` |
| Game build | `24847281` |
| Status | Release candidate |
| Gameplay tools | Offline campaigns |

The installer checks the game executable before applying changes. Other builds are not supported yet. This is an unofficial project with no affiliation with the game's developers or rights holders.

## Install

1. Download `ClanLoader-0.3.0-rc4.zip` from [Releases](https://github.com/kyotozx/warrior-cats-clan-tools/releases). Use this package, rather than GitHub's automatically generated source archives.
2. Save and close the game. Extract the entire ZIP to a writable folder.
3. Open `ClanLoader.exe`. Check the detected game folder, then select **Install / update suite**.
4. Start the game. Open **Mods** from the main or pause menu. In an offline campaign, open **Clan Tools** from pause.

The package includes the tested UE4SS runtime. Python and a separate mod loader download are not required. The external app handles packages, updates, removal, skin imports, and backups. The in-game menus provide the gameplay tools.

Game textures and fonts are loaded from your own installation. They are not included in this repository or the release package.

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Mods menu | F10 | R3 |
| Clan Tools from pause | F6 | Y / Triangle |
| Navigate | Arrow keys | D-pad / left stick |
| Select | Enter | A / Cross |
| Back | Backspace | B / Circle |
| Switch tool tabs | 1 / 2 | LB / RB |

On-screen hints explain tool-specific actions and reflect supported remaps. All mod interface text is in English.

## Features

| Tool | What it does |
| --- | --- |
| Party Manager | Choose up to two living clanmates, remove forced companions, save party presets, and restore the story party. |
| Exploration followers | Follow, stay, and regroup controls, nearby name/rank labels, smoother spacing, and independent idle timing. |
| Clan appearance | Use the native appearance editor, rotate and randomize cats, edit names, generate names, and save cosmetic presets. |
| Player skins | Save, preview, favorite, and share looks. Reuse a saved look in the original new-player creator without copying progression. |
| Item feedback | See consumption, remaining quantity, actual health/stamina changes, and hear feedback. |
| Offline Admin | Flight, noclip, speed, healing, invulnerability, item and enemy spawning, XP, move unlocks, damage controls, and infinite stamina. |
| Travel and exploration | Choose a destination on the original map, save waypoints, return to previous positions, and suppress ordinary enemy detection. |
| Clan upkeep | Fill or lock the fresh-kill pile, edit bonds, and complete quests. |
| Den crafting | Accelerate crafting timers or finish projects. Craft supported decorations and inventory items with a free option. |
| Den layout and photos | Preview decoration changes, use layout tools, adjust photo settings, and choose native day/night lighting presets. |
| Settings | Edit keyboard/controller bindings, set a frame-rate limit or unlimited FPS, and enable an FPS counter. |

Some actions change saved progression. Read the confirmation shown by the tool and keep backups. See the [full feature guide](mods/ClanTools/release/README.txt) and [validation notes](mods/ClanTools/release/VALIDATION.txt) for tested behavior and limitations. Day/night is a lighting override, not a simulated clock or weather system. Map travel needs valid loaded ground. Story battles are not disabled by Ignore Enemies.

## Mods and packages

Clan Loader adds package management and a native Mods menu on top of UE4SS. It checks package paths, declared files, hashes, dependencies, and game-build compatibility. It does not sandbox executable mod code.

Changes to enabled mods take effect on the next launch. The current release has no automatic updater, online mod catalog, or Steam Workshop integration. Compatibility with other community managers has not been established.

Want to make a mod? Start with the [package format](mods/ClanLoader/DEVELOPERS.txt) and the [architecture guide](docs/ARCHITECTURE.md).

## Project layout

```text
mods/
  ClanLoader/
    Scripts/       Native in-game Mods menu
    manager/       External Windows manager and original emblems
    tests/         Loader and package tests
  ClanTools/
    Scripts/       Gameplay features and native menu integration
    native/        Build-specific C bridges
    data/          Static interoperability catalogs
    release/       Installer, package rules, feature and validation notes
    tests/         Lua, native, and installer tests
  ClanParty/
    native/        Shared party bridge retained under its original path
scripts/           Build, audit, and test entry points
docs/              Development and project documentation
```

The loader and tools share one repository so related changes can be reviewed together. They remain separate installable packages. Individual Clan Tools features currently share runtime state and native UI code, so they are modules within the suite, not separate installable mods.

## Development and contributions

Read [BUILDING.md](docs/BUILDING.md) for prerequisites and build commands. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR. You can help with reproducible bug reports even without a development setup.

![Clan emblems](docs/images/clan-emblems.png)

## Credits and license

**Credits: kyotozx**

Original project code is available under the [MIT License](LICENSE). Third-party components keep their own licenses. UE4SS is MIT licensed. The separate ooz decompression helper is GPL-3.0-or-later and includes its source and notices. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Game names, assets, and related intellectual property belong to their respective rights holders. No permission to redistribute game assets is granted by this project's license.
