# LLM NPC Companions System for The Blood of Dawnwalker

Fight Horde battles, explore in first-person POV, customise your companions' eye, hair and armour colours, and manage relationships with Anca and Lacra. Summon characters such as Brencis, Bakir, Xanthe and Crake to follow Coen and fight alongside him using the game's native AI and abilities.

Talk to supported characters through text or voice, with AI-powered replies, subtitles, lipsync and group conversations. No Convai account, API key setup or command-line commands are needed.

## Features

- Text and microphone conversations with nearby supported characters, voiced replies, subtitles, facial animation and gentle distance-based volume; talk privately or in a group with up to three distinct speakers.
- Transparent conversation HUD, with an optional microphone-only display, a separate NPC-subtitle toggle, and a shared bottom-offset control for chat and voice UI.
- Optional first-person POV with adjustable field of view, height and forward offset, while preserving native dialogue and cutscene cameras.
- Horde mode with ten curated wave types, a starting-wave selector and random later waves without repeats, adjustable enemy counts, wave growth, levels and rest times; waves load before combat, defeated bodies remain on the ground, and the rest countdown makes room for conversation subtitles.
- Custom eye, hair and armour colours with 33 shades, including vivid pinks, purples, blues, greens and reds. Each summoned copy keeps its own colours.
- Relationship management with Anca and Lacra through separate Auto, On and Off profile choices. Auto follows relationship history in the loaded save, On selects her romantic conversation profile, and Off uses her normal profile. When the save confirms both relationships and both characters join group chat, they can acknowledge Coen’s relationship with each of them and exchange character-specific banter.
- Optional multilingual pack switches conversation profiles to new IDs with voices supporting 25 languages, including Russian, Spanish, French, Arabic and Japanese.
- Character-specific biographies, speaking rules and relationships, with quest knowledge based on detected journal progress and relevant location, time and environmental context.
- Recent battle context with observed character names, enemy types and cleared Horde waves, so companions can discuss who you fought during the rest between waves.
- 21 conversation-capable named-character entries, including Anca, Lacra, Brencis, Bakir, Xanthe, Ambrus and Crake, plus 101 combat-only character, enemy, boss and creature definitions.
- Multiple simultaneous companions and duplicate summons without an artificial party cap; queue more summons while others load, and share conversation history between copies of a character.
- Native following, combat and abilities, adjustable companion damage and attack frequency, and automatic recovery after 3 seconds out of combat.
- Companion haste lets followers run faster to stay with Coen during fast-paced exploration, with extra catch-up speed when they fall far behind, even after you slow down or stop.
- Spaced follow formations and off-screen following. Companions settle on arrival instead of repeatedly adjusting their positions while you approach. Idle followers face generally toward you, with the closest looking more directly at you. Fast-travel recovery remains available, but loading a save clears the summoned party.
- Conversation actions such as “Follow me,” “Stop walking” and “Look at me,” with individual or whole-party dismissal through the menu.
- Native F5 menu with Summon, Party, Horde, Settings, Controls and Help pages, plus remappable menu, text and voice shortcuts.
- Built-in Copy logs support report with sensitive values removed.

## Changelog

### What changed in 0.5.1

- Redesigned the conversation HUD with transparent backgrounds, brass details, larger text and a microphone indicator that shows listening, sending and input problems. Text chat uses Enter to send.
- Added Hide chat boxes, an independent NPC subtitles toggle, and one shared bottom-offset slider. Zero keeps the original position; higher values move the HUD upward across screen sizes.
- Added live first-person FOV, height and forward-offset controls. Removed the fixed camera aspect ratio and retained first person through F5 transitions.
- Corrected microphone-startup visibility, HUD positioning and decimal-valued settings. Reworked overlay startup to avoid showing an old window frame.

### What changed in 0.5 since 0.30.9

