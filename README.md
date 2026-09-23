# LLM NPC Companions System for The Blood of Dawnwalker

Build your own travelling party in Vale Sangora. Summon characters to follow you and fight alongside Coen, talk to them beyond their scripted dialogue, customise their appearance, and take on waves of enemies together. No Convai account or command-line setup is needed.

## Features

- Text and microphone conversations with nearby supported characters, voiced replies, subtitles, facial animation and gentle distance-based volume; talk privately or in a group with up to three distinct speakers.
- Optional first-person POV, enabled in Settings, with native cameras preserved for dialogue and cutscenes.
- Horde mode with ten curated waves of varied enemies and bosses, adjustable enemy counts, wave growth, levels and rest times; waves load before combat, defeated bodies remain on the ground, and the rest countdown makes room for conversation subtitles.
- Custom eye, hair and armour colours, saved per character and their copies, with an option to restore the original colours.
- Romantic conversations with Anca and Lacra through separate profile toggles, Off by default and automatically On for each character whose romance is confirmed in the loaded save; you can also enable either profile early.
- Optional multilingual pack switches conversation profiles to new IDs with voices supporting 25 languages, including Russian, Spanish, French, Arabic and Japanese.
- Character-specific biographies, speaking rules and relationships, with quest knowledge based on detected journal progress and relevant location, time and environmental context.
- 21 conversation-capable named-character entries, including Lunka, Lunka (Turned), Yanna, Mirto, Pieter and Esme, plus 101 combat-only character, enemy, boss and creature definitions; family members without combat AI travel as protected companions.
- Multiple simultaneous companions and duplicate summons without an artificial party cap; queue more summons while others load, and share conversation history between copies of a character.
- Native following, combat and abilities, adjustable companion damage and attack frequency, and automatic recovery after 3 seconds out of combat.
- Spaced party formations, catch-up while travelling and party restoration across supported world-travel transitions.
- Conversation actions such as “Follow me,” “Stop walking” and “Look at me,” with individual or whole-party dismissal through the menu.
- Native F5 menu with Summon, Party, Horde, Settings, Controls and Help pages, plus remappable menu, text and voice shortcuts.
- Built-in Copy logs support report with sensitive values removed.

Windows · Game 1.05 · Latest release: 0.5.0

