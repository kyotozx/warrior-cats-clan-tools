# Contributing

**Pull requests are welcome.** We welcome fixes, features, documentation, tests, and compatibility improvements.

## Before you start

For a large feature or architectural change, open an issue to discuss the approach first. Small fixes can go straight to a PR. Keep each PR focused on one problem and use clear English for UI text and documentation.

## Local workflow

1. Fork the repository and create a branch for your change.
2. Follow [the build guide](docs/BUILDING.md).
3. Make the smallest complete change that addresses the problem.
4. Run the relevant tests. For gameplay changes, test against the supported game build when available.
5. Open a pull request explaining the behavior before and after, how you tested it, and any remaining limitations.

If you cannot run the game, say so in the PR. Mock tests and source review do not establish live game behavior. UI changes should include a screenshot when practical, with personal information removed.

## Development conventions

- Keep the native game's menu style, keyboard/controller navigation, and readable input hints.
- Keep gameplay mutations offline and on the game thread. Validate object identity, lifetime, signatures, and supported build before native calls.
- Restore temporary state when leaving a mode, changing scenes, or closing a preview.
- Preserve personal settings, skins, presets, and saves during installation and updates.
- Update package allowlists when adding runtime files. Do not include test fixtures or mutable state in release payloads.
- Do not commit saves, account identifiers, logs, credentials, extracted game assets, game binaries, or decompiled game code.
- Use normal punctuation in the README. Do not add em dashes.

## Licensing

Contributions to original project code are submitted under the repository's MIT license. Do not copy code or assets from another project without a compatible license and attribution. Keep third-party license notices intact. The ooz helper is a separate GPL component; changes to it must retain its license obligations.

## Reporting problems

Include the game build, mod version, steps to reproduce, expected behavior, actual behavior, and whether keyboard or controller was used. Mention other installed mods. Prefer a short relevant log excerpt after removing personal paths and account information. Do not upload your full save or installation by default.
