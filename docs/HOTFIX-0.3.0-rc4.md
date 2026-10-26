# Loader startup and idle-work investigation

Release candidate: `0.3.0-rc4`, 2026-10-25.

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
- Completed portraits now update only their image widgets, including duplicate
  appearances of the same cat. They no longer rebuild the whole menu. Replaced
  pages and closed menus cancel pending captures. Completed render targets use
  a 32-entry cache; the private animated capture actor is destroyed when idle.
- Campaign queries follow the engine's current viewport, world, game state,
  possessed player and save manager instead of repeated global actor searches.
  World, ownership, offline state and profile are still checked on every query.
- Parsing the save snapshot is reused only while its exact bytes are unchanged.
  Missing, partial and changed saves invalidate the parse immediately. Clan role
  definitions are indexed once. No cached roster authorizes a mutation.
- The creator reuses the current loop's campaign query; video settings cache the
  engine singleton with validity checks. Empty follower selections, idle inventory
  tools and disabled enemy avoidance skip work when there is nothing to restore.

These changes remove unnecessary work. They do not establish the cause of every
reported stutter or a measured FPS improvement. Clan Performance 0.1.0 is a
separate graphics-settings package and is unchanged by this candidate.

## Validation

- 77 Lua suites and four PowerShell suites passed using `scripts/Test.ps1` with
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
  Clan Tools program hashes matched the first candidate manifest.
- The second pass loaded the same separate test character, generated all eight
  first-page portraits, switched to Appearance with cached portraits and returned
  to the original pause menu and exploration without Lua errors. Additional model
  tests cover duplicate image subscribers, cancellation, cache bounds, world
  changes, direct context traversal and partial save snapshot writes.

## Local profiling observation

An instrumented session on this development PC compared the first idle-work fix
with the additional context and portrait changes, using the same test save and
graphics settings. The first eight-portrait page previously triggered eight full
menu rebuilds. Their combined measured Lua time was 1,143 ms, with a 213 ms maximum
for one rebuild. The containing portrait routine took 1,238 ms in that 10-second
window. After the change it took 58 ms total, with a 23 ms maximum callback; there
were no portrait-driven menu rebuilds. Opening the panel was measured separately.

These are inclusive `os.clock` timings with a temporary local probe, not GPU frame
times or an FPS benchmark. Nested timings must not be added together. The sample
does not reproduce the affected users' machines or establish that every recurring
exploration stutter is fixed. The probe and its logs are excluded from the release.

## Remaining investigation

The affected users' hardware, enabled features, game/loader versions and precise
stutter timing are still needed. Compare the same location, camera, resolution
and frame cap after warm-up. Separate asset-loading pauses from recurring hitches.
Compare Clan Tools enabled and disabled with a game restart between runs, retaining
the same other mods and graphics settings. Do not infer improvement from unrelated
FPS screenshots, menu FPS or a changed frame cap.

If installation still fails, request the exact error, which file was launched,
and the bundle version. Do not recommend changing system-wide execution policy.