[![Watch the AI Companion Manager demo](https://img.youtube.com/vi/K1X4xf-1i_8/hqdefault.jpg)](https://youtu.be/K1X4xf-1i_8)

[Watch the gameplay demo on YouTube](https://youtu.be/K1X4xf-1i_8)

## Download and install

Get the mod from the [GitHub Releases page](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/latest). Choose **Complete** for a single download, or install **both Scripts and Runtime** below:

| Download | What's inside |
| --- | --- |
| [Complete ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.0/DawnwalkerConvai-0.5.0-Complete.zip) | Recommended: all player files in one download |
| [Scripts ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.0/DawnwalkerConvai-0.5.0-Scripts.zip) | The Lua game scripts |
| [Runtime ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.0/DawnwalkerConvai-0.5.0-Runtime.zip) | Everything else needed to run the mod |
| [Multilingual voices ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.0/DawnwalkerConvai-0.5.0-Multilingual.zip) | Optional character copies with Azure multilingual voices; Russian, Spanish and French tested |

**Updating:** install Complete or both matching Scripts and Runtime packages, then reapply the matching Multilingual pack if you use it. Restart the game after updating.

1. Close the game.
2. Install [UE4SS for Dawnwalker **1.2.1 RC6**](https://www.nexusmods.com/thebloodofdawnwalker/mods/18) and [Dawnwalker Mod Menu **1.0.6.2 or later**](https://www.nexusmods.com/thebloodofdawnwalker/mods/271), following their instructions.
3. Extract **Complete**, or **both Scripts and Runtime**, into your game installation folder. Merge the included `Dawnwalker` folders when asked.
4. Launch the game, load a save, and press **F5**.

For multilingual conversations, install the main mod first. Then close the game and copy the optional **Multilingual voices ZIP** into the same game folder, overwriting its one configuration file. English remains available in that pack. To restore the original English Kokoro voices, reinstall the matching Runtime or Complete ZIP. The optional ZIP contains only a JSON configuration file and an installation note; it does not include an executable, DLL, script, or API key. Its character copies begin separate conversation histories and memories. The game and F5 menu remain in their original language.

Your installation should contain:

```text
Your game folder/
└─ Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai/
   ├─ Scripts/
   ├─ Payload/
   ├─ config.ini
   └─ keybindings.ini
```

Don't run the helper executable yourself. The mod starts it when needed. Use borderless or windowed mode for the chat overlays. Conversations require internet access and [Microsoft WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/), which is already installed on many Windows PCs.

**Updating?** Close the game and replace both packages together. Keep your existing `config.ini`, `keybindings.ini` and generated `Payload/runtime` data if you want to retain settings and conversation state. See the [installation guide](docs/PREBUILT-INSTALL.md) for details. GitHub's **Code → Download ZIP** is source code, not the player installation.

## Your first companion

Open **F5 → Summon**, choose a character, then click **Summon** beneath their description. You can queue more characters while others load. Selecting a name alone does not summon it.

Companions follow and fight automatically. Their native AI chooses attacks and powers. Open **Party** to dismiss an individual companion, or use **Dismiss** beside the selected character's description to remove the newest copy.

Choose from talking characters or combat-only character, enemy and creature entries. Combat-only summons do not take part in conversations. Duplicate summons are supported; copies of the same talking character share conversation history.

## Talk to them

| Key | What it does |
| --- | --- |
| **F5** | Open or close the companion menu |
| **F6** | Type to one character |
| **F7** | Talk to one character using your microphone |
| **F8** | Start a group text conversation |
| **F9** | Start a group voice conversation |
| **Enter** | Send your typed message |
| **Esc** | Go back or close the current mod panel |

Look toward the character you want to talk to. If nobody eligible is in view, the mod chooses your nearest talking companion. You can also approach supported world NPCs without summoning them.

For voice chat, **press once, wait for “Speak now,” speak, then press again to finish**. You don't need to hold the key. The mod uses your Windows default microphone; keep the game focused while speaking.

Group chat gives up to three distinct characters a turn. Character profiles include personalities, relationships and relevant quest knowledge, with detected quest progress and details from the game world providing context. Replies are AI-generated, so they can still make mistakes.

## Settings

Open **F5 → Settings**. Manual changes save immediately to `config.ini` in the mod folder. Horde settings apply to the next run.

Starting a Horde resumes the game for loading and closes the panel when the wave is ready. Esc from Horde or Settings returns directly to gameplay.

| Setting | Default | What it does |
| --- | --- | --- |
| Companion damage | 250% | Scales summoned companions' normal physical damage. Enemy damage is unchanged; some special abilities use separate damage rules. |
| Attack frequency | 180% | Adjusts the native attack-speed attribute so attacks finish faster. Native AI still chooses when to attack and which moves to use. |
| Anca romance profile | Off | Automatically On when the loaded save confirms romance with Anca. You can enable it manually before that. |
| Lacra romance profile | Off | Works independently of Anca, automatically turning On when the loaded save confirms romance with Lacra. You can also enable it early. |
| First-person camera | Off | Switches to Coen's eye-level viewpoint. Turn Off to return to the normal camera. Dialogue, menus and cutscenes keep their native cameras. |
| Starting enemies | 8 | Regular enemies in the first Horde wave, in addition to bosses. |
| Enemies added per level | 2 | Extra regular enemies added with each cleared wave. |
| Horde levels | 10 | How many of the ten curated waves to play. Later waves introduce tougher enemies and bosses. |
| Bosses per level | 1 | Extra bosses in each wave, chosen from that wave's enemy theme. |
| Horde timeout | 10 seconds | Rest before the next wave. The countdown pauses with the game and gives way to conversation subtitles. |

Romance toggles change conversation profiles only. They do not complete quests, invent past encounters or play cutscenes. A profile enabled by saved romance history stays On for that save; loading an earlier save rechecks the history. Manual early activation is saved separately.

Fallen companions recover automatically after 3 seconds out of combat. Recovery is always enabled, with no toggle to configure.

## Appearance and controls

- **F5 → Summon:** select a character, then use the eye, hair and armour colour arrows above Summon. Choices apply to that character's summoned copies. Use Restore original colours to reset them.
- **F5 → Controls:** remap the five shortcuts. You can also edit `keybindings.ini` in the mod folder.
- **Multilingual voices:** the optional pack switches conversation profiles to new IDs with voices supporting 25 languages, including Russian, Spanish, French, Arabic and Japanese.
- **Conversation actions:** try “Follow me,” “Stop walking” or “Look at me.” Use the menu to dismiss a companion.
- **Custom characters and voices:** advanced users can change their own Convai profiles and mappings. See [character customization](docs/DEVELOPER-GUIDE.md#character-customization).

## If something isn't working

**F5 doesn't open:** confirm both packages and both required mods are installed. Check the folder path above; an extra nested `Dawnwalker` folder is a common installation mistake.

**The microphone doesn't pick you up:** check the Windows default input and microphone permissions. Press F7/F9 once to start, then again to finish.

**A character won't respond:** check your internet connection, choose a talking character, and try again outside combat or a cutscene.

For help, open **F5 → Help → Copy logs**, then share the report with what happened and which character was involved. The report is also saved as `Payload/runtime/support-report.txt`.

[Join the Discord](https://discord.gg/3p2FzjZQZ) · [Report an issue](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/issues)

## A few things to know

This is a preview mod. Some roster entries, boss powers and area attacks still need more gameplay testing. Large creatures need room to spawn, and big parties can affect performance. Summons are copies: they don't change quest outcomes or revive story characters. Your party is not saved between game sessions. Conversations depend on the shared service being available.

## For developers

[Build from source](docs/SOURCE-BUILD.md) · [How the mod works](docs/DEVELOPER-GUIDE.md) · [File structure](docs/FILE-STRUCTURE.md) · [Release notes](docs/RELEASE-050.md)

The developer guide covers UE4SS discovery, Lua lipsync, companion AI, Convai connections, group chat, quest memory and adapting the approach to another game.
