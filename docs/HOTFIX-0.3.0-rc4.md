# Loader startup and idle-work investigation

Local candidate: `0.3.0-rc4-local1`, 2026-10-25. Not published.

## Confirmed problems and changes

- The executable used a default PowerShell runspace, so opening the EXE could
  still fail under a Restricted execution policy. Its runspace now explicitly
  permits the bundled scripts for that process. CurrentUser and LocalMachine
  policies are unchanged; organization-managed Group Policy still takes priority.
- Map travel acquired a fresh campaign snapshot on every 16 ms callback even
  with the map closed. Inactive discovery now runs once per 16 callbacks. Once
  active, input, preview expiry and campaign checks retain their original cadence.
  Discovery can take about 256 ms at normal frame rates, and longer at low FPS.
- Native cat labels parsed the whole game save and scanned widget classes even
  when no cats had been renamed. A cached, profile-scoped override check now skips
  that work. Removing an alias still restores the original owned caption.
- Default photo extensions no longer acquire campaign state or discover photo
  widgets. Turning off the last extension still restores owned state immediately.
- Disabled or unverified followers no longer acquire campaign snapshots. Pending
  actor cleanup continues to be retried.

These changes remove unnecessary work. They do not establish the cause of every
reported stutter or a measured FPS improvement. Clan Performance 0.1.0 is a
separate graphics-settings package and is unchanged by this candidate.

## Validation

- 75 Lua suites and four PowerShell suites passed using `scripts/Test.ps1` with
  `-SkipNative`. No C sources changed in this hotfix.
- The launcher regression first reproduced failure with the original runspace
  under Restricted policy. The production runspace then loaded a downloaded-file
  marked script and its dot-sourced helper, preserving `$PSScriptRoot` and leaving
  persistent and parent-process policies unchanged. Managed-policy environments
  were not modified or simulated by this fixture.
- In 160 simulated inactive map callbacks, snapshot calls fell from 160 to 10.
  The same test checks fresh safety checks during active input and shutdown.
  This is a call-count result, not a frame-rate benchmark.
- Additional regressions cover cached override checks, profile changes, original
  caption restoration, default photo inactivity and retrying follower cleanup.
- All 14 packaged native binaries matched fresh recompilations in their
  production PE sections. Only linker build identifiers differed.
- The candidate external loader opened with the original theme, detected the
  Steam installation and listed installed mods. Package installation succeeded
  with a program backup; a separate save backup was taken before live testing.
- On Steam build 24847281, the separate admin test character loaded. The original
  map displayed the travel hint and F9 produced a destination preview. Closing
  the map removed that preview without teleporting. F6 opened Clan Tools with
  its native roster and portraits. The test game then closed normally. No Lua
  errors from the affected routines appeared in the session log. All installed
  Clan Tools program hashes matched the candidate manifest.

## Remaining investigation

The affected users' hardware, enabled features, game/loader versions and precise
stutter timing are still needed. Compare the same location, camera, resolution
and frame cap after warm-up. Separate asset-loading pauses from recurring hitches.
Compare Clan Tools enabled and disabled with a game restart between runs, retaining
the same other mods and graphics settings. Do not infer improvement from unrelated
FPS screenshots, menu FPS or a changed frame cap.

If installation still fails, request the exact error, which file was launched,
and the bundle version. Do not recommend changing system-wide execution policy.
