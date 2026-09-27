This update adds ten interface languages, native subtitles above speakers, better quest and battle context, and support for Rideable Mount Companions.

## What's new

- Choose English, Simplified or Traditional Chinese, Spanish, Brazilian Portuguese, French, German, Russian, Japanese or Korean for the interface. Conversation voices are selected separately.
- Native overhead subtitles advance in short spoken phrases. Beast captions account for the creature's scaled body.
- Conversations receive the tracked quest and revealed active objectives. Exploration replies also receive relevant journal context and the preceding observation line. The persistent family objective is excluded from this temporary activity context.
- One companion can comment at combat start and after combat ends. Closing remarks can combine the fight, Coen's immediate observation and collected loot. The ten-minute cooldown starts after combat; loading a save resets reaction cooldowns.
- The separate [Rideable Mount Companions](https://github.com/alystria-ai/Rideable-Mount-Companions/releases/latest) addon reuses this mod's conversations, audio, subtitles, context and creature commands.

## Fixes

- Fixed fresh launches losing F5 and other shortcuts when an older loader omitted a required Lua module.
- Fixed missed automatic replies during microphone and connection transitions, and retained closing comments through pause-menu use.
- Ignore brief creature spawn-time combat flags when no hostile opponent was observed.
- Improved beast spacing and resting positions. Small steps and camera turns no longer request a new formation position for a settled beast.
- Shared first-person camera settings and body masking with ridden creatures, and improved creature replacement and control cleanup.

## Settings and defaults

All settings are optional. Restore backed-up configuration files after updating to retain saved preferences.

| Setting | Default | Purpose |
| --- | --- | --- |
| Interface language | Auto | Follows the game language when supported, with a manual language selector. |
| Subtitles above speakers | On | Native overhead captions. Off uses the regular conversation HUD. NPC subtitles and Hide chat boxes still control text visibility. |
| React to battles | On | One opening and one closing comment, followed by the cooldown. |
| React to Coen's observations | On | Replies to solo exploration observations with context and a three-minute minimum gap. |
| React to collected loot | On | Occasional comments on pickup batches; storage withdrawals stay silent. |

First-person mode, Auto-loot, Fast travel from anywhere, Spend skill points anywhere, Day and night abilities, and Passives without slots remain Off by default. Horde and Nightmare runs start only when requested. The mount addon is optional.

## Installation

Close the game. Extract **Complete**, or **both Scripts and Runtime for 0.5.5**, into the game installation folder, merging the included `Dawnwalker` folders. Neither split ZIP works alone: Runtime also contains configuration and enablement files.

Requires **The Blood of Dawnwalker 1.05**, **UE4SS for Dawnwalker 1.2.1 RC6**, and **Dawnwalker Mod Menu 1.0.7 or later**. Back up `config.ini` and `keybindings.ini` and restore them after updating to retain preferences. Keep generated conversation data. Reapply the matching optional **Multilingual** pack after updating.

No Convai account, API key setup or command-line commands are needed. Source is for developers. Rideable Mount Companions uses this Runtime and needs no second helper.

[Player guide](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker#readme) | [Full changelog](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/blob/main/CHANGELOG.md) | [YouTube channel](https://www.youtube.com/@AlystriaAI)
