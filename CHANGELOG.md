# Changelog

Player-facing history for LLM NPC Companions System. Published releases and development builds are labelled separately. Version numbers follow the original packages: the release before 0.5 is **0.30.9**.

## 0.5.0: September 24, 2026

Horde battles, first-person POV, companion colours and relationship management, with the following improvements since 0.30.9. This release includes the corrected Horde AI and melee-weapon setup.

[Release and downloads](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/tag/v0.5.0)

### First-person camera

- Added an optional first-person viewpoint in Settings, with native cameras retained for dialogue and cutscenes.
- Kept the viewpoint active when opening single-character or group text and voice chat.
- Adjusted camera placement and player-component visibility to address head, hair and body clipping while moving or looking down. Original visibility is restored when leaving first person.

### Horde battles

- Added ten curated wave types with varied enemies and bosses, a starting-wave selector on the right panel, and random later themes without repeats. Enemy counts grow by round, independently of the chosen theme.
- Added settings for starting enemies, enemies added per level, number of levels, bosses per level and rest time between waves.
- Saved the starting-wave choice between runs and placed Start horde directly below its selector. The configured level count is the total number of rounds, even when starting with a later theme; themes do not repeat within a run.
- Prepared waves before releasing enemies into combat, with recovery and omission of individual missing AI attachments instead of blocking the entire wave.
- Kept defeated bodies on the ground between waves. Missing enemies are not counted as kills.
- Closed the menu when a wave is ready and made Esc from Horde or Settings return directly to gameplay.
- Added a rest countdown that gives way to conversation subtitles.
- Improved wave-list wrapping and spacing, pause-message restoration on resume, and handling of a reset game clock.
- Fixed Horde melee hits dealing no damage by registering inventory and natural weapons with each enemy's native AI equipment system. Normal enemies and companion damage protection are unchanged.

### Companion appearance and roster

- Added eye, hair and armour colour choices, expanded to 33 shades with more vivid colours.
- Replaced the initial appearance controls with arrow selectors, improved alignment, and selected the first character when opening the menu.
- Captured colours for each summon separately. Changing a preset or restoring original colours affects future summons; existing copies retain their choices through recovery and travel.
- Removed the unreliable clothing-colour control.
- Expanded the Characters list from 15 to 21 entries and the combat-only catalogue from 86 to 101 definitions. Non-fighting character entries receive protection while travelling.
- Added conversation profiles and multilingual mappings for the expanded talking roster.

### Conversations, relationship management and memories

- Added relationship management with Anca and Lacra through separate conversation profiles, each with Auto, On and Off choices. Auto follows detected story history; explicit On and Off selections take precedence.
- Added mutual awareness and distinct, teasing romantic banter when both romances are confirmed and both characters participate in group chat.
- Adjusted Anca's romantic speaking rules to reduce repeated pet names such as “my love.”
- Changed group chat into a reply chain: your message goes to the first speaker, that reply goes to the second, and the second's reply goes to the third. Later replies can prepare while earlier audio plays.
- Added recent battle context with observed opponents, participating companions and Horde-wave outcomes. The opponent list is captured once at encounter start and supplied to conversations after combat or a wave ends, including rest periods.
- Preferred the game's character display names over catalogue labels in battle context, with speaking instructions to name opponents instead of calling them a generic boss.
- Kept recent battle observations separate from permanent quest history and cleared them on save/world changes.
- Simplified playback to centred character voices with gentle distance-based volume, removing directional audio processing.
- Removed experimental romance-cutscene playback. Romance profiles change conversations, not quest completion or scene playback.

### Following and recovery

- Added attention from settled followers without requiring the player to look at them. The two closest nearby companions look directly toward Coen; others face roughly toward him with a slight side angle. Native animation handles turning, and movement or combat releases the attention.
- Tightened arrival formations and gaps between companions, including smaller parties, while preserving body-size clearance and settled positions during nearby approaches.
- Improved final stopping destinations and offscreen locomotion so companions do not depend on being visible to follow.
- Corrected off-screen animation scheduling for the driving mesh of each owned companion. The game's global animation budget and other characters remain unchanged.
- Stop the formation path once a companion reaches its arrival area, with a wider tolerance before restarting. This addresses small repeated steps and shuffling after following, including the active path observed on Ambrus near his assigned position.
- Added running-speed matching through private companion movement profiles, with normal pace restored as they catch up or leave travel behaviour. Shared enemy movement assets are unchanged.
- Extended the speed boost to distant followers even when Coen slows or stops, tapering it as they catch up. Widened spawn and follow gaps after the tighter formation caused crowding.
- Gave moving followers more opportunity to catch up on foot before using distant recovery.
- Stopped carrying the previous summoned party and queued summons into a loaded save. Fast-travel recovery remains separate.
- Fixed character-loading timeouts after save reloads by checking cached object identities and clearing asset caches on save/world resets. Failed loads report their loading stage instead of a generic adapter error.
- Set automatic recovery for defeated companions to 3 seconds after combat, without a recovery toggle.

