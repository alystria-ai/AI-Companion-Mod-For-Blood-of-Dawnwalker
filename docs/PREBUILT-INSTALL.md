# Dawnwalker Convai 0.30.9 Preview

Talk with nearby characters through text or voice, or summon travelling companions that follow Coen and use their native combat AI. This is a preview release: the conversation and companion framework is usable, but every character, power and combat interaction has not been validated in normal play.

## Requirements

- The Blood of Dawnwalker 1.05 on Windows x64.
- [UE4SS for Dawnwalker](https://www.nexusmods.com/thebloodofdawnwalker/mods/18), custom 1.2.1 RC6 build for this game version, installed separately.
- [Dawnwalker Mod Menu](https://www.nexusmods.com/thebloodofdawnwalker/mods/271) 1.0.6.2 or later, installed separately.
- [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/).
- Internet access for conversations. Summoning and native combat do not require a conversation connection.

The release contains the helper, local runtime and shared-service configuration. It needs no npm commands, separate Node.js installation, account or setup screen.

## Choose a download

| Download | Contents | When to use it |
| --- | --- | --- |
| **Complete** | All scripts, data, configuration, helper executables, DLLs and licenses | Recommended for a new install or a normal update |
| **Scripts** | Lua game scripts only | Use only together with the matching **Runtime** archive |
| **Runtime** | All remaining files: configuration, browser client, helper, dependencies and licenses | Use only together with the matching **Scripts** archive |

**Scripts and Runtime are two halves of the same release. Install both 0.30.9 archives.** Neither split archive is a playable standalone package. Do not mix versions.

## Install

1. Close the game.
2. Install UE4SS 1.2.1 RC6 for game version 1.05 and Dawnwalker Mod Menu 1.0.6.2 or later.
3. Choose **Complete**, or download both **Scripts** and **Runtime** for version 0.30.9.
4. Extract the selected archive or archives into the game installation folder, merging the included `Dawnwalker` folder.
5. Verify this exact directory exists:

   ```text
   Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai
   ```

6. Start the game normally and load a save. Press F5 to open the companion menu.

All three archives use game-root-relative paths. When using the split download, extract **both** archives to the same game installation folder and allow their directories to merge.

Vortex deployment has not been validated. If you use it, verify the exact directory above after deployment; automatic detection and placement are not guaranteed.

The packages do not include UE4SS or Dawnwalker Mod Menu and do not replace global UE4SS settings. A visible UE4SS console is unnecessary for local play. To hide it, edit the existing `Dawnwalker/Binaries/Win64/ue4ss/UE4SS-settings.ini` and set only these existing values, preserving every other loader setting:

```ini
ConsoleEnabled = 0
GuiConsoleEnabled = 0
```

## Update or reinstall

Close the game before replacing files. Extract **Complete**, or both matching split archives, over the existing installation. Preserve `config.ini` and `keybindings.ini` if you want to keep your combat settings and remapped shortcuts. Preserve `Payload/runtime` if you want to retain local conversation identity and session state.

Do not keep multiple copies of the mod enabled. Do not delete or replace the rest of the UE4SS folder during a mod update.

## Controls

| Default | Action |
| --- | --- |
| **F5** | Open or close Summon, Party, Settings, Controls and Help |
| **F6** | Start a single-character text conversation |
| **F7** | Start or finish single-character voice capture |
| **F8** | Start a group text conversation |
| **F9** | Start or finish group voice capture |

Face a nearby character before opening a conversation. If no eligible character is in view, the mod can use the nearest summoned talking companion. Voice keys toggle listening: press once, wait for **Speak now**, speak, and press again to finish.

In the F5 menu, use Up/Down to select, Left/Right to change a setting and Enter to choose. Esc cancels key capture, returns to Summon from another page, then closes the root page. Mouse controls and sliders are also available.

Selecting a roster entry does not summon it. Choose a character, then use **Summon** below the description. Repeated clicks queue separate copies. **Dismiss** removes the newest copy of the selected character; Party lets you dismiss a specific copy. Loading continues while the game is unpaused.

## Customize

The F5 Settings page changes companion damage and native attack frequency and saves immediately. The same settings are available through the game's Mod Settings interface. Defaults are 250% damage and 180% attack frequency. Native AI still chooses attacks and abilities. Fallen companions return after the party leaves combat; health bars remain hidden.

Open **F5 → Controls** to remap all five shortcuts. Changes save to `keybindings.ini` in the installed mod folder and reload automatically. Supported keys are F1–F11, A–Z, 0–9, Home, End, PageUp, PageDown, Insert and Delete. Each action needs a different key; Escape, Enter and arrow keys remain reserved for menu navigation.

You can also edit `config.ini` and `keybindings.ini` in the installed mod folder. Advanced conversation mappings live in `Payload/runtime/convai-config.json` and take effect after restarting the game and helper. The bundled configuration already supports normal play; no account is needed.

## Help and support report

Open **F5 → Help** and use **Copy logs** at the bottom of the left column. The button copies a sanitized diagnostic report to the clipboard and also writes:

```text
Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai/Payload/runtime/support-report.txt
```

The report is assembled for support and is not a copy of the complete, unredacted logs. Paste the copied report with the game version, the mod version and the exact steps that caused the problem. If clipboard access fails, attach `support-report.txt` instead.

## Known preview limitations

- The roster contains asset-verified character and creature definitions. Individual definitions, story variants and large creatures still need gameplay testing; some require open terrain or encounter-specific state.
- Native AI decides which attacks and abilities are available. Scripted boss powers, transformations, player-only branches and ability-specific damage scaling may not work against NPCs.
- Ordinary faction relationships and owned-companion protection are applied, but friendly-fire behavior is not confirmed for every special attack or area effect.
- A character's first summon can still hitch while the engine finalizes assets. The progress display reports loading stages, not elapsed time.
- Conversations require internet access and depend on shared-service availability. Large parties increase game, navigation and connection load.
- Summoned copies do not recruit or revive story actors or change quest outcomes. Party membership is not saved between game sessions or Lua reloads.
- Vortex deployment and automatic path detection have not been validated.

## Remove

Close the game and remove only:

```text
Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai
```

Keep UE4SS and Dawnwalker Mod Menu if other mods use them.