- Added first-person POV, kept it active during text and voice chat, and adjusted player visibility to prevent head, hair and body clipping.
- Added ten curated Horde wave types, a saved starting-wave selector with Start horde directly underneath, and random later themes without repeats. Enemy and boss counts, total rounds, wave growth and rest times are configurable. Enemies prepare before combat, missing AI attachments can be skipped, defeated bodies remain, and the menu closes when the wave is ready. Fixed missing melee damage through native weapon setup, and improved wave text, pause/resume handling and Esc navigation.
- Added 33 eye, hair and armour colours with native arrow selectors. Choices apply to your next summon, so duplicate companions can keep different appearances.
- Added relationship management with Anca and Lacra through independent Auto, On and Off profile choices, awareness of confirmed story relationships, and shared banter. Reduced repetitive endearments. This affects conversations only; scene playback was removed.
- Expanded the roster from 15 to 21 named-character entries and from 86 to 101 combat-only definitions, with protected travel for non-fighting characters and richer conversation profiles.
- Changed group chat so each speaker responds to the previous character's reply. Added recent battle and Horde-wave context, captured once at the start and supplied after the encounter or wave ends, using observed opponent names instead of generic boss labels.
- Reworked follower formations and balanced spacing to reduce crowding. Corrected off-screen locomotion scheduling and added catch-up speed based on both your speed and their distance, including when you stop. Arrival now stops the active path to prevent repeated small steps and shuffling. Settled followers face generally toward you, with more direct attention from the closest companions. Loading a save clears the party instead of resummoning it; fast-travel recovery remains separate.
- Simplified voice playback to clear, centred audio with gentle distance-based volume, and set automatic post-combat companion recovery to 3 seconds.
- Updated Mod Menu support to 1.0.7, fixed menu opening and appearance-control layout, improved shortcut recovery when the helper and game have different permissions, and reduced idle background work.
- Fixed character-loading timeouts after save reloads caused by stale asset references, with clearer messages if a load fails.

[Full version history](CHANGELOG.md), including previous releases and development milestones.

Windows · Game 1.05 · [Latest release: 0.5.1](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/tag/v0.5.1)