### Menu, input and performance

- Updated support to Dawnwalker Mod Menu 1.0.7 or later and repaired menu opening with its exposed text-wrapping property.
- Improved appearance-control arrows, text spacing, button alignment and selection behaviour.
- Added helper recovery when Windows permission differences prevent F5–F9 shortcuts from reaching the game.
- Serialised application updates and reduced background work with an empty party. Battle context does not continuously rescan opponents throughout a fight.
- Updated the mod title to LLM NPC Companions System and expanded the player guide, settings descriptions and installation information.

## 0.4.0: development milestone, incorporated into 0.5

- Began companion appearance customisation and expanded the character roster and conversation profiles.
- Added the first versions of the first-person camera, Horde mode and romance-profile selection.
- Refined native menu controls and hidden helper startup.
- Experimented with clothing tinting and romance-scene playback. Both were removed before the current feature set; they are not supported features.
- This milestone did not become a separate supported public release. Its retained features are documented under 0.5 above.

## 0.30.9: published release

- Fixed repeated UE4SS errors and heavy stuttering after reloading a save, including when companions had already been dismissed.
- Made native protection cleanup tolerate game objects and effect handles that had already expired during save/world teardown.
- Included the fix in Runtime, requiring matching Scripts and Runtime packages when updating.
- Added an optional multilingual pack for 26 conversation profiles with new character IDs and voices supporting 25 languages. The original English voices remained the default. New profile IDs start separate conversation histories.

[Release and downloads](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/tag/v0.30.9) · [Installation notes](docs/RELEASE-0309.md)

## 0.30.8: published release

- Improved character voice clarity by removing the hollow, grainy quality of the earlier audio setup across text, microphone and group conversations.
- Retained directional playback and distance volume in this release; the later move to centred playback is part of 0.5.
- Provided ready-to-copy Complete, Scripts and Runtime packages, plus source code, without requiring npm commands or a Convai account.
- Added automated GitHub release builds and a more player-friendly README with installation links and a gameplay video preview.

[Release and downloads](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/tag/v0.30.8) · [Installation notes](docs/RELEASE-0308.md)

## 0.30.7: release-preparation build

- Prepared player packages and public source documentation.
- Added the Help page's Copy logs support report with sensitive values removed.
- Configured normal play without the UE4SS debug console and documented installation, customisation and the mod's internal structure.

## 0.30.6: development build

- Reduced stalls while queuing companions by budgeting loading work and background menu updates.
- Kept browsing and additional summon requests responsive while earlier characters loaded.

## 0.30.5: development build

- Added source-filtered protection against companion gameplay effects and strengthened companion allegiance handling.
- Improved native combat exit and cleanup to reduce repeated combat lines and unwanted hostility.

## 0.30.4: development build

- Restored native menu operation after incompatible changes.
- Reworked tuning around owned companions and added travel recovery handling.

## 0.30.3: development build

- Separated character selection from summoning, with explicit Summon and Dismiss buttons beside the description.
- Improved retention of native click events and loading feedback while queuing multiple characters.

## 0.30.2: development build

- Aligned menu rows and the footer, improved category layout and made respawn timing automatic rather than another player setting.

## 0.30.1: development build

- Corrected native menu layout and Escape navigation.
- Added configurable keyboard shortcuts through the Controls page and a settings file.

## 0.30.0: development baseline

- Moved the companion interface into the native game menu for game 1.05.
- Included talking characters and combat-only creatures, native following and combat, configurable companion damage and attack frequency, automatic recovery, and the text/voice conversation helper.

## Earlier prototypes

Before the versioned source baseline, development established Lua facial animation, Convai text and voice responses, subtitles, character identification, group chat, quest and world context, companion summoning, formations and native combat integration. These were iterative local prototypes rather than separately supported public releases. Their individual version notes are incomplete, so this history groups them here rather than inventing release details.
