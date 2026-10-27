# Selected-character identity correction

Included in rc8; implemented and tested locally on October 27, 2026.

## Cause

The Lua identity reader registered `ClanToolsCurrentCharacterSlot` at offset `0x154` on `SwtAdventureFlowManager` and read `instance.FlowManager`. The selected-character field actually belongs to `SwtAdventureGameConfig`, available through `instance.GameConfig`.

Reading the wrong object did not fail. It returned zero while the active character was in slot 2. The mod then combined the active ThunderClan campaign with slot 0's Skywing data, showing Skywing and an empty clan roster. Existing tests repeated the same incorrect object model. The two original local characters were copies with the same name and clan, which also concealed the mismatch.

The native appearance bridge already used the GameConfig singleton and the correct field. Its misleading FlowManager variable names and layout token have been corrected. The Lua reader now requires the `CONTEXT_LAYOUT config_slot=340` token, registers the field on GameConfig, checks the object's class and fails closed if identity cannot be established.

## State ownership

Both previous identity readers could assign a character's mod preferences to another slot. Party selections, original-party snapshots, party presets and custom display names now use `character-v2` paths. Earlier files are preserved without automatic migration because they cannot establish which character owns their contents. Game saves and saved skin files are not migrated or reset by this change.

## Local reproduction and verification

A new orange ThunderClan apprentice, Sharppaw, was created through the original character creator in slot 2. The existing Skywing WindClan campaign in slot 1 supplied a distinct second campaign.

Before the fix, the game displayed Sharppaw while Clan Tools reported Skywing and zero clan cats. A one-time diagnostic confirmed GameConfig held slot 2 while the old FlowManager reader returned 0.

After the fix:

1. Sharppaw loaded with 24 ThunderClan cats and the correct player name. Party and Appearance menus displayed cat portraits.
2. Blazepaw was renamed to Blazepawx through Rename and Apply. The operation completed without a crash and wrote the alias under slot 2.
3. Returning to the main menu and loading Skywing, without restarting the process, displayed 22 WindClan cats and the correct player name and portraits. Native validation matched all 22 entries.
4. Loading Sharppaw again restored the 24 ThunderClan cats and the Blazepawx alias. Native validation matched all 24 entries, with no mismatches.

The test save and diagnostic evidence were archived locally. The original user save files were restored and their hashes verified. Temporary polling and runtime inspection were removed from the installed mod.

Regression coverage includes a decoy FlowManager returning zero, several character transitions, missing GameConfig, rejection of the old native token and preservation without reuse of ambiguous legacy state. The full suite passed 79 Lua suites, five PowerShell suites and seven native tests. All 14 native bridges passed the production-section audit.

These results establish the reproduced identity bug and the tested Rename / Apply path. They do not establish that every reported crash has the same cause; logs from affected players remain useful.
