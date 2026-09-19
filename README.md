# Dawnwalker Convai

Talk to the people of **The Blood of Dawnwalker**, or summon them as travelling companions. Face a nearby character, type or speak, and receive a voiced Convai reply with subtitles and Lua-driven lipsync. F5 opens a companion roster: summoned copies follow Coen, fight using their native character AI and abilities, and can join a simulated group conversation.

The mod combines a **UE4SS Lua game adapter**, a **local Node server**, the **Convai Web SDK**, and a small **Windows WebView2/WinForms helper**. Convai produces dialogue, speech and facial data; the mod connects those outputs to actual game actors. The companion system manages spawning, allegiance, travel and combat handoff. It does not ask an LLM to choose every attack.

**Current state, 19 September 2026:** v0.30.8 is a preview for game version 1.05 with UE4SS 1.2.1 RC6 and Dawnwalker Mod Menu 1.0.6.2 or later. It includes a native UMG F5 menu with independent Summon, Party, Settings, Controls and Help pages; 15 talking characters and 86 combat-only creature/boss/enemy definitions; adjustable damage and attack frequency; hidden health bars; recovery after combat; and a Help-page **Copy logs** button that copies a sanitized support report and writes `Payload/runtime/support-report.txt`. New definitions are asset-verified candidates, not all gameplay-verified companions. [Game-update notes](docs/UPDATE-105-V0300.md). [Menu and control fixes](docs/UPDATE-0301-MENU-CONTROLS.md). [Recovery and combat audit](docs/UPDATE-0304-RECOVERY.md). [Source protection and combat exit](docs/UPDATE-0305-PARTY-PROTECTION.md). [Queued-loading performance](docs/UPDATE-0306-LOADING.md). Complete and split prebuilt downloads need no npm commands, separate Node.js installation or account setup. [Prebuilt installation](docs/PREBUILT-INSTALL.md).

## Contents

