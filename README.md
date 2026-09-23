# AI Companion Manager for The Blood of Dawnwalker

Bring company on your travels through Vale Sangora. Summon characters to follow you and fight alongside Coen, or stop for a conversation that goes beyond their scripted dialogue.

Talk by **voice or text**, hear their replies with **subtitles and lipsync**, and invite nearby companions into a **group conversation**. No Convai account or command-line setup is needed.

**Version 0.30.9 · Windows · Game 1.05**

[![Watch the AI Companion Manager demo](https://img.youtube.com/vi/K1X4xf-1i_8/hqdefault.jpg)](https://youtu.be/K1X4xf-1i_8)

**[Watch the gameplay demo on YouTube](https://youtu.be/K1X4xf-1i_8)**

## Download and install

Get the mod from the [GitHub Releases page](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/latest). Choose **Complete** for a single download, or install **both Scripts and Runtime** below:

| Download | What's inside |
| --- | --- |
| [Complete ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.30.9/DawnwalkerConvai-0.30.9-Complete.zip) | Recommended: all player files in one download |
| [Scripts ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.30.9/DawnwalkerConvai-0.30.9-Scripts.zip) | The Lua game scripts |
| [Runtime ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.30.9/DawnwalkerConvai-0.30.9-Runtime.zip) | Everything else needed to run the mod |
| [Multilingual voices ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/download/v0.30.9/DawnwalkerConvai-0.30.9-Multilingual.zip) | Optional character copies with Azure multilingual voices; Russian, Spanish and French tested |

**Updating for the save-reload fix:** install Complete or both matching packages. The fix is in Runtime; replacing Scripts alone is not enough. Restart the game after updating.

1. Close the game.
2. Install [UE4SS for Dawnwalker **1.2.1 RC6**](https://www.nexusmods.com/thebloodofdawnwalker/mods/18) and [Dawnwalker Mod Menu **1.0.6.2 or later**](https://www.nexusmods.com/thebloodofdawnwalker/mods/271), following their instructions.
3. Extract **Complete**, or **both Scripts and Runtime**, into your game installation folder. Merge the included `Dawnwalker` folders when asked.
4. Launch the game, load a save, and press **F5**.

For multilingual conversations, install the main mod first. Then close the game and copy the optional **Multilingual voices ZIP** into the same game folder, overwriting its one configuration file. English remains available in that pack. To restore the original English Kokoro voices, reinstall the normal 0.30.9 Runtime or Complete ZIP. The optional ZIP contains only a JSON configuration file and an installation note; it does not include an executable, DLL, script, or API key. Its character copies begin separate conversation histories and memories. The game and F5 menu remain in their original language.

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

There are **15 talking characters** and **86 combat-only character, enemy and creature entries**. Combat-only summons do not take part in conversations. Duplicate summons are supported; copies of the same talking character share conversation history.

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

## Make it yours

- **F5 → Settings:** adjust companion damage and attack frequency. Fallen companions recover automatically after combat.
- **F5 → Controls:** remap the five shortcuts. You can also edit `keybindings.ini` in the mod folder.
- **Multilingual voices:** the optional pack switches all 26 conversation profiles to new IDs with voices supporting 25 languages, including Russian, Spanish, French, Arabic and Japanese.
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

[Build from source](docs/SOURCE-BUILD.md) · [How the mod works](docs/DEVELOPER-GUIDE.md) · [File structure](docs/FILE-STRUCTURE.md) · [Release notes](docs/RELEASE-0309.md)

The developer guide covers UE4SS discovery, Lua lipsync, companion AI, Convai connections, group chat, quest memory and adapting the approach to another game.
