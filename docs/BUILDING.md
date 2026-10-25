# Building and testing

Run commands from the repository root on Windows x64. A game installation is not needed for compilation or isolated tests. Live menu/gameplay checks and the original-theme extraction test require the supported game build.

## Prerequisites

- Zig 0.15.2, the tested native compiler: https://ziglang.org/download/
- Node.js for executable-section auditing.
- Lua 5.4 for standalone Lua tests.
- Windows PowerShell 5.1 and .NET Framework 4.x/WPF for the external manager.

The build does not download dependencies, install mods, or modify your game. Native binaries, local test output, and release archives are ignored by Git.

## Compile

```powershell
./scripts/Build.ps1 -ZigPath 'C:/Tools/zig/zig.exe'
```

This builds the 14 native bridges, recompiles them independently for an executable-section comparison, generates a local native selection manifest, builds the GPL ooz helper from its included source, and compiles the external manager and icons. Only the linker `.buildid` section is excluded from the native comparison.

The comparison verifies that the two builds match. It does not prove live gameplay safety or compatibility with an untested game build. The checked-in release notes describe the acceptance of the originally published candidate.

## Tests

```powershell
./scripts/Test.ps1 -LuaPath 'C:/Tools/lua/lua.exe' -ZigPath 'C:/Tools/zig/zig.exe'
```

Run `Build.ps1` first because the package dependency tests expect generated DLL names. The test script runs standalone Lua suites, installer/manager filesystem fixtures, dependency checks, and isolated native harnesses. Fixtures are created under the ignored `analysis` directory. They do not access a running game or your saves.

For an installed-game theme check, run:

```powershell
powershell.exe -NoProfile -File mods/ClanLoader/tests/theme.test.ps1 -GameDirectory 'C:/Your Steam Library/steamapps/common/Warrior Cats Clans of the Forest'
```

That test reads supported artwork blocks, checks cache behavior and original font families, and confirms that mismatched source hashes are rejected. It writes only to the local theme cache and test fixtures.

## Package a local candidate

Obtain the pinned UE4SS runtime from the published release package. The `ClanTools/loader` folder contains `dwmapi.dll` and the `ue4ss` subfolder. Pass that folder explicitly:

```powershell
./scripts/New-Release.ps1 -Version '0.3.0-local1' -UE4SSDirectory 'C:/Downloads/ClanLoader-0.3.0-rc3/ClanTools/loader'
```

The packager checks the pinned UE4SS DLL hashes and includes its license. It uses explicit allowlists and refuses to overwrite an existing release directory. The complete installer bundle appears under `dist/ClanLoader-0.3.0-local1.zip`.

Keep development builds local until the affected features pass live acceptance. Use an isolated test save, record the actual tested game build, and preserve previous release notes rather than claiming old validation for new behavior.

## Source scope

No game executable, decompiled game source, save, extracted asset payload, or private investigation output belongs in this repository. Native adapters and catalogs contain only the information needed for interoperability. The manager's theme recipe stores verified offsets and hashes, not the original artwork or fonts.