[Videos and updates on the Alystria AI YouTube channel](https://www.youtube.com/@AlystriaAI)

## Download and install

Get the mod from the [GitHub Releases page](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/latest). Choose **Complete** for a single download, or install **both Scripts and Runtime** below:

| Download | What's inside |
| --- | --- |
| [Complete ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.1/DawnwalkerConvai-0.5.1-Complete.zip) | Recommended: all player files in one download |
| [Scripts ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.1/DawnwalkerConvai-0.5.1-Scripts.zip) | The Lua game scripts |
| [Runtime ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.1/DawnwalkerConvai-0.5.1-Runtime.zip) | Everything else needed to run the mod |
| [Multilingual voices ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.5.1/DawnwalkerConvai-0.5.1-Multilingual.zip) | Optional character copies with Azure multilingual voices; Russian, Spanish and French tested |

**Updating:** install Complete or both matching Scripts and Runtime packages, then reapply the matching Multilingual pack if you use it. Restart the game after updating.

1. Close the game.
2. Install [UE4SS for Dawnwalker **1.2.1 RC6**](https://www.nexusmods.com/thebloodofdawnwalker/mods/18) and [Dawnwalker Mod Menu **1.0.7 or later**](https://www.nexusmods.com/thebloodofdawnwalker/mods/271), following their instructions.
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

Group chat passes your message to the first character, their reply to the second, and the second’s reply to the third. Up to three distinct characters take part, including Anca and Lacra when they are selected for the group. Character profiles include personalities, relationships and relevant quest knowledge, with detected quest progress and details from the game world providing context. Replies are AI-generated, so they can still make mistakes.

## Play a Horde

Find an open area, summon any companions you want alongside you, then open **F5 → Horde**. Use the arrows beside **Starting wave** in the right panel, then select **Start horde** directly underneath. Start outside combat. Your starting-wave choice is saved for future runs and cannot be changed during an active run.

Later wave types are chosen randomly without repeats. Enemy counts grow after each cleared wave; enemy types and bosses follow the selected theme, so their difficulty does not follow a fixed order. **Horde levels** sets the total number of rounds, regardless of which theme you start with. You can adjust enemy counts, wave growth, levels, bosses and rest time in Settings before starting.

The wave prepares before enemies are released, and the menu closes when they are ready. Defeat the available enemies to advance; defeated bodies stay on the ground. During the rest countdown, you can talk to companions about the wave you just fought. The timer returns when conversation subtitles close. Use **End horde** to stop the run, or leave the encounter area.

Companion damage and attack-frequency settings affect your summoned allies, not Horde enemies. Loading a save clears both the party and the active Horde; it does not summon your old party into the new save.

## Settings

Open **F5 → Settings**. Manual changes save immediately to `config.ini` in the mod folder. Horde settings apply to the next run.

Starting a Horde resumes the game for loading and closes the panel when the wave is ready. Esc from Horde or Settings returns directly to gameplay.

| Setting | Default | What it does |
| --- | --- | --- |
| Companion damage | 250% | Scales summoned companions' normal physical damage. Enemy damage is unchanged; some special abilities use separate damage rules. |
| Attack frequency | 180% | Adjusts the native attack-speed attribute so attacks finish faster. Native AI still chooses when to attack and which moves to use. |
| Anca romance profile | Auto | Auto follows your save. On always uses her romantic profile; Off always uses her normal profile, even after unlocking romance. |
| Lacra romance profile | Auto | The same Auto, On and Off choices, independent of Anca. |
| Transparent chat HUD | On | Removes the backdrop behind subtitles, voice status and the typing field. Subtitles and status text have a dark outline for readability. Off restores the shaded panel. |
| Hide chat boxes | Off | On hides all conversation text, including NPC subtitles. Voice input shows only a transparent microphone indicator with a Listening status and your finish shortcut. After sending a text message, the input disappears and no reply text is shown. Spoken replies continue. Horde countdowns are unaffected. |
| NPC subtitles | On | Off hides subtitles for mod NPC replies while keeping the normal voice-input HUD and live transcript. Hide chat boxes overrides this toggle. The game's own subtitles are unchanged. |
| Chat HUD bottom offset | 0% | Zero keeps the original HUD position. Increase it to move text input, subtitles, the microphone HUD and Horde countdowns upward together, by up to 40% of screen height. Tall content stays within the screen. Applies live and scales with resolution. |
| First-person camera | Off | Switches to Coen's eye-level viewpoint. Turn Off to return to the normal camera. Dialogue, menus and cutscenes keep their native cameras. |
| First-person field of view | 90° | Adjust the mod camera from 60° to 120°. Higher values show more surroundings. Applies live without changing native gameplay or cinematic cameras. |
| Camera height offset | 0 cm | Adjust the viewpoint up or down by up to 20 cm relative to Coen's eye height. Crouching still follows the native eye height. |
| Camera forward offset | 42 cm | Adjust the viewpoint between 20 and 70 cm ahead of Coen's capsule. Applies live in first person. |
| Starting wave (Horde page) | Roadside raiders | Choose the first enemy theme with the arrows. Remaining themes are random without repeats; the choice saves for future runs. |
| Starting enemies | 8 | Regular enemies in the first Horde wave, in addition to bosses. |
| Enemies added per level | 2 | Extra regular enemies added with each cleared wave. |
| Horde levels | 10 | How many waves to play, up to ten different themes. Starting with a later theme still plays this many rounds. |
| Bosses per level | 1 | Extra bosses in each wave, chosen from that wave's enemy theme. |
| Horde timeout | 10 seconds | Rest before the next wave. The countdown pauses with the game and gives way to conversation subtitles. |

Relationship management uses the **Anca romance profile** and **Lacra romance profile** settings shown in the menu. These change conversation profiles only. They do not complete quests, invent past encounters or play cutscenes. Auto rechecks relationship history when you load a save. Your explicit On or Off choice is saved and takes priority over that history.

Fallen companions recover automatically after 3 seconds out of combat. Recovery is always enabled, with no toggle to configure.

## Appearance and controls

- **F5 → Summon:** select a character, then use the eye, hair and armour colour arrows above Summon. Colours are captured when you click Summon. Changing the choices or using Restore original colours affects future summons only; existing copies keep their own colours through recovery and travel.
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

[Build from source](docs/SOURCE-BUILD.md) · [How the mod works](docs/DEVELOPER-GUIDE.md) · [File structure](docs/FILE-STRUCTURE.md) · [Release notes](docs/RELEASE-051.md)

The developer guide covers UE4SS discovery, Lua lipsync, companion AI, Convai connections, group chat, quest memory and adapting the approach to another game.

## License

The original mod code, documentation and configuration are available under the [LLM NPC Companions System Convai Use License](LICENSE). You can use, modify and distribute them, including commercially. Distributed modifications and services with AI character conversations or generative character interactions must offer Convai as a working, selectable provider option. Other hosted providers, local models and self-hosted systems are welcome, and any provider can be the default. Users can choose another provider without using Convai. Native combat, following, Horde mode, camera and appearance features do not require Convai.

This is a source-available license, not an OSI-approved open-source license. Third-party components retain their own licenses, and game assets remain subject to their owners' terms.
