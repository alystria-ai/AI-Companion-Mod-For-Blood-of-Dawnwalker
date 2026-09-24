# LLM NPC Companions System 0.5.0 - page draft

Summon companions such as Anca, Lacra, Brencis, Bakir, Xanthe and Crake to follow you and fight alongside Coen. Talk to them through text or voice, with spoken replies, subtitles and lipsync. Play in first-person POV, fight waves of enemies and bosses in Horde mode, customise eye, hair and armour colours, and have romantic conversations with Anca and Lacra. No Convai account or command-line setup is needed.

This is a preview release. The core conversation, menu, loading and companion systems are working, but every roster entry, scripted power and friendly-fire path has not been validated in gameplay.

## Features

The next release adds first-person POV, Horde mode, custom eye, hair and armour colours, and romantic conversations with Anca and Lacra. The current release candidate is withdrawn while a Horde issue is fixed.

- Text and microphone conversations with nearby supported characters.
- Voiced replies, subtitles and facial animation, with gentle distance-based volume.
- Single-character and group conversations with up to three distinct speakers.
- Character-specific biographies, speaking rules and relationships, with curated quest knowledge based on detected journal progress.
- Relevant location, time and environmental context when the game exposes it; shared conversation sessions for duplicate copies of a character.
- Recent battle context, including observed enemy types and cleared horde waves, available during the rest between waves.
- Native F5 menu with Summon, Party, Horde, Settings, Controls and Help pages.
- 21 named-character summon entries, including Anca, Lacra, Brencis, Bakir, Xanthe, Ambrus and Crake, and 101 combat-only character, enemy, boss and creature definitions.
- Multiple simultaneous companions and duplicate summons, without an artificial party cap.
- Native following and combat behavior rather than generated attack commands.
- Adjustable companion damage and attack frequency.
- Eye, hair and armour colour selectors with 33 shades and left/right arrows. Each summon keeps its own colours; changes and the original-colour reset apply to future summons.
- Optional first-person gameplay camera, with priority given to native dialogue and cinematics.
- Ten curated horde levels with enemy-count, growth, boss-count and rest settings. Companions can join the fight; the rest countdown yields to conversation subtitles.
- Separate Anca and Lacra romance profiles: Auto follows the save, On enables romance early, and Off uses the normal profile even after unlocking romance. When both romances are confirmed and both women are nearby in group chat, Anca and Lacra know about Coen’s relationship with each of them and can exchange character-specific romantic banter. Relationship memories still follow the save. When both romances are confirmed and both women are nearby in group chat, Anca and Lacra know about Coen’s relationship with each of them and can exchange character-specific romantic banter.
- Automatic recovery for fallen companions after 3 seconds out of combat.
- Spaced party formations, catch-up while travelling and party restoration across supported world-travel transitions.
- Remappable menu, text and voice shortcuts.
- Built-in **Copy logs** support report with sensitive values removed.
- Shared conversation service included in the helper; no account, npm command or separate Node.js installation is needed.

## Requirements

- The Blood of Dawnwalker 1.05 on Windows x64.
- [UE4SS for Dawnwalker](https://www.nexusmods.com/thebloodofdawnwalker/mods/18), custom 1.2.1 RC6 build for this game version, installed separately.
- [Dawnwalker Mod Menu](https://www.nexusmods.com/thebloodofdawnwalker/mods/271) 1.0.7 or later, installed separately.
- [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/).
- Internet access for conversations.

## Installation

The main mod has three download choices, plus an optional language pack:

- **Complete** contains the full mod and is recommended.
- **Scripts** contains the Lua game scripts.
- **Runtime** contains the remaining configuration, helper executables, DLLs, local runtime and licenses.
- **Multilingual voices** is an optional two-file ZIP: one JSON configuration and one installation note. It switches conversations to separate profiles using Azure multilingual voices for English, Russian, Spanish and French. Install it over a complete 0.30.9 installation. It contains no executable or API key.

For a split installation, you must install **both Scripts and Runtime for version 0.30.9**. They are two halves of one install.

1. Close the game.
2. Install UE4SS 1.2.1 RC6 and Dawnwalker Mod Menu 1.0.7 or later.
3. Extract **Complete**, or both **Scripts** and **Runtime**, into the game installation folder and merge the included `Dawnwalker` folder.
4. Verify that the mod is exactly here:

   ```text
   Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai
   ```

5. Start the game, load a save and press F5.

For the optional multilingual pack, close the game after the main installation and copy its `Dawnwalker` folder into the same game folder, replacing the configuration file. To return to the original English Kokoro voices, reinstall the normal Runtime or Complete archive. The multilingual character copies have separate conversation histories and cloud memories. The game interface and F5 menu are not translated.

Vortex deployment has not been validated. If you use it, verify the exact path above after deployment; automatic detection is not guaranteed.

The release packages do not include UE4SS or Dawnwalker Mod Menu and do not replace global UE4SS settings. A UE4SS console is not required. If you want it hidden, edit the existing `Dawnwalker/Binaries/Win64/ue4ss/UE4SS-settings.ini`, set `ConsoleEnabled = 0` and `GuiConsoleEnabled = 0`, and preserve all other loader settings.

## Controls

| Default | Action |
| --- | --- |
| **F5** | Open or close the companion menu |
| **F6** | Single-character text chat |
| **F7** | Start or finish single-character voice capture |
| **F8** | Group text chat |
| **F9** | Start or finish group voice capture |

Face a nearby character before chatting. Voice capture is a toggle: press once, wait for **Speak now**, speak, then press again to finish.

In the F5 menu, use Up/Down to move, Left/Right to adjust a setting, Enter to choose and Esc to go back or close. Mouse controls are supported. Selecting a roster entry only shows its details; use the separate **Summon** button to create a companion.

## Customization

Open **F5 → Settings** to change companion damage and native attack frequency. Changes save immediately. Native AI still decides when and how each companion attacks.

Open **F5 → Controls** to remap the five shortcuts. F1–F11, letters, digits, Home, End, PageUp, PageDown, Insert and Delete are supported. Each action needs a unique key. You can also preserve or edit `config.ini` and `keybindings.ini` in the installed mod folder.

The bundled shared-service build is ready to use and needs no account. Advanced users can change local character mappings in `Payload/runtime/convai-config.json`; restart the game and helper after editing it.

## Known limitations

- Roster definitions are asset-verified candidates. Some individual characters, enemies and creatures have not been tested through full gameplay.
- Scripted boss powers, player-only branches, transformations and ability-specific damage may depend on their original encounter and may not work against NPCs.
- Friendly relationships and owned-companion protection are applied, but friendly fire is not confirmed for every special attack or area effect.
- First-time asset loading can still hitch. Large creatures need open ground, and large parties use more game and connection resources.
- Conversations require internet access and shared-service availability.
- Summoned copies do not alter quests or story actors. Party membership is not saved between game sessions or Lua reloads.
- Vortex deployment has not been validated.

## Support

Open **F5 → Help** and choose **Copy logs** at the bottom of the left column. This copies a sanitized diagnostic report to the clipboard and writes `Payload/runtime/support-report.txt`. It is a purpose-built support report, not the complete unredacted logs.

When reporting a problem, include the copied report, the game and mod versions, the roster entry involved, and the exact steps needed to reproduce it. If copying fails, attach `support-report.txt` from the installed mod folder.