- [For players](#for-players)
- [Installation](#installation)
- [Character customization](#character-customization)
- [Folders and version control](#folders-and-version-control)
- [Release file structure](docs/FILE-STRUCTURE.md)
- [Build from public source](docs/SOURCE-BUILD.md)
- [Architecture and source map](#architecture-and-source-map)
- [Convai implementation](#convai-implementation)
- [Lua lipsync](#lua-lipsync)
- [Companion implementation](#companion-implementation)
- [Replicating this in another game](#replicating-this-in-another-game)
- [Build, reload and verification](#build-reload-and-verification)
- [Troubleshooting and references](#troubleshooting-and-references)

## For players

| Input | Function |
| --- | --- |
| **F5** | Native companion menu: Summon, Party, Settings, Controls and Help; separate Characters and Creatures & combatants rosters. |
| **F6** | Text chat: prefer a character in view, otherwise the nearest companion. |
| **F7** | Toggle single-character microphone input; press again to stop listening. |
| **F8** | Group text chat; up to three distinct character identities respond in turn. |
| **F9** | Group microphone input. A finalized transcription starts the round and capture closes for replies. Press again to stop manually. |
| **Enter / Send** | Submit the text composer. |
| **Esc** | Close the mod composer/panel when it owns input; outside it, normal game pause behavior applies. |

F6–F9 use the same selection rule on each new conversation: prefer a visible camera-facing character, otherwise choose the nearest spawned companion, even behind the camera or cover. Spawned companions have no selection distance cap; ordinary world NPCs retain their proximity and visibility checks. Combat, cinematics and uninterruptible actions can still make a companion temporarily unavailable. Group listener eligibility remains local to the conversation.

F7/F9 also show a compact microphone panel even when no subtitle is present. Wait for **Speak now**, then talk; the panel names the same key to press again when finished. A steady green dot indicates that capture is open; the green bar measures input level. Received transcription appears as **You: ...**. There is no preparation splash. The mod uses the Windows default input without choosing a device by name; a silent-input hint or microphone failure appears when relevant. The panel hides after capture closes, while current reply subtitles can continue. Keep the game focused; switching away stops capture.

Subtitles show the current reply and clear afterward. The UI scales to the game window and uses a game-inspired charcoal, cream and brass theme. It is an external overlay, not an injected UMG menu; borderless/windowed play is the appropriate setup.

Responses have spatial direction and distance falloff relative to the camera, for both single and group chat. Equal-power panning preserves the voice tone while changing left/right levels and distance volume. This uses an approximate humanoid mouth position and does not simulate wall occlusion or room echoes. [Implementation and checks](docs/SPATIAL-AUDIO-V0278.md).

Ordinary conversations interrupt competing travel while retaining walking physics and idle/turn animation. Native focus and look modes replace direct capsule rotation. After speech, movement is released; a nearby stationary character can keep looking toward Coen without blocking following. Anca’s native turning has been confirmed in gameplay; other characters still need individual confirmation. [Method, evidence and cleanup](docs/CONVERSATION-MOVEMENT-V0281.md). Walking away releases a world NPC when outside selection range and no longer looking at them. Group chat instead uses a shared twelve-metre area around its starting point, so looking toward another speaker does not cancel it. Chatting does not remove a summoned companion from the party.

The v0.30.3 layout aligns toggle and slider rows, keeps the combat category on one line and aligns the Esc/Back footer with the content margin. Recovery timing is automatic and has no user-facing delay control.

The Summon roster only selects a character. Use the dedicated **Summon** and **Dismiss** buttons beneath the description on the right. Dismiss removes the newest queued or spawned copy of that character; Party still lists individual copies. Stage-based loading progress and the queueing hint stay inside the right-hand panel. Native CommonUI click latches retain quick clicks until Lua handles them, and selection/loading updates keep the existing widgets in place.

The keyboard table shows defaults. Open **F5 → Controls** to select an action and press a new key, or edit `keybindings.ini` beside the installed mod's `config.ini`. All five shortcuts are configurable and reload automatically. Escape, Enter and arrow keys remain reserved for navigation. Duplicate or incomplete mappings retain the last valid bindings. Letters and digits remain normal text while the composer is open; use Escape to close it. The menu uses the game's artwork, Afacad typeface, selection material and slider style, with a viewport-filling 1920×1080 design that scales to the display. Escape cancels capture, returns to Summon from another page, then closes the root page; the menu shortcut closes directly.

For support, open **F5 → Help** and choose **Copy logs** at the bottom of the left column. It copies a sanitized diagnostic report to the clipboard and writes `Payload/runtime/support-report.txt`. This purpose-built report is not the complete unredacted log set.

Companions follow and assist in combat by default. Ask **“Follow me,” “Stop walking,” “Look at me,”** or **“Leave the conversation.”** Follow resumes travel; Stop means wait; Leave ends chat without dismissing a summoned copy. Use F5 for dismissal. There are no tactics, orders, power-grant or action-management tabs.

The 15 current companion definitions are Anca, Lacra, Bakir, Ambrus, Xanthe, Brencis, Crake, Uriash Matriarch / Bakr-Erga, Leonica, Ocha, Vicho, Drogos, Sara, Catalin and Isbrand. An available definition does not guarantee every story-specific ability works outside its original encounter. Pieter and Vladimir cannot be summoned from F5. Their research templates remain, but their cloud profiles were absent from the latest account audit; named world dialogue requires a valid configured ID, otherwise eligible humanoids use the ambient pool. Ordinary humanoid street NPCs do not need to be companions: approach and face them, then use F6 for text or F7 for voice. Named profiles take precedence; other supported humanoids receive a saved assignment from the five male or five female original Convai personas when configured. Animals and NPCs without supported humanoid identity metadata do not use these pools.

Duplicates are allowed, without an artificial party cap. A lone copy keeps its plain name; duplicates are numbered while several exist. Copies of a named character share its Convai identity/session. Large parties still cost game CPU, navigation work and potentially more simultaneous Convai connections.

Summons are mod-owned copies: they do not revive story characters, recruit original quest actors or change quest outcomes. Conversation actions cannot grant items, complete quests or execute arbitrary code. Quest knowledge is curated rather than omniscient. The default 2.5× damage boost affects verified physical attributes, not uniformly every spell/area effect. Parties reset on Lua reload and are not automatically restored as a persistent saved party.

## Installation

### Prebuilt installation

Download both [Scripts ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/raw/refs/heads/main/DawnwalkerConvai-0.30.8-Scripts.zip) and [Runtime ZIP](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/raw/refs/heads/main/DawnwalkerConvai-0.30.8-Runtime.zip), then extract both to the game root. Scripts contains only Lua files; Runtime contains everything else, including JavaScript, PowerShell, data, configuration, executables, DLLs, local runtime, documentation and licenses. Neither split archive works alone. Both preserve the game-root-relative `Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai` path. See [installation instructions](docs/PREBUILT-INSTALL.md) and [ZIP checksums](SHA256SUMS.txt). The previously supplied Complete package remains an alternative single download.

Install UE4SS 1.2.1 RC6 for game version 1.05 and Dawnwalker Mod Menu 1.0.6.2 or later separately. No npm command, separate Node.js installation or account is needed. Vortex deployment has not been validated, so verify the exact installed path if you use it. The packages do not replace global UE4SS settings. A visible console is optional; to hide it, set `ConsoleEnabled = 0` and `GuiConsoleEnabled = 0` in the existing `ue4ss/UE4SS-settings.ini` while preserving every other loader setting. See [the installation guide](docs/PREBUILT-INSTALL.md) and [release file structure](docs/FILE-STRUCTURE.md).

### Developer requirements

The instructions below describe a **development-folder installation**. Keep the complete project at a permanent writable location such as `C:\Mods\DawnwalkerConvai`; the installed bootstrap loads code from that folder.

- Windows x64, The Blood of Dawnwalker 1.05 and the game-compatible **UE4SS 1.2.1 RC6** build.
- Node.js and npm available on PATH. Node 22 or newer is a practical baseline for the APIs used by the bridge/tests.
- [Microsoft WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/). Building the helper also requires the WebView2 SDK and Windows .NET Framework compiler.
- For a developer installation: a Convai API key, accessible character IDs and sufficient service allowance. The prebuilt shared-service edition includes its configuration. Microphone permission is needed only for F7/F9.
- Native/helper binaries listed below, supplied in a distribution or built locally. `npm ci` does not fetch UE4SS, the WebView2 SDK or the native compiler.

Required binaries in `bridge/native/`: `ConvaiHost.exe`, `Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.WinForms.dll`, `WebView2Loader.dll`, `companion_native_v9.dll`, `companion_assets_v2.dll`, and `companion_protection_v2.dll`. Retain `bridge/fonts/` and its license. Historical DLL versions and diagnostic executables are not all required for a fresh package.

### 1. Prepare the project

Run from the project directory. Keep the game closed during initial installation:

```powershell
Set-Location 'C:\Mods\DawnwalkerConvai'
npm ci
npm run check
npm test
npm run build
New-Item -ItemType Directory -Force -Path runtime | Out-Null
[IO.File]::WriteAllText((Join-Path (Get-Location) 'runtime\node-path.txt'), (Get-Command node).Source)
```

Extract the compatible UE4SS archive into `vendor/ue4ss/`, preserving its structure. That level must contain `dwmapi.dll` and `ue4ss/`, without an extra enclosing archive directory. If binaries are not supplied, complete [the source build](#build-reload-and-verification) before launching.

### 2. Configure Convai

For a new setup, copy [examples/convai-config.example.json](examples/convai-config.example.json) to `runtime/convai-config.json` and replace every placeholder with your own values:

```powershell
Copy-Item -LiteralPath examples/convai-config.example.json -Destination runtime/convai-config.json
```

Do not overwrite an existing working configuration. Save JSON as **UTF-8 without a BOM**, without comments/trailing commas: the Node endpoint uses `JSON.parse` directly. The example configures only Anca. Both default `characterId` and her roster `id` must contain her cloud ID. Add other roster entries before expecting distinct conversations; spawning a pawn does not create its cloud profile.

For a custom developer account, create profiles and map their IDs as described below. The prebuilt shared-service edition uses the included roster. Core API scripts are deliberate profile-writing tools, not required startup tasks. Release packaging uses an explicit file list and excludes personal runtime history.

### 3. Install the game adapter

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install.ps1 -GameDirectory 'C:\Games\The Blood of Dawnwalker'
```

Pass the folder containing the game's `Dawnwalker` subfolder. The installer verifies `Dawnwalker\Binaries\Win64\Dawnwalker.exe`, copies the loader, enables the mod, writes `runtime_path.lua` and records `runtime/installation.json`. It warns if the executable hash differs from the tested build. It refuses to overwrite an existing loader: preserve and reconcile an existing UE4SS installation first. It is an **initial installer**, not an everyday update command.

The installer does not create cloud profiles, populate `node-path.txt`, fetch third-party dependencies or compile the helper. The preparation steps are necessary on a fresh machine.

### 4. Launch and check

Launch normally and load a save. With `AutoStartConvai = true`, Lua starts the helper; `Start-Convai.cmd` can also start it manually. If the game runs elevated, let its supervisor launch the helper at the same privilege level so input can reach it.

Summon Anca with F5 or approach an eligible existing actor. Press F6 and send a short message. Verify voice, current subtitles, mouth shaping and release before trying a large party. F8 needs multiple configured nearby identities. F7/F9 use the default microphone; summoning and preconnection never open it.

A visible UE4SS console is not required. Check `<game>\Dawnwalker\Binaries\Win64\ue4ss\UE4SS.log`, `runtime/reload-status.txt`, `runtime/background-status.txt` and heartbeat files when startup fails.

### Disable or relocate

To play without UE4SS, close the game and run `Disable-UE4SS.cmd`. It verifies the loader and moves it to `runtime/dwmapi.dll.disabled`, leaving the executable/saves unchanged. To re-enable that exact installation, close the game and restore the saved DLL to the manifest's `gameBin` as `dwmapi.dll`. Do not rerun the installer over a partially disabled existing setup.

If moving the project, close the game/helper, preserve its complete layout, update installed `Scripts/runtime_path.lua` to the new runtime directory, update `runtime/installation.json`, and regenerate `node-path.txt` if Node moved. Native DLLs locate runtime relative to `bridge/native/`.

## Character customization

### What controls what

| Location | Authoritative for |
| --- | --- |
| **Convai cloud profile** | Backstory, personality, voice, language, model and generation settings. |
| `runtime/convai-config.json` | Private key, default profile and live game-identity-to-cloud-ID roster. |
| `characters/companion-config.json` and `mod/Scripts/companion_config.lua` | F5 roster and game assets to summon. |
| `characters/companion-lore.json` | Local background, aliases, topics and weighted relationships. |
| `characters/quest-knowledge.json` | Which verified quest facts each character may receive. |

`characters/roster.json` is a provisioning/research record. The browser reads the roster **embedded in runtime configuration**, not that file directly. Recorded voice/model fields can become stale after cloud edits. Changing local `bio`, `voice` or `model` fields does not update Convai. Conversely, a new cloud ID does not create a body or facial rig.

### Change biography, voice or model

Edit the corresponding character in your Convai account, preserving its ID. Describe identity, speaking style, relationship to Coen and what must remain unknown. Anca can be thoughtful and reserved; guarded characters should decline to discuss secrets instead of inventing them. Keep canonical background separate from mutable quest facts.

A useful style paragraph is:

> Speak as this character in first person. Usually answer in one or two short spoken sentences, without markdown or stage directions. Use runtime context for verified current events. Do not invent quest completion, private revelations or successful game actions. Request only advertised actions and wait for their result.

Choose a voice available to your account. Voice IDs are service identifiers, not actor names or local files; selected voices are not replicas of the game's actors. Use the current account/model catalogue rather than assuming an old list remains available.

The current setup retains `fast-gemma-4-31b-it`. Three alternatives were tested without consistent speech-latency improvement. Two real short-prompt group runs measured first replies at 2.59–3.12 seconds and later replies around 40 ms after simulated handoff. These browser measurements exclude game handoff delay and are not a guarantee. [Methods and limitations](docs/CONVAI-LATENCY-V0277.md).

After changing IDs or cloud generation settings, reconnect retained clients:

```powershell
Set-Content -LiteralPath runtime/background-restart.request -Value 'Apply character configuration changes' -Encoding Ascii
```

The running game's supervisor consumes this marker. Active chat resets, but the party remains and the game need not restart. When the game is closed, the next helper launch reads the updated configuration.

### Add or replace a mapping

Each runtime roster entry needs:

```json
{
  "key": "anca",
  "id": "YOUR_ANCA_CHARACTER_ID",
  "name": "Anca",
  "kind": "main",
  "gender": "FEMALE",
  "aliases": ["anca", "NPCDef_Anca", "NPCDef_anca_Base", "anca_Base"]
}
```

`key` is the stable local identity; `id` is the remote ID. Aliases match exact identity tokens case-insensitively. Preserve keys when changing a display name. Crake's internal key remains `marat`, while his user-facing name is **Crake**.

Named profiles match NPC name, voice-tag suffix or definition/actor basename; broad directory substrings do not count. Generic profiles use `kind: "generic"`, `gender: "MALE"` or `"FEMALE"` and keys such as `male-1`. Five of each gender provide the intended variety. Eligible humanoids get a stable random choice per actor path and a separate session identity even if they share a persona. Unknown/animal identities are not blindly assigned human profiles.

For companion/group support, align keys across runtime roster, JSON/Lua companion configurations and companion lore. Adding a new game character also requires verified definition/AI/rig compatibility. The setup page at `http://127.0.0.1:32123/` supports advanced actor/class-to-ID overrides, but normal roster mapping is preferable: overrides can lack a quest recipient and bypass ordinary identity routing. Keep the server local.

### Researched profiles and LTM

The portable [profile catalogue](characters/profiles.json) and [pasteable Core Descriptions](characters/README.md) include sourced history, directed relationships, speaking rules and original dialogue examples. The dedicated speaking-style controls can remain blank because all of that content is embedded in the verified Core Description. The current 26 cloud voices were checked against Convai's Kokoro catalogue; none is ElevenLabs. [Research, update workflow, free-account setup and memory limitations](docs/CHARACTER-PROFILES-V0282.md).

The free account supplied for testing allowed profile readback but rejected Core API setting writes. That restriction is separate from the LTM allowance shown in its dashboard: enable permitted LTM toggles through Memories → Memory Settings, and reuse one `endUserId` across characters. Live quest context continues to work when cloud memory is unavailable. Connection concurrency and usage credits are separate account limits.

### Core API maintenance

These operations use the `CONVAI-API-KEY` header:

| Endpoint | Purpose |
| --- | --- |
| `POST /character/list` | Verify ownership before reusing IDs. |
| `POST /character/create` | Create with `charName`, `voiceType`, `backstory`. |
| `POST /character/update` | Update selected fields, including `model_group_name`, voice/backstory, temperature or language. |
| `POST /character/get` | Read back the profile. |
| `GET /tts/get_available_voices` | Read voice IDs/descriptions. |
| `POST /character/getSupportedModel` | Query models for `charID` and verify the active selection. |

See Convai's [character API](https://docs.convai.com/api-docs/api-reference/core-api-reference/character-crafting-apis/character-api), [voice API](https://docs.convai.com/api-docs/api-reference/core-api-reference/character-crafting-apis/voice-list-api) and [Core AI settings](https://docs.convai.com/api-docs/api-reference/core-api-reference/character-crafting-apis/core-ai-settings-api), including account-plan requirements. Writes are verified by readback.

`provision-characters.py` creates/updates the base main/ambient set, checkpoints each creation, verifies ownership and writes runtime mappings. `provision-companion-extras.py PROJECT_PATH` expects that checkpoint and extends the source roster from lore; it **does not deploy the final runtime roster**. Copy reviewed entries into runtime configuration afterward. `build-character-profiles.mjs` compiles the researched descriptions and pasteable text exports. `apply-researched-profiles.py` plans existing-profile changes by default; add `--apply` to write and verify them. `update-managed-profiles.py` delegates to that updater. The older provisioning tools can overwrite manual customization and retain historical naming/model choices: inspect before deliberately rerunning, then reapply the researched profiles. Ordinary play requires none of them.

For developer damage tuning, `mod/Scripts/companion_config.lua` holds `damageMultiplier = 2.5`; the adapter accepts 1–10 and 1 means baseline. Lua changes reload/dismiss the party. Keep JSON/Lua roster entries consistent. `Build-CompanionConfig.mjs` requires the captured asset catalogue and emits research-time defaults; reconcile its output instead of blindly overwriting current curated files.

## Folders and version control

The published repository is [AI-Companion-Mod-For-Blood-of-Dawnwalker](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker), on branch `main`. Source files, this README, and both download ZIPs live directly at the repository root. `git log --oneline` lists rollback points and `git diff` shows uncommitted changes. Prefer `git revert <commit>` to undo a completed change while preserving history. Local runtime state, credentials, backups and build dependencies remain excluded. Keep runtime conversation state separately when changing versions.

| Project-relative path | Contents |
| --- | --- |
| `mod/Scripts/` | Lua bootstrap, facial adapter, selection, conversation and companion gameplay. |
| `bridge/` | TypeScript Convai client, Node service and C# overlay/helper source. |
| `bridge/public/` | Setup page, generated `client.js` and audio worklet. |
| `bridge/native-source/` | Native population/asset-loader C source. |
| `bridge/native/` | Built Windows helper and versioned native DLLs. |
| `characters/` | Profile research, companion definitions, relationships and quest policy. |
| `examples/` | Shareable placeholder configuration; no real key. |
| `scripts/` | Install/build tools, profile maintenance, diagnostics and benchmarks. |
| `tests/`, `docs/` | Regression checks, implementation reports and investigation evidence. |
| `runtime/` | Private configuration, installation paths, browser/session storage, live mailboxes, logs and test output. |
| `vendor/` | Locally supplied loader, SDKs and build tools. |
| `backups/` | Historical recovery copies. |

The game entry is `<game>\Dawnwalker\Binaries\Win64\ue4ss\Mods\DawnwalkerConvai\Scripts`. Its `runtime_path.lua` points back to this project. Locate your exact installed mod without embedding machine-specific paths in public documentation:

```powershell
$installation = Get-Content -LiteralPath runtime/installation.json -Raw | ConvertFrom-Json
Join-Path $installation.gameBin 'ue4ss\Mods\DawnwalkerConvai\Scripts'
```

Before sharing source, inspect staged/package files. `.gitignore` excludes runtime, vendor, dependencies, backups and the generated browser bundle; it is not a complete release/license audit. Review built files under `bridge/native`, personal profile metadata and third-party assets. Do not ZIP the entire working folder. A source checkout requires external dependencies; a playable release must supply the required authorized binaries and configuration instructions. [The release file-structure guide](docs/FILE-STRUCTURE.md) distinguishes source folders from the installed package.

[CHANGELOG-AND-LEGACY-GUIDE.md](CHANGELOG-AND-LEGACY-GUIDE.md) preserves the previous README and release narrative. Older reports describe superseded keys, graphs and experiments; this README is the current entry point.

## Architecture and source map

```text
Player chat keys                    Player F5
       |                              |
WinForms composer / microphone    Companion panel
       |                              |
       +--- Node server on 127.0.0.1:32123 ---+
       |                                    |
Hidden WebView2 + Convai SDK        Validated file mailboxes
       |                                    |
Convai: text/audio/face/actions          UE4SS Lua
       |                                    |
Local voice / subtitle overlay     Actor / face / companion adapters
                                            |
                                   Dawnwalker native systems
```

One WebView2/WinForms helper supplies the overlay and browser Web APIs, rather than Electron. Node handles routing and context processing. The game process performs no HTTP, WebRTC or microphone work. Unreal operations run on the game thread; network waits stay outside it.

Three ownership tokens serve different purposes: **actor generation** identifies the current game selection; **character/session identity** identifies cloud conversation/memory; **group turn token** identifies one reply. Delayed output must still match its owner. Clones may share a cloud identity without simultaneously owning the currently animated mouth.

The HTTP server checks host/origin and authenticates writes with a session token. Lua reads bounded plain data, not executable text. Node atomically replaces mailboxes: `target.txt` identifies actor/generation; `frame.txt` contains timestamped mouth weights; action/UI/group files have separate requests and acknowledgements. Stale frames neutralize the mouth, and heartbeat expiry releases owned input/actor state. This is a local desktop integration, not a public credential proxy.

| Source | Main responsibility |
| --- | --- |
| `mod/Scripts/main.lua`, `live_reload.lua` | Stable entry point, callbacks and versioned gameplay reload. |
| `app.lua`, `targeting.lua`, `engagement.lua`, `ui_input.lua` | Selection, identity, reversible conversation hold, input lease and game snapshots. |
| `face_graph.lua` | Owned facial layer and verified numeric control mapping. |
| `companions.lua`, `companion_recovery.lua`, `companion_combat.lua` | Owned party, travel/recovery and native encounter handoff. |
| `ai_state.lua`, `companion_damage.lua`, `companion_native.lua` | Native lifetime/AI guards, per-clone damage and fixed native bridge operations. |
| `bridge/client.ts`, `character-connections.ts` | SDK lifecycle, preconnection, active reply and cloud identity. |
| `prepared-reply.ts`, `reply-audio.ts`, `reply-tracker.ts` | Deferred speech, PCM playback clock and current-turn completion. |
| `group-chat.mjs`, `companion-lore.mjs` | Speaker ordering, group transcript and relevance. |
| `characters.ts`, `quest-memory.ts`, `heard-memory.ts`, `microphone.ts`, `voice-input.ts` | Profile routing, memory isolation and capture lifecycle. |
| `server.mjs`, `protocol.mjs`, `game-context.mjs`, `quest-knowledge.mjs`, `environment.mjs` | Local transport and interpreted world/quest facts. |
| `WebViewHost.cs`, `DialogueOverlay.cs`, `ComposerKeys.cs`, `CompanionPanel.cs` | Host, scaled UI and real keyboard input. |

Lua filenames in the table are under `mod/Scripts`; browser/server/helper files are under `bridge`.

## Convai implementation

### Creating and retaining clients

The pinned SDK is **`@convai/web-sdk` 1.7.0**, using its vanilla client. The essential configuration is equivalent to:

```typescript
import { ConvaiClient, AudioRenderer } from '@convai/web-sdk/vanilla';

const client = new ConvaiClient({
  apiKey,
  characterId,
  endUserId,            // stable within character + save timeline
  characterSessionId,  // restore when one has been recorded
  transport: 'livekit',
  startWithAudioOn: false,
  enableVideo: false,
  enableLipsync: true,
  blendshapeConfig: { format: 'mha', output_fps: 60 },
  logRtviMessages: false
});
const renderer = new AudioRenderer(client.room);
await client.connect();
await client.room.startAudio();
// Production waits for botReady, installs guarded listeners,
// supplies current context and only then sends a request.
```

This excerpt illustrates baseline SDK playback and omits lifecycle/action configuration. Production v0.30.8 uses `SpatialRenderer` instead of the ordinary renderer, routing the remote stream through equal-power panning; prepared PCM playback uses the same `SpatialOutput`. Use the source for a complete port. Convai documents the need for audio-track attachment with custom UIs and exposes the blendshape queue for facial output. [Web SDK documentation](https://docs.convai.com/api-docs/plugins-and-integrations/web-plugins/convai-web-sdk).

`CharacterConnections` retains one client per distinct named profile/timeline. Summon requests announce connection intent before assets finish loading. Setup is staggered by 500 ms with at most two background setups pending; that limits startup work, not party size. Failures back off. Selecting a ready character promotes its existing client. Ready party connections remain available while needed; clones share their named identity. Generic identity additionally includes actor path.

A **character profile** defines the persona, a **session ID** identifies dialogue history, and **endUserId** identifies the player for cloud memory. The same end-user ID is now passed to every character and clone; Convai separates memory by character plus player. Set optional `endUserId` in the private config to reuse your existing end user. When blank, one UUID is persisted in browser local storage per API-key fingerprint. Preserve the explicit ID across key rotations, machines or WebView resets to avoid allocating another slot. Session identities include the shared player, character and local timeline; generic actors additionally include actor path. Generic actors sharing a persona have separate sessions but share that persona's cloud LTM. Clearing the WebView profile does not delete old cloud memories.

### Requests, audio, subtitles and microphone

A text request has an ID/generation. The client waits for the selected bot, replaces temporary context with `run_llm: 'false'`, clears old captions, calls `sendUserTextMessage`, and acknowledges once. New input can interrupt speech without replaying acknowledged requests after reconnect.

`ReplyTracker` snapshots old message IDs. Only fresh rows/current speech become captions; empty SDK streaming placeholders cannot keep a turn unfinished indefinitely. Initial idle is not completion. Final text, actual speech state and drained facial queues determine completion, with tail guards for delayed TTS. The direct response uses the spatial remote-track renderer; current captions travel through Node to the native overlay independently of the setup page.

`Microphone` serializes hardware transitions. `VoiceInput` keeps stable controls per SDK client, enables STT, verifies the live microphone publication and unpublishes stopped tracks between turns. It uses Windows default capture with no device ID/name constraint. Its local analyser reads the same published track for the input meter and has no audible output. The `userTranscriptionChange` event supplies the on-screen transcription. `heartbeat.mjs` preserves the previous timestamp across partial file reads while retaining explicit focus-loss and expiry checks. F7/F9 provide explicit request IDs. A late permission result is closed if ownership changed. Focus loss, target loss and device removal stop capture; denial/failure requires a new user request rather than retrying forever. Group voice uses the finalized first-speaker transcription once and closes capture for the responses. Preconnection and preparation never request microphone access. The native `DialogueOverlay` reads `microphoneRequested`, `microphoneOn`, `microphoneStatus`, `microphoneLevel` and `microphoneTranscript` from `overlay.json`. Listening appears only after capture is verified; the overlay does not display a preparation splash. It renders an independent 480-pixel-wide logical panel for voice alone, with height measured from wrapped transcription, or adds a separate strip below a current subtitle. Its existing window scaling and focus gates also apply to this indicator; showing it does not start capture or take keyboard focus. Local selection/request errors remain visible for eight seconds.

### Simulating group conversation

There is no shared multi-character Convai session here. `GroupChat` coordinates individual clients:

1. The addressed actor speaks first. Other available summoned members within twelve metres are ranked by explicit name mention, topic matches and weighted relationships from `companion-lore.json`, then distance. At most two more **distinct identities** are selected; twenty Anca copies are not twenty speakers.
2. The player's utterance records nearby listeners. Each response receives that character's own background/quest facts and applicable heard transcript, not another character's private context.
3. When first-speaker text finalizes, the second starts generating. When second-speaker text finalizes, the third can start while the first still speaks. This overlaps generation/playback while preserving conversational dependency.
4. `PreparedReply` stores silent PCM, caption segments, facial frames and deferred actions. `ReplyAudio` and `public/reply-capture.js` capture and replay samples on a local audio clock.
5. Lua acknowledges selection of the next actor before that reply's playback/face/actions become active. Completion waits for drained playback; the final turn releases the conversation hold.

Real Chromium WebRTC tracks sometimes yielded no Web Audio PCM until consumed by a media element. The buffer now attaches a hidden, muted, zero-volume consumer. LiveKit can unmute attached elements in `startAudio`, so zero volume also protects handoffs. Only the replay worklet outputs audible samples. Finished speech with missing PCM is an explicit failure, not silent success. Cancellation disposes buffers and annotates the client's temporary context that the prepared reply was not heard.

Short preceding replies, slow service or failed preparation can still leave gaps. A generated reply is not counted as heard until its turn finishes. See [pipeline design](docs/GROUP-PIPELINE-V0276.md) and [real audio repair/measurements](docs/CONVAI-LATENCY-V0277.md).

### Dynamic context and memory

| Input | Source and lifetime |
| --- | --- |
| Persona | Cloud backstory and reviewed local personal lore; relatively stable. |
| Surroundings | Fresh game region/time/precipitation; temporary replacement context. |
| Quest knowledge | Current journal matched to explicit recipient rules; eligible facts may also enter cloud memory. |
| Heard dialogue | Completed group utterances with listeners; reported speech, not proof the claim is true. |

`environment.mjs` rejects stale/wrong-generation observations. A region is not a precise building; regional rain does not prove indoor/outdoor exposure, temperature or visibility. Weather is not continuously appended to permanent quest memory.

Lua exports a journal snapshot. `quest-knowledge.mjs` matches reviewed rules in `characters/quest-knowledge.json`: exact quest title, ID prefix, state, optional ending inclusion/exclusion patterns and recipient key. Authored facts are emitted only for that character when the conditions hold. A walkthrough explains an event; the live save proves whether it occurred. Missing state, unknown branches and unmatched active quests do not become completed facts. The system does not automatically learn every quest from a wiki or upload the whole journal to every NPC. [Policy and sources](characters/QUEST-KNOWLEDGE.md).

`QuestMemory` tracks a hashed journal/policy ledger. Ordinary active-to-terminal progress keeps the timeline. A rollback, missing old quest, changed ending or relevant policy change conservatively creates a new local timeline and new sessions. The shared cloud end-user ID remains stable to fit a one-user allowance. Cloud LTM can therefore retain older-save facts; current-save context is authoritative, but this does not guarantee perfect cloud rollback isolation. Old cloud memories are not deleted. This is heuristic local save separation, not a native save-slot identifier.

Eligible facts use `client.memoryManager.addMemories`, at most 16 per batch, with persisted acknowledgements, normal spacing and failure backoff. Memory writes do not block sending the reply request. `HeardMemory` preserves listener-scoped reported dialogue; a character does not learn a line merely because it existed in another client's generated history. Verified game facts and player/companion claims remain distinct.

To extend coverage: inspect the runtime quest ID/state/ending, consult the linked source, decide who should know and when, add an explicit recipient rule, and test both matching/nonmatching branches. “Quest complete” is not permission to reveal every secret to the party.

### Actions

The client advertises only `Follow`, `Stop Walking`, `Look At Player` and `Leave`, targeting Coen. An `actionResponse` is structured data, never executable Lua. Browser allowlists, the Node queue and game-generation checks reject unsupported/stale actions. The game returns success/failure; that result is appended to temporary context. Prepared actions wait for the speaker's playback instead of moving an NPC during hidden generation.

Summoned actors route through the party manager; world NPCs use the reversible conversation/follower adapter. Both must never own one pawn's movement simultaneously: that conflict previously caused running in place. Conversation release and party dismissal are separate operations.

## Lua lipsync

All **game-side facial control remains Lua**. Native companion DLLs handle spawning/assets, not face animation. Convai supplies facial values; it does not discover Dawnwalker's graph for us.

The investigation first proved visible `JawOpenAlpha` movement on an actor's owned face layer. Richer shaping uses `face_graph.lua`, the correct attached layer and `ABP_FaceDefaultLayers` when appropriate. The adapter captures original state and writes dump-verified numeric `CurveValues` layouts:

- `AnimGraphNode_ModifyCurve_3`: 129 fixed mouth/jaw/tongue controls.
- `AnimGraphNode_ModifyCurve_8`: four additional lip-closure inputs.
- `JawOpenAlpha`: clamped scalar jaw control.

The browser names Convai's 251-channel MetaHuman frames with `METAHUMAN_ORDER_251` and sends relevant `CTRL_expressions_...` mouth channels. Lua matches names to its verified layout, validates array counts/types, bounds values, and restores original values/layer ownership on release. It never copies the complete remote array into an arbitrary game array.

Queue consumption uses elapsed time/source FPS rather than “one packet equals one frame.” Prepared facial/caption samples follow the captured audio clock. Browser, file bridge and game ticks sample at different rates: this is not sample-accurate synchronization, and not every 60-fps source frame reaches the game. Stale/wrong-generation data neutralizes the mouth. Native scene/dialogue ownership and object destruction take priority over retained mod handles.

JALI inspection located speech machinery, but the streaming path does not synthesize JALI clips or freeze the whole skeleton. Ordinary `SetMorphTarget` calls were insufficient on this graph. A port must first prove a writable facial control and restoration on its own rig.

## Companion implementation

### Queue, native bridge and spawn ownership

`bridge/companions.mjs` validates commands; `companions.lua` owns the party. Cooked NPC definitions determine native body/AI. Copies are created through population spawners; original quest actors are not destroyed/reassigned. Only objects belonging to recorded spawners become party members.

The F5 roster remains interactive while summon requests queue. Class/asset loads are asynchronous and polled. Mere class presence is insufficient: class/CDO initialization and postload flags must be clear. Native work/population ownership are guarded to avoid earlier overlapping-load crashes. UI progress describes pending stages rather than a fake byte percentage. Auto-close waits for the whole batch and a grace period after the latest roster interaction. Engine finalization can still cost a frame.

The small C ABI bridge exists because this loader's Lua soft-reference marshaling did not match the game's 40-byte parameter representation. Lua writes a fixed operation request and calls a no-argument export. C resolves verified engine functions/properties and returns plain data. It does not link a second Lua runtime, evaluate input as code or hardcode dump object addresses. Native parameter buffers use verified sizes and property initialization/destruction. The wrapper loads `companion_native_v9.dll`, `companion_assets_v2.dll` and `companion_protection_v2.dll`.

Native boundaries revalidate/re-resolve objects. Temporary async actions can expire while their population spawner still owns a pawn; retaining an action pointer caused an earlier crash. Cleanup tracks the durable owner and verifies class/lifetime. The bridge also avoids a weak-object serial-allocation path that crashed on fresh objects in this build. These are build-specific constraints, not universal Unreal guarantees.

### Following, spacing and retreat

Companions spawn in front arcs and follow in matching rear arcs. The first arc is about 2.5 metres from Coen for standard bodies, with at least 1.9 metres between assigned positions. Larger parties fill additional arcs. Larger collision capsules expand spacing. Short approaches leave settled companions still; travel resumes after a three-metre departure. [Spacing, arrival correction and validation](docs/COMPANION-SPACING-V0283.md).

Fast travel retains the party roster. Super-speed travel first tries to recover existing off-camera pawns on safe navigation rather than repeatedly spawning replacements. New worlds restore companions through the queued loading path; defeated members wait until combat has ended before reviving. These changes still need gameplay validation on version 1.05.

`party_formation.lua` coordinates all companion seats once per update. Summons retain their initial front positions until departure, then follow matching rear arcs; larger parties add outer arcs. Native-locked participants reserve their actual space. A blocked seat searches nearby angles on its arc or waits. Camera turns and short approaches preserve settled positions.

`companion_recovery.lua` manages spacing/catch-up. Movement starts promptly, with run/walk hysteresis to avoid gait oscillation. Obstructed/distant members have finite retries and a shared movement-request budget. Eligible out-of-view followers can be recovered; visible, airborne, busy, dead or fighting actors are excluded from unsafe relocation. Temporary unloading is distinguished from confirmed destruction.

`formation_native.lua` creates one hidden, collision-free `TargetPoint` for each travelling companion. `DawnwalkerAIControllerBase:AIMoveToActor` binds it to the authored `MovementTargetActor` behavior-tree branch. The ordinary Coen follower flag is temporarily disabled; main behavior, movement physics and animation remain enabled. Marker positions follow the shared plan. The inspected native task has a 100 cm acceptance radius and does not automatically track moving goals, so the adapter offsets its marker beyond the desired seat and refreshes native intent at most once per second when travelling targets change materially. This compensates for native stopping distance without editing shared behavior-tree assets. It does not issue `MoveToLocation` corrections or run an independent separation driver.

Combat, conversation, stop, detachment and dismissal release the owned movement target and restore tracking flags. Cleanup destroys markers; a refreshed 15-second lifespan provides a fallback if updates stop. A measured stall permits two spaced native rebinds, then a six-second fallback to ordinary following. The paused native binding probe succeeded and 189 offline checks passed; visible movement still needs gameplay validation. [Rewrite design, evidence and limits](docs/FORMATION-REWRITE-V0290.md).

Sprint catch-up now becomes eligible at `max(1200, seatDistance + 600)` cm with a three-second cooldown; slower travel uses `max(1600, seatDistance + 600)` cm and five seconds. Off-camera, grounded, collision and native-action checks still apply. Registered companions retain their journey while their pawn streams out. A distant traveller reaches within roughly fourteen metres of the party before accepting a new fight. Existing fighters use the retreat detector: being over twenty-four metres behind, with their own enemy far from Coen, permits regroup after two seconds. A nearby new battle does not keep them stuck fighting the old enemy. Recovered companions can clear regrouping after 500 ms of approach/circling evidence near a current enemy; running away from that enemy keeps retreat active. They remain free to choose any eligible opponent.

Retreat uses separation/history and a latched transition to distinguish running away from repositioning. Native encounter exit is requested, uninterruptible actions may finish, and follow movement resumes afterward. It does not cancel attacks whenever the player steps. Reunion has settle conditions to prevent immediately re-entering the fight while retreating.

### Native fighting and powers

`companion_combat.lua` manages follow/combat handoff. Bounded native enemy queries select eligible current opponents near each companion. An accepted native opponent stays stable; everyone is not retargeted to the player's crosshair. Native movement, attacks, abilities, cooldowns and combat tickets then run in the game.

Remaining mod states are lifecycle states such as follow, entering combat and retreat—not player-authored tactical graphs. Combat is handed off once with finite retries for failed entry. Repeated combat-start/follow requests previously produced wandering and combat/idle oscillation.

Boss definitions carry encounter assumptions. Narrow per-clone fixes handle allegiance, guard areas, follower state and known locomotion/weapon setup. Keeping campaign follower identity active during fighting forced defensive behavior at distance; the current adapter releases it for native combat and restores it for travel/cleanup. Powers are not granted on a timer, and a visible ability list is not an exhaustive capability list: native action-tree fragments can supply abilities dynamically. Target/form/encounter/cost requirements still matter.

`companion_damage.lua` adjusts verified `BaseMeleeDamage`, `BaseUnarmedDamage` and `DamageAIvsAI` on owned clones, with readback and baseline tracking so setup cannot stack the boost. Cached damage values are checked against current native stats; native changes trigger a rebase and failed partial writes restore their owned bases. During combat, owned copies clear the forced campaign-helper damage tag and use normal physical strength as the baseline for native AI-versus-AI damage. Authored character levels stay unchanged. New installations default to 250% damage and 180% native attack frequency. No global player/shared-effect edits are used. Native armor, resistances and ability-specific damage still apply. Friendship/follower checks reduce friendly targeting but do not prove every boss area effect uses the same damage path.

Cleanup requests native exit/stow before follow and restores owned settings when appropriate. Dismissal/reload stops owned spawners and releases holds, attitudes and tracked modifications. Historical `companion_orders`/plan files remain, but the active manager does not execute tactical graphs; the bridge rejects removed plan/configure/attack/hold commands.

## Replicating this in another game

### Discover before writing

Start with a loader compatible with the target executable and confirm a heartbeat. Register input once, dispatch Unreal operations through `ExecuteInGameThread`, and keep network waits outside the game process.

UE4SS's [`DumpAllObjects()`](https://docs.ue4ss.com/dev/lua-api/global-functions/dumpallobjects.html) catalogues loaded objects and reflected members. This project used an approximately 153 MB object dump, targeted metadata inspections and a read-only asset-registry catalogue. Loaded objects are not a complete catalogue of every cooked disk asset. Dumps belong in occasional investigation, not per-frame work or forced loading of everything.

Useful searches against your own dump:

```powershell
rg -n 'SkeletalMeshComponent|AnimInstance|LinkedAnimLayer|Jali' UE4SS_ObjectDump.txt
rg -n 'CharacterName|VoiceTag|NPCDefinition|BodyType' UE4SS_ObjectDump.txt
rg -n 'Follower|MainBehaviorSuspended|StartCombat|Population' UE4SS_ObjectDump.txt
```

Dawnwalker identity evidence came from `RebelAIBlueprintFunctionLibrary.GetAIStub(actor)` → `GetNPCDefinition()` → `CharacterName`, `BodyType` and `VoiceTag`. Those are game discoveries, not portable UE4SS APIs. Verify class, property type, argument layout and owning instance before reading a value. A default object describes defaults, not necessarily a live actor's active behavior.

A reflected field existing does not prove the loader can marshal it safely. Arbitrary nested traversal, malformed container reads and guessed soft-reference layouts caused native failures during development. `pcall` cannot catch an engine access violation. Inspect bounded metadata, then one known value; log immediately before the narrow native operation being investigated. [Discovery findings](DUMP-FINDINGS.md) and [crash notes](CRASH-NOTES.md) preserve the evidence.

### Implement in observable stages

1. Prove selection/release of one actor, including destruction and reload.
2. Prove a visible facial control locally, with original-value restoration and no network dependency.
3. Map enough mouth controls for real lip shaping, and check more than one rig.
4. Connect one real Convai text request in an isolated browser; verify actual audio tracks, text and facial queues.
5. Add generation-tagged transport and reject stale output. Check repeated replies and cancellation.
6. Add UI/microphone lifecycle, identity matching and session retention.
7. Advertise a small action vocabulary, map it to reversible native behavior, and acknowledge results.
8. Add curated memory with negative recipient/rollback checks. A wiki explains events; it does not know the current save.
9. Add spawned companions with explicit ownership, async loading and stable follow/combat handoff.
10. Add group preparation only after direct replies work. Verify remote WebRTC audio, not just generated tones.

Reuse browser lifecycle/protocol concepts, but replace target discovery, facial mapping, identity, quest reading, spawning and AI control for the destination game. Do not transplant Dawnwalker indices or reflected layouts. Cache validated controller references: the supplied UEHelpers controller lookup scanned all objects, and calling it four times a second caused camera stutter. Keep global scans/recursive reflection out of party ticks.

Local reflection, logs and repeated gameplay reports establish whether Dawnwalker's implementation actually works. A delivered network action or valid-looking pointer is evidence for one layer, not proof the whole feature works.

## Build, reload and verification

### Source build

```powershell
npm ci
npm run check
npm test
npm run build
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-WebView.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -AssetLoader
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -Protection
```

These commands produce the current `companion_native_v9.dll`, `companion_assets_v2.dll` and `companion_protection_v2.dll`. `Build-WebView.ps1` expects the WebView2 SDK at `vendor/webview2/sdk`, including `lib/net462` assemblies and `runtimes/win-x64/native/WebView2Loader.dll`. It uses Windows Framework64 `csc.exe`. `Build-CompanionNative.ps1` expects Zig 0.14.1 at `vendor/zig/zig-x86_64-windows-0.14.1/`. These ignored dependencies must be supplied on a fresh checkout. Keep versions compatible with the tested loader/ABI rather than silently upgrading a native dependency.

The public source contains all C# and C source needed for the helper and native DLLs, but contains no conversation-service credential. For a developer installation, copy `examples/convai-config.example.json` to `runtime/convai-config.json`, provide your own account values locally and keep that runtime file out of source control.

Release packaging also needs `docs/THIRD-PARTY-PREBUILT.txt`, the Node and WebView2 notices under `vendor/release-licenses/`, and the browser dependency licenses under `vendor/release-licenses/browser/`. `Build-Prebuilt.ps1 -BundleSharedKey` is for an authorized release build with a configured shared-service credential; it compiles the shared configuration into the helper resource and removes the credential from the packaged runtime JSON. It emits matching **Complete**, **Scripts** and **Runtime** archives. A source user does not need that release-only switch for a developer build.

### Updates while the game stays open

| Changed layer | Apply it |
| --- | --- |
| Gameplay Lua | Save under `mod/Scripts`; the bootstrap reloads watched modules after two matching snapshots. **Existing summons are dismissed.** |
| Browser TypeScript | `npm run build`; the helper watches `bridge/public/client.js` and reloads the browser. Chat resets; party remains. |
| Node server/runtime mapping | Write `runtime/background-restart.request`; Lua's supervisor restarts the helper/server. |
| C# helper | Build with `-OutputName ConvaiHost.next.exe`, then request helper restart; the launcher swaps it. |
| Active native DLL | Use a new versioned filename, release owned companions and update the wrapper; never unsafely unload a live module. |
| UE4SS/bootstrap | Restart the game for loader/settings or stable bootstrap changes. |

The router invalidates old callbacks, avoids duplicate keys/timers and preserves the working version if an edit fails validation. The installed `live_reload.lua` module list is authoritative; old notes may list fewer modules. Pausing may defer the game-thread handover. Mod-local reload does not protect against native crashes. [Reload design](AUTO-RELOAD.md).

### Verification and measurements

The v0.30.6 foundation passed **282 automated tests**, and all 25 production Lua modules parsed. Coverage includes client coordination with mocked SDK, deduplication, identity, current captions, microphone errors, memory isolation and Lua behavior through Fengari. Native ownership guards are exercised against mocks; that cannot validate engine ABI/layouts, navigation, every power or every friendly-fire path. The user confirmed the queued-loading UI fix in gameplay. These results are carried forward as evidence for the 0.30.8 preview rather than a claim that every new or game-dependent path is validated.

Real isolated Convai tests used production browser code with fresh identities and no microphone/game input. The audio worklet check verifies silence before handoff and complete sample drainage. Actual game animation, native fighting and large-party frame pacing still need gameplay observation.

Live developer benchmarks consume ordinary Convai requests:

```powershell
node scripts/benchmark-convai.mjs runtime/my-single-benchmark prepared anca
node scripts/benchmark-group-client.mjs runtime/my-group-benchmark
```

The group benchmark needs configured Anca, Lacra and Pieter. It uses real SDK/audio/preparation but simulates Lua handoffs and limited world context. `compare-convai-models.mjs` temporarily changes Anca's cloud model and restores it; it requires the saved research catalogue and is not an offline check or startup task. See [timing definitions and measured limits](docs/CONVAI-LATENCY-V0277.md).

## Troubleshooting and references

| Symptom | Inspect |
| --- | --- |
| No F5/F6 UI | Loader log, `reload-status.txt`, helper/dependencies, `node-path.txt`, privilege match and borderless/windowed mode. |
| UI works, no connection | Runtime JSON/BOM, key ownership, IDs, account allowance, network and `overlay.json` status. |
| Only one group speaker | Nearby distinct identities, runtime mappings, available membership, aliases and `group-status.json`. Clones deliberately do not add speakers. |
| Slow reply | `group-reply-status.json` covers both modes: connection readiness, `requestToTextMs`, `requestToAudioMs`, capture/preparation and handoff. |
| Voice but no useful lipsync | Actor generation, face layer and validated array layout in `npc-diagnostics.txt`; changing the LLM cannot fix an incorrect rig mapping. |
| Input/subtitles stop | `helper-errors.log`, `webview-errors.log`, helper heartbeat and `ui-status.txt`; request a helper restart. |
| Disabled mic/empty input | Check the Windows default input/permissions, then press F7/F9 again. The green bar shows signal; `microphone-status.json` records track state, device label and whether transcription arrived. A flat meter means no detected signal. No transcription means no group message. |
| Poor companion behavior | Native combat/activity logs, exact definition, ownership and encounter assumptions. Avoid repeatedly forcing combat entry/follow as a blanket fix. |
| Edit ignored | Correct source path, watched module list, `reload-status.txt`, build timestamp and restart marker consumption. |
| Need a support report | Use **F5 → Help → Copy logs**. Paste the sanitized clipboard report or attach `support-report.txt`. |

Unqualified diagnostic names above are under `runtime/`. Use the sanitized **Copy logs** report for support rather than sharing the complete runtime folder. [TEST-NEXT.md](TEST-NEXT.md) contains the latest user check.

| Reference | Contribution |
| --- | --- |
| [Convai Web SDK](https://docs.convai.com/api-docs/plugins-and-integrations/web-plugins/convai-web-sdk), [package](https://www.npmjs.com/package/@convai/web-sdk) | Service API concepts; exact behavior checked against pinned source/types and real requests. |
| [UE4SS dumps](https://docs.ue4ss.com/dev/lua-api/global-functions/dumpallobjects.html), [reflected structs](https://docs.ue4ss.com/lua-api/classes/uscriptstruct.html) | Metadata discovery and value access. |
| [Epic MetaHuman rig description](https://dev.epicgames.com/metahuman/metahuman-dna-rig-definition-and-rig-operation) | Background for investigating RigLogic/graph inputs instead of assuming morph targets. |
| [Publisher characters](https://en.bandainamcoent.eu/dawnwalker/the-blood-of-dawnwalker/characters/), [quest policy](characters/QUEST-KNOWLEDGE.md) | Biography sources and reviewed quest-recipient information. |
| [Microsoft WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/) | Browser runtime hosted in a small Windows helper. |
| [Official gameplay/UI preview](https://news.xbox.com/en-us/2026/07/07/the-blood-of-dawnwalker-hands-on-preview/) | Visual inspiration for drawn controls; no copied game menu artwork. |
| Local dumps, asset catalogues, logs and gameplay reports | Evidence for this executable's ownership, face controls, AI behavior and visible results. |

Detailed reports: [companion implementation](docs/COMPANION-IMPLEMENTATION.md), [combat review](docs/COMPANION-REVIEW-V0267.md), [group/spacing](docs/COMPANION-GROUP-AND-SPACING-V0271.md), [group-area repair](docs/GROUP-AREA-V0275.md), [speech pipeline](docs/GROUP-PIPELINE-V0276.md), [audio/latency repair](docs/CONVAI-LATENCY-V0277.md). Some retain superseded experiments; use the current source/README for active behavior.
