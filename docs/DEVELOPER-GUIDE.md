# Developer guide

Implementation, Convai integration and porting notes for developers. Players should start with the [main README](../README.md). Build instructions are in [SOURCE-BUILD.md](SOURCE-BUILD.md).

## Development setup

### Developer requirements

The instructions below describe a **development-folder installation**. Keep the complete project at a permanent writable location such as `C:\Mods\DawnwalkerConvai`; the installed bootstrap loads code from that folder.

- Windows x64, The Blood of Dawnwalker 1.05 and the game-compatible **UE4SS 1.2.1 RC6** build.
- Node.js and npm available on PATH. Node 22 or newer is a practical baseline for the APIs used by the bridge/tests.
- [Microsoft WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/). Building the helper also requires the WebView2 SDK and Windows .NET Framework compiler.
- For a developer installation: a Convai API key, accessible character IDs and sufficient service allowance. The prebuilt shared-service edition includes its configuration. Microphone permission is needed only for F7/F9.
- Native/helper binaries listed below, supplied in a distribution or built locally. `npm ci` does not fetch UE4SS, the WebView2 SDK or the native compiler.

Required binaries in `bridge/native/`: `ConvaiHost.exe`, `Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.WinForms.dll`, `WebView2Loader.dll`, `companion_native_v9.dll`, `companion_assets_v2.dll`, `companion_protection_v5.dll`, `companion_simulation_v1.dll`, `companion_gaze_v2.dll`, and `background_launcher_v1.dll`. Retain `bridge/fonts/` and its license. Historical DLL versions and diagnostic executables are not all required for a fresh package.

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

For a new setup, copy [examples/convai-config.example.json](../examples/convai-config.example.json) to `runtime/convai-config.json` and replace every placeholder with your own values:

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

The current setup retains `fast-gemma-4-31b-it`. Three alternatives were tested without consistent speech-latency improvement. Two real short-prompt group runs measured first replies at 2.59–3.12 seconds and later replies around 40 ms after simulated handoff. These browser measurements exclude game handoff delay and are not a guarantee. Methods and limitations.

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

The portable [profile catalogue](../characters/profiles.json) and [pasteable Core Descriptions](../characters/README.md) include sourced history, directed relationships, speaking rules and original dialogue examples. The dedicated speaking-style controls can remain blank because all of that content is embedded in the verified Core Description. The current 26 cloud voices were checked against Convai's Kokoro catalogue; none is ElevenLabs. Research, update workflow, free-account setup and memory limitations.

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

**This folder is a local Git repository**, initialized on 18 September 2026. Source checkpoints and subsequent fixes are committed on `main`; no remote is configured and nothing has been pushed. `git log --oneline` lists rollback points and `git diff` shows uncommitted changes. Prefer `git revert <commit>` to undo a completed change while preserving history. Installed game binaries, credentials, runtime state, backups and release archives stay outside Git. Keep runtime conversation state separately when changing versions.

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

Before sharing source, inspect staged/package files. `.gitignore` excludes runtime, vendor, dependencies, backups and the generated browser bundle; it is not a complete release/license audit. Review built files under `bridge/native`, personal profile metadata and third-party assets. Do not ZIP the entire working folder. A source checkout requires external dependencies; a playable release must supply the required authorized binaries and configuration instructions. [The release file-structure guide](../docs/FILE-STRUCTURE.md) distinguishes source folders from the installed package.

CHANGELOG-AND-LEGACY-GUIDE.md preserves the previous README and release narrative. Older reports describe superseded keys, graphs and experiments; this README is the current entry point.

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

This excerpt illustrates baseline SDK playback and omits lifecycle/action configuration. The 0.4 bridge retains the `SpatialRenderer` and `SpatialOutput` names for compatibility, but routes both the live remote stream and prepared PCM through a gain node only. Gain stays at 1 within four metres, fades linearly to 0.85 at thirty metres, and never drops below that. Changes are smoothed over 150 ms. There is no panning, filtering, convolution or JavaScript resampling. Use the source for a complete port. Convai documents the need for audio-track attachment with custom UIs and exposes the blendshape queue for facial output. [Web SDK documentation](https://docs.convai.com/api-docs/plugins-and-integrations/web-plugins/convai-web-sdk).

`CharacterConnections` retains one client per distinct named profile/timeline. Summon requests announce connection intent before assets finish loading. Setup is staggered by 500 ms with at most two background setups pending; that limits startup work, not party size. Failures back off. Selecting a ready character promotes its existing client. Ready party connections remain available while needed; clones share their named identity. Generic identity additionally includes actor path.

A **character profile** defines the persona, a **session ID** identifies dialogue history, and **endUserId** identifies the player for cloud memory. The same end-user ID is now passed to every character and clone; Convai separates memory by character plus player. Set optional `endUserId` in the private config to reuse your existing end user. When blank, one UUID is persisted in browser local storage per API-key fingerprint. Preserve the explicit ID across key rotations, machines or WebView resets to avoid allocating another slot. Session identities include the shared player, character and local timeline; generic actors additionally include actor path. Generic actors sharing a persona have separate sessions but share that persona's cloud LTM. Clearing the WebView profile does not delete old cloud memories.

### Requests, audio, subtitles and microphone

The WinForms HUD reads `TransparentChatHud`, `HideChatBoxes`, `ShowNpcSubtitles` and `ChatHudBottomOffset` from the installed mod's `config.ini`. Numeric parsing is invariant and accepts Lua slider values such as `28.0`. Hide chat boxes overrides subtitle visibility but never disables microphone capture or audio playback. The typing control opens only on a deliberate text-chat request and Enter submits it. A shared bottom offset adds a percentage of visible screen height to the original scaled margin; viewport clamping keeps the controls on screen.

Transparency uses a colour key shared by the form and text-entry control, with outlined glyphs for readability. The overlay paints at zero opacity before being revealed and disables desktop transitions for its own HWND. Settings are refreshed on chat shortcuts and menu exit; the server clears the old display frame when the selected conversation changes. Microphone startup waits for the overlay to acknowledge the request, then keeps Connecting visible while capture is requested but not yet active. No extra capture stream is opened for the indicator.

A text request has an ID/generation. The client waits for the selected bot, replaces temporary context with `run_llm: 'false'`, clears old captions, calls `sendUserTextMessage`, and acknowledges once. New input can interrupt speech without replaying acknowledged requests after reconnect.

`ReplyTracker` snapshots old message IDs. Only fresh rows/current speech become captions; empty SDK streaming placeholders cannot keep a turn unfinished indefinitely. Initial idle is not completion. Final text, actual speech state and drained facial queues determine completion, with tail guards for delayed TTS. The direct response uses the distance-volume remote-track renderer; current captions travel through Node to the native overlay independently of the setup page.

`Microphone` serializes hardware transitions. `VoiceInput` keeps stable controls per SDK client, enables STT, verifies the live microphone publication and unpublishes stopped tracks between turns. It uses Windows default capture with no device ID/name constraint. Its local analyser reads the same published track for the input meter and has no audible output. The `userTranscriptionChange` event supplies the on-screen transcription. `heartbeat.mjs` preserves the previous timestamp across partial file reads while retaining explicit focus-loss and expiry checks. F7/F9 provide explicit request IDs. A late permission result is closed if ownership changed. Focus loss, target loss and device removal stop capture; denial/failure requires a new user request rather than retrying forever. Group voice uses the finalized first-speaker transcription once and closes capture for the responses. Preconnection and preparation never request microphone access. The native `DialogueOverlay` reads `microphoneRequested`, `microphoneOn`, `microphoneStatus`, `microphoneLevel` and `microphoneTranscript` from `overlay.json`. Connecting remains visible between selection, request acceptance and confirmed capture, then switches to Listening. Voice-only presentation uses a 560-pixel logical width, or a 220-pixel microphone indicator when chat boxes are hidden, with wrapped transcription measured separately. Its existing window scaling and focus gates also apply to this indicator; showing it does not start capture or take keyboard focus. Local selection/request errors remain visible for eight seconds.

### Simulating group conversation

`conversation-context.mjs` supplies temporary turn instructions for the `FollowUpQuestions` setting (default On). The server reads `config.ini` on its existing one-second settings/context cycle and includes the policy in both `/target` and `/group-context`. The client includes its revision in the context cache key, so switching it replaces the instruction on retained connections. Prepared replies receive the same policy using their future speaker index. Before a group voice transcript creates a round, the eligible distinct-speaker count identifies whether the first speaker should leave the closing question to someone else. Intermediate speakers never prompt Coen for the next turn; only the last normally asks one relevant question. The prompt favours asking and is selective about omitting it, allowing clear exceptions such as farewells, immediate danger or intrusive questions while still avoiding formulaic attempts to prolong the exchange. This stays out of character biographies and long-term memory and does not enable recording or generate an automatic player reply. Already generated replies keep the instructions used when they were created.

There is no shared multi-character Convai session here. `GroupChat` coordinates individual clients:

1. The addressed actor speaks first. Other available summoned members within twelve metres are ranked by explicit name mention, topic matches and weighted relationships from `companion-lore.json`, then distance. At most two more **distinct identities** are selected; twenty Anca copies are not twenty speakers.
2. The player's utterance is sent only to the first speaker and records nearby listeners. Later turns receive the immediately preceding character's line, labelled with that speaker's name, as their actual input message. The original question stays in context. This is the same for Anca/Lacra and every other group. Each response receives that character's own background/quest facts and applicable heard transcript, not another character's private context. If a speaker produces no reply, the next answers the latest available line. A companion's forwarded words cannot authorize player-only actions.
3. When first-speaker text finalizes, the second starts generating. When second-speaker text finalizes, the third can start while the first still speaks. Each prepared request uses the finalized text of its immediate predecessor, exactly as the non-prepared fallback does. This overlaps generation/playback while preserving conversational dependency.
4. `PreparedReply` stores silent PCM, caption segments, facial frames and deferred actions. `ReplyAudio` and `public/reply-capture.js` capture and replay samples on a local audio clock.
5. Lua acknowledges selection of the next actor before that reply's playback/face/actions become active. Completion waits for drained playback; the final turn releases the conversation hold.

Real Chromium WebRTC tracks sometimes yielded no Web Audio PCM until consumed by a media element. The buffer now attaches a hidden, muted, zero-volume consumer. LiveKit can unmute attached elements in `startAudio`, so zero volume also protects handoffs. Only the replay worklet outputs audible samples. Finished speech with missing PCM is an explicit failure, not silent success. Cancellation disposes buffers and annotates the client's temporary context that the prepared reply was not heard.

Short preceding replies, slow service or failed preparation can still leave gaps. A generated reply is not counted as heard until its turn finishes. See pipeline design and real audio repair/measurements.

### Dynamic context and memory

| Input | Source and lifetime |
| --- | --- |
| Persona | Cloud backstory and reviewed local personal lore; relatively stable. |
| Surroundings | Fresh game region/time/precipitation; temporary replacement context. |
| Quest knowledge | Current journal matched to explicit recipient rules; eligible facts may also enter cloud memory. |
| Heard dialogue | Completed group utterances with listeners; reported speech, not proof the claim is true. |

`environment.mjs` rejects stale/wrong-generation observations. A region is not a precise building; regional rain does not prove indoor/outdoor exposure, temperature or visibility. Weather is not continuously appended to permanent quest memory.

Lua exports a journal snapshot. `quest-knowledge.mjs` matches reviewed rules in `characters/quest-knowledge.json`: exact quest title, ID prefix, state, optional ending inclusion/exclusion patterns and recipient key. Authored facts are emitted only for that character when the conditions hold. A walkthrough explains an event; the live save proves whether it occurred. Missing state, unknown branches and unmatched active quests do not become completed facts. The system does not automatically learn every quest from a wiki or upload the whole journal to every NPC. Policy and sources.

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

The browser names Convai's 251-channel MetaHuman frames with `METAHUMAN_ORDER_251` and sends the supported `CTRL_expressions_...` mouth, eyelid, cheek, brow and nose channels. Eye-direction and head-pose channels remain excluded so native gaze stays in control. Lua matches names to its verified layout, validates array counts/types, bounds values, and restores original values/layer ownership on release. It never copies the complete remote array into an arbitrary game array.

Queue consumption uses elapsed time/source FPS rather than “one packet equals one frame.” Prepared facial/caption samples follow the captured audio clock. Browser, file bridge and game ticks sample at different rates: this is not sample-accurate synchronization, and not every 60-fps source frame reaches the game. Stale/wrong-generation data neutralizes the mouth. Native scene/dialogue ownership and object destruction take priority over retained mod handles.

JALI inspection located speech machinery, but the streaming path does not synthesize JALI clips or freeze the whole skeleton. Ordinary `SetMorphTarget` calls were insufficient on this graph. A port must first prove a writable facial control and restoration on its own rig.

## Companion implementation

### Queue, native bridge and spawn ownership

`bridge/companions.mjs` validates commands; `companions.lua` owns the party. Cooked NPC definitions determine native body/AI. Copies are created through population spawners; original quest actors are not destroyed/reassigned. Only objects belonging to recorded spawners become party members.

The F5 roster remains interactive while summon requests queue. Class/asset loads are asynchronous and polled. Mere class presence is insufficient: class/CDO initialization and postload flags must be clear. Native work/population ownership are guarded to avoid earlier overlapping-load crashes. UI progress describes pending stages rather than a fake byte percentage. Auto-close waits for the whole batch and a grace period after the latest roster interaction. Engine finalization can still cost a frame.

The small C ABI bridge exists because this loader's Lua soft-reference marshaling did not match the game's 40-byte parameter representation. Lua writes a fixed operation request and calls a no-argument export. C resolves verified engine functions/properties and returns plain data. It does not link a second Lua runtime, evaluate input as code or hardcode dump object addresses. Native parameter buffers use verified sizes and property initialization/destruction. The wrapper loads `companion_native_v9.dll`, `companion_assets_v2.dll`, `companion_protection_v5.dll`, `companion_simulation_v1.dll` and `companion_gaze_v2.dll`.

Native boundaries revalidate/re-resolve objects. Temporary async actions can expire while their population spawner still owns a pawn; retaining an action pointer caused an earlier crash. Cleanup tracks the durable owner and verifies class/lifetime. The bridge also avoids a weak-object serial-allocation path that crashed on fresh objects in this build. These are build-specific constraints, not universal Unreal guarantees.

### Following, spacing and retreat

Companions spawn in front arcs and follow in matching rear arcs. The first arc is about 2.5 metres from Coen for standard bodies, with at least 1.9 metres between assigned positions. Larger parties fill additional arcs. Larger collision capsules expand spacing. Short approaches leave settled companions still; travel resumes after a three-metre departure. Spacing, arrival correction and validation.

Fast travel retains the party roster. Super-speed travel first tries to recover existing off-camera pawns on safe navigation rather than repeatedly spawning replacements. New worlds restore companions through the queued loading path; defeated members wait until combat has ended before reviving. These changes still need gameplay validation on version 1.05.

`party_formation.lua` coordinates all companion seats once per update. Summons retain their initial front positions until departure, then follow matching rear arcs; larger parties add outer arcs. Native-locked participants reserve their actual space. A blocked seat searches nearby angles on its arc or waits. Camera turns and short approaches preserve settled positions.

`companion_recovery.lua` manages spacing/catch-up. Movement starts promptly, with run/walk hysteresis to avoid gait oscillation. Obstructed/distant members have finite retries and a shared movement-request budget. Eligible out-of-view followers can be recovered; visible, airborne, busy, dead or fighting actors are excluded from unsafe relocation. Temporary unloading is distinguished from confirmed destruction.

`formation_native.lua` creates one hidden, collision-free `TargetPoint` for each travelling companion. `DawnwalkerAIControllerBase:AIMoveToActor` binds it to the authored `MovementTargetActor` behavior-tree branch. The ordinary Coen follower flag is temporarily disabled; main behavior, movement physics and animation remain enabled. Marker positions follow the shared plan. The inspected native task has a 100 cm acceptance radius and does not automatically track moving goals, so the adapter offsets its marker beyond the desired seat and refreshes native intent at most once per second when travelling targets change materially. This compensates for native stopping distance without editing shared behavior-tree assets. It does not issue `MoveToLocation` corrections or run an independent separation driver.

Combat, conversation, stop, detachment and dismissal release the owned movement target and restore tracking flags. Cleanup destroys markers; a refreshed 15-second lifespan provides a fallback if updates stop. A measured stall permits two spaced native rebinds, then a six-second fallback to ordinary following. The paused native binding probe succeeded and 189 offline checks passed; visible movement still needs gameplay validation. Rewrite design, evidence and limits.

Sprint catch-up now becomes eligible at `max(1200, seatDistance + 600)` cm with a three-second cooldown; slower travel uses `max(1600, seatDistance + 600)` cm and five seconds. Off-camera, grounded, collision and native-action checks still apply. Registered companions retain their journey while their pawn streams out. A distant traveller reaches within roughly fourteen metres of the party before accepting a new fight. Existing fighters use the retreat detector: being over twenty-four metres behind, with their own enemy far from Coen, permits regroup after two seconds. A nearby new battle does not keep them stuck fighting the old enemy. Recovered companions can clear regrouping after 500 ms of approach/circling evidence near a current enemy; running away from that enemy keeps retreat active. They remain free to choose any eligible opponent.

Retreat uses separation/history and a latched transition to distinguish running away from repositioning. Native encounter exit is requested, uninterruptible actions may finish, and follow movement resumes afterward. It does not cancel attacks whenever the player steps. Reunion has settle conditions to prevent immediately re-entering the fight while retreating.

### Native fighting and powers

`companion_combat.lua` manages follow/combat handoff. Bounded native enemy queries select eligible current opponents near each companion. An accepted native opponent stays stable; everyone is not retargeted to the player's crosshair. Native movement, attacks, abilities, cooldowns and combat tickets then run in the game.

The mod tracks lifecycle states such as following, entering combat and retreating. Combat is handed off once with finite retries for failed entry. Repeated combat-start/follow requests previously produced wandering and combat/idle oscillation.

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

A reflected field existing does not prove the loader can marshal it safely. Arbitrary nested traversal, malformed container reads and guessed soft-reference layouts caused native failures during development. `pcall` cannot catch an engine access violation. Inspect bounded metadata, then one known value; log immediately before the narrow native operation being investigated. Discovery findings and crash notes preserve the evidence.

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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -Simulation
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -Gaze
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-BackgroundLauncher.ps1
```

These commands produce the current `companion_native_v9.dll`, `companion_assets_v2.dll`, `companion_protection_v5.dll`, `companion_simulation_v1.dll`, `companion_gaze_v2.dll` and `background_launcher_v1.dll`. `Build-WebView.ps1` expects the WebView2 SDK at `vendor/webview2/sdk`, including `lib/net462` assemblies and `runtimes/win-x64/native/WebView2Loader.dll`. It uses Windows Framework64 `csc.exe`. The native build scripts expect Zig 0.14.1 at `vendor/zig/zig-x86_64-windows-0.14.1/`. These ignored dependencies must be supplied on a fresh checkout. Keep versions compatible with the tested loader/ABI rather than silently upgrading a native dependency.

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

The router invalidates old callbacks, avoids duplicate keys/timers and preserves the working version if an edit fails validation. The installed `live_reload.lua` module list is authoritative; old notes may list fewer modules. Pausing may defer the game-thread handover. Mod-local reload does not protect against native crashes. Reload design.

### Verification and measurements

The v0.30.6 foundation passed **282 automated tests**, and all 25 production Lua modules parsed. Coverage includes client coordination with mocked SDK, deduplication, identity, current captions, microphone errors, memory isolation and Lua behavior through Fengari. Native ownership guards are exercised against mocks; that cannot validate engine ABI/layouts, navigation, every power or every friendly-fire path. The user confirmed the queued-loading UI fix in gameplay. These results are carried forward as evidence for the 0.30.8 preview rather than a claim that every new or game-dependent path is validated.

Real isolated Convai tests used production browser code with fresh identities and no microphone/game input. The audio worklet check verifies silence before handoff and complete sample drainage. Actual game animation, native fighting and large-party frame pacing still need gameplay observation.

Live developer benchmarks consume ordinary Convai requests:

```powershell
node scripts/benchmark-convai.mjs runtime/my-single-benchmark prepared anca
node scripts/benchmark-group-client.mjs runtime/my-group-benchmark
```

The group benchmark needs configured Anca, Lacra and Pieter. It uses real SDK/audio/preparation but simulates Lua handoffs and limited world context. `compare-convai-models.mjs` temporarily changes Anca's cloud model and restores it; it requires the saved research catalogue and is not an offline check or startup task. See timing definitions and measured limits.

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

Unqualified diagnostic names above are under `runtime/`. Use the sanitized **Copy logs** report for support rather than sharing the complete runtime folder. TEST-NEXT.md contains the latest user check.

| Reference | Contribution |
| --- | --- |
| [Convai Web SDK](https://docs.convai.com/api-docs/plugins-and-integrations/web-plugins/convai-web-sdk), [package](https://www.npmjs.com/package/@convai/web-sdk) | Service API concepts; exact behavior checked against pinned source/types and real requests. |
| [UE4SS dumps](https://docs.ue4ss.com/dev/lua-api/global-functions/dumpallobjects.html), [reflected structs](https://docs.ue4ss.com/lua-api/classes/uscriptstruct.html) | Metadata discovery and value access. |
| [Epic MetaHuman rig description](https://dev.epicgames.com/metahuman/metahuman-dna-rig-definition-and-rig-operation) | Background for investigating RigLogic/graph inputs instead of assuming morph targets. |
| [Publisher characters](https://en.bandainamcoent.eu/dawnwalker/the-blood-of-dawnwalker/characters/), quest policy | Biography sources and reviewed quest-recipient information. |
| [Microsoft WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/) | Browser runtime hosted in a small Windows helper. |
| [Official gameplay/UI preview](https://news.xbox.com/en-us/2026/07/07/the-blood-of-dawnwalker-hands-on-preview/) | Visual inspiration for drawn controls; no copied game menu artwork. |
| Local dumps, asset catalogues, logs and gameplay reports | Evidence for this executable's ownership, face controls, AI behavior and visible results. |

Detailed reports: companion implementation, combat review, group/spacing, group-area repair, speech pipeline, audio/latency repair. Some retain superseded experiments; use the current source/README for active behavior.


## Appearance and relationships

`companion_appearance.lua` stores choices by character key in `Payload/runtime/companion-appearance.tsv`. The menu updates the next-summon preferences without rebuilding the page. Each queue entry captures an independent copy of the selected colour IDs, including an empty preset for Original. The member retains that preset across recovery, owner replacement and world travel; later menu changes never recolour existing or queued copies. Each summoned actor gets its own material instances; shared material assets are never recoloured. Parameter discovery follows material parent chains and targets inspected eye, hair and armour channels. The menu reset only clears future-summon preferences. Actor cleanup restores original materials only while the mod owns those slots. Mesh swaps are checked periodically. A channel may have no visible effect if an outfit exposes no supported parameter.

`companion_romance.lua` reads `q.s.721.fact.anca_romance` and `q.s.717.fact.lacra_romance` from the active save's FactsDB. The bridge rejects stale or incomplete `relationships.tsv` snapshots and gives relationship facts only to the relevant character. `characters/romance-config.json` maps exact ordinary profile IDs to English or multilingual romance copies. Duplicate companions reuse that character's profile/session. The mapping is restricted to Anca and Lacra.

`AncaRomance` and `LacraRomance` are independent three-state preferences: 0 = Auto (default), 1 = On, -1 = Off. Existing 0/1 preferences remain compatible. Version 3 of `relationships.tsv` carries an effective profile flag per character: Auto follows confirmed story romance or a previously recorded encounter; explicit On or Off overrides profile selection regardless of those facts. Relationship evidence is still reported truthfully. Automatic activation is derived from the current save and never written into the manual preferences, so it does not leak into an older save. The menu cycles Auto, On and Off. The bridge also reads version 2 snapshots for compatibility. The obsolete shared RomanceCharacterID and EarlyRomance settings are ignored. No new encounter counters or quest facts are written.

For group chat, `groupRomanceContext` adds shared relationship awareness only for Anca/Lacra when a fresh save snapshot confirms both romances and both are in the nearby conversation audience. Profile toggles alone do not establish either romance. The same recipient context feeds live and pre-generated replies, and speaker selection prioritises the pair while keeping the three-speaker limit. The prompt encourages distinct, brief banter and replies to earlier spoken lines, without inventing an exclusivity agreement, prior confrontations or quest outcomes. Private chats and absent participants receive no shared-romance context.

Romance support is conversation-only. No scene action is advertised or accepted, and the mod does not change the player camera, outfit, position or game time for romance. Story relationship facts and previously recorded encounter counters remain readable for save compatibility.

Appearance rows render the game's `WBP_Settings_Control_Picker` widget without a colour-swatch box. The native picker supplies the artwork, with explicit left/right arrow targets and a mod-owned value label to prevent its delayed placeholder refresh from replacing the selected colour; separate CommonUI click targets and the menu's keyboard routing save the mod's character presets. The stock widget is not assigned a game settings entry, and its input is disabled so colour choices cannot alter unrelated game settings.

Clothing tinting has been removed, including its mesh refresh and dye writes. Old saved clothing entries are ignored. The remaining channels continue to create actor-owned dynamic material instances and restore the original materials on reset or cleanup.

The captured family definitions distinguish civilian/follower AI from Pieter's dedicated combat AI. Protection applies only to summoned non-fighters: damage is disabled and pairwise friendly attitudes are leased between each protected actor and nearby enemies. The leases do not alter enemy damage, global factions or enemies' attitudes toward Coen. Fighting companions retain the existing native combat controller.


## Camera and Horde lifecycle

`first_person_camera.lua` owns one temporary CameraActor and a controller view-target lease. It uses the player capsule position plus native BaseEyeHeight, control rotation and current FOV. Walking and running head-socket animation no longer moves the camera through the torso. The bootstrap allows one pending native EngineTick callback at a time. That callback runs the 16 ms application dispatcher, file polling and hot reload on the game thread; nested application dispatch executes inline rather than registering another native callback. The dispatcher updates the camera and schedules conversation work at approximately 33 ms and companion work at 250 ms. Quest and environmental reads run only with a selected conversation target, relationship reads run during chat or an open menu, and an empty party bypasses combat and formation work. A two-second watchdog retries a lost callback; generation tickets prevent superseded callbacks from running. This avoids independent pending flags that could leave the camera stopped after a rejected callback. The mode retains its camera and body mask through the mod menu and immediately reapplies its view after resume. A bounded menu-transition allowance handles the native pause input blocker, while actual finishers and cinematic dialogue still release the camera. Other native input blockers also take priority. Single/group text and voice chat retain first-person view; the composer only borrows movement, look and mouse input. It restores the pawn view only when the same controller still views its owned camera, then destroys that camera. The owned camera belongs to the player pawn. Only that pawn’s base body, face, hair, beard, eyebrows, torso and headgear components receive temporary owner-only hiding, with hidden shadows retained. Hands, gauntlets, legs, weapons and other actors are excluded. A local component refresh handles equipment swaps twice per second without an object-array scan. Original visibility and shadow flags are restored on every camera release, including native scenes, pawn changes and hot reload. Global actor visibility, collision and animation are unchanged. The camera disables aspect-ratio constraining and exposes FOV, eye-height offset and forward offset through the shared settings schema. FOV is written only when its configured value changes. These controls affect only the owned mod camera. This is an experimental viewpoint, not a new animation set.

`horde_catalog.lua` defines ten normal encounter themes and a separate Nightmare boss pool. The ten themes use 39 verified catalogue IDs and reject story-category paths even when those paths also appear under combat entries. Nightmare explicitly allows verified boss definitions, including hostile copies of vampire characters. `horde_native.lua` uses the async class/asset loader and population bridge with separately owned action handles. No handle is inserted into the companion registry, so companion tuning, recovery and friendly-fire protection are not applied to horde enemies. Hostility is instance-specific, and pairwise friendly attitudes between owned enemies prevent different enemy species fighting one another. The encounter does not write quest facts, shared definitions or global faction defaults.

`horde_mode.lua` progresses through preparing, loading, armed, combat and rest phases. Settings are snapshotted per run: 8 starting regular enemies, 2 added per level, 10 levels, 1 extra boss per level and a 10-second rest by default. Enemies load serially at projected walkable positions ahead of the player. Each owned actor stays hidden, collision-free, damage-disabled and AI-suspended during preparation, with temporary friendly player attitudes. Once every actor is ready and a one-second settling period passes, the complete wave becomes visible and hostile. The adapter registers the player as combat instigator, initializes inspected native weapon state and retries combat entry while no live native target exists. It leaves target and attack choices alone once native combat owns them. Player attitude leases are restored on cleanup. Already-resident dependencies are traversed in a bounded pass; no synchronous asset-load loop is used. The player enters combat through the normal game combat system, after which native AI owns individual attack choices.

A cleared wave requires confirmed deaths for all available enemies, with at least one actual kill. Missing AI is never counted as a kill. The adapter reacquires the current stub and board only from its owned pawn, with recovery attempts limited to once per second. Preparation and combat allow five seconds for reattachment, then remove only the broken population after its exact owner confirms cleanup. Failed preparations are likewise omitted rather than ending the whole wave. Omitted entries are reported separately; an entirely unavailable wave ends with an error instead of awarding a clear. Death checks consult the retained board before requiring live AI; health fallback requires prior positive health plus the native IsAlive result to avoid counting initialization as death. Confirmed bodies keep their population handles so ragdolls settle naturally, and remain through later waves and ordinary run completion. World resets and hot reload perform full cleanup; naturally unloaded bodies release their remaining handles. Death, a changed world/player, travel, or leaving the encounter ends and cleans up the run. A five-second quiet period outside combat distinguishes retreat from a momentary combat-state change; moving more than 140 metres from the encounter also ends it. End horde stops only horde-owned population handles. Individual companion dismissals do not end a run. Whole-party resets release horde ownership before the native bridge's global stop, and hot reload does the same. Cleanup failures remain retryable.

Game time drives rest intervals, so pause does not spend the countdown. `horde-state.tsv` is a fresh versioned status snapshot; the helper derives only a display string from it. `DialogueOverlay.cs` shows this text only when there is no composer, microphone panel or conversation subtitle. Conversation text/generation is never overwritten by the horde timer.

### Settled follower attention

The party manager reuses the formation position snapshot to select stationary, settled followers outside combat and native actions. Chat selection alone does not remove a follower from this system. Camera direction is not a selection condition. Each eligible actor has an independent attention lease: up to two nearby companions focus on Coen directly, while others focus roughly 22 degrees to either side of his direction. Native FaceDirection/KeepInFOV locomotion supplies animated turns without setting actor rotation or blocking movement. Direct-attention distance hysteresis limits switching between nearby companions. Sight checks are cached for two seconds. New attention waits until the party has settled for one second, then attempts at most one new lease per 250 ms party update. Existing leases tolerate small movement and destination drift to avoid repeated teardown during idle shuffling. Unsupported actors back off rather than preventing later companions from acquiring attention.

Focus-point updates have a movement threshold. Cleanup pops only owned rotation/look handles and restores the earlier focus only if the controller still has the mod's focus. Travel, combat, explicit action ownership, dismissal and world resets release these leases. Chat keys alone leave them intact for summoned companions. Formation clearance remains based on capsule size; small approach movements leave settled destinations parked.

### Asset lookup across save reloads

Asset caches require identity checks in addition to `IsValid`. During save reloads, a cached class address was observed being reused for a transport-waypoint actor while UE4SS still considered the wrapper valid. `companion_native.lua` and `ai_state.lua` compare the object's full path with the requested path before reusing it. Invalid identities are discarded and resolved again, before any class-specific call such as `GetCDO`. Save/world cleanup also clears these Lua lookup caches without changing native population ownership. This preserves fast cached lookups while preventing a stale object from hiding an already loaded character class.

### Horde melee equipment

Before activation, `prepareEquipment` registers each owned enemy's weapons with its native AI equipment proxy. Inventory weapons use the definition's `EquipmentSlotMapping` and `BP_EquipInventoryWeapon`. Enemies without inventory weapons use their authored `EnemyConfig.HandToHandWeapons`, translated through `WeaponSlotToGenericCharacterSlotTag`, and `BP_EquipWeaponClass`. Setup is retained per proxy and repeated after AI reattachment, not on every combat tick.

This distinction fixes hits that animated and connected without reducing player health. `CombatComponent:SpawnEquippedWeapon` could create a visible sword while leaving the new AI's equipment lookup empty. The native melee path needs that lookup to resolve the attacking weapon. The repair uses native damage, block and dodge handling rather than subtracting player health directly. It changes only Horde-owned actors, with no shared asset edits or changes to companion protection. Gameplay confirmed the repair on existing enemies and then on a fresh wave using automatic setup.

### Recent battle observations

`companion_combat.lua` keeps up to three session-local battle records. `companions.lua` reuses its nearby enemy query, records native NPC names and nearby party identities, and takes one context snapshot at fight start. With no party, context requests one nearby-enemy query at fight start; it does not repeat that query during the fight. Ordinary combat ending does not imply victory. `horde_mode.lua` supplies actual prepared enemies, confirmed deaths and wave-clear events, including the rest between waves. No UObject references are retained in the journal. Enemy identities and nearby witnesses are captured once at fight start or once per fully prepared horde wave. Later reinforcements in ordinary battles may be absent from this initial snapshot. Only ended battles and cleared or ended horde waves are published to conversation context.

The bounded `battle-context.tsv` snapshot is refreshed at most once a second. `bridge/battle-context.mjs` rejects stale snapshots and observations older than 30 minutes. Its text is injected into the selected speaker and prepared group replies. The bridge distinguishes a confirmed nearby witness from a character receiving a report. These observations are not uploaded as permanent quest facts; reset, save/world transitions and live reload clear the local journal.

### Shortcut helper permissions

The helper must have matching Windows permissions to receive the game keyboard input. The native in-game launcher already inherits the game token. If an external restart leaves a normal-permission helper beside an elevated game, the helper requests a game-managed relaunch and exits. No UAC configuration is changed. `input-status.txt` and `input-last-key.txt` are included in the sanitized support report.

### Off-screen follower locomotion

The driving skeletal mesh must continue evaluating root motion while it is outside the camera. `VisibilityBasedAnimTickOption = 0` alone is insufficient for a registered `SkeletalMeshComponentBudgeted`. Its reflected `SetAutoRegisterWithBudgetAllocator` setter only changes the future-registration flag; it does not unregister the existing allocator entry.

`companion_simulation_v1.dll` leases the allocator's native `SetComponentSignificance` flags on each owned companion's driving mesh: never skip, tick even when not rendered, no reduced work and no forced interpolation. The helper verifies the reflected layout, native implementation signatures, allocator array bounds and the mesh identity in the registration before calling the native API. Unknown layouts fail closed. It retains no native object pointers between requests. Lua keeps the previous scheduling flags and restores them when the lease ends, provided the flags still match our override. Face, hair and clothing meshes retain the game's normal animation budget. This is performed once per mesh lease, not on every update, and no global animation budget is disabled.

Follow pace uses both player speed and distance from the assigned formation seat. A follower that remains far away gets a bounded private locomotion-profile boost even after the player stops. The boost tapers as the gap closes and releases for combat or a nearby settled position. Shared profiles, enemies and attack animation speeds are untouched.

Camera gaze uses `companion_gaze_v2.dll` to construct a reflected actor look target bound to a hidden, non-ticking CameraActor used only as a gaze anchor. Engine `ImportText_Direct` allocates the instanced target, permanent tracking policy and weak actor reference; reflected parameter initialization and destruction own their lifetime. Lua stores only the returned handle and removes that handle when attention ends, combat starts or the camera changes. The game follows the camera each frame, without repeated native bridge calls or writes to animation bones. Third-person attention uses RebelAI's normal player-face target. The request is checked once per second while attention is active; this does not add a global actor scan.

The gaze anchor is created lazily when first-person attention needs it and destroyed with the camera lease. The existing camera update positions it relative to camera-local right/up using `GazeHorizontal` and `GazeVertical`. Only the actual camera is assigned as the view target. Both offsets have a -20 to +20 cm range and default to +5/-1 cm. No additional timer or scene scan is used.

### Conversation expressions

The Web SDK connection enables `enableEmotion` with the contextual LLM provider. Its documented `emotionChange` signal supplies a label and an intensity from 1 to 3 after a character turn; the client does not wait for that event before playing audio. `facial-expression.ts` maps labels into joy, trust, sadness, anger, fear, surprise, disgust and anticipation, with unknown labels returning to neutral. A small initial listening smile gives way to detected mood. Reactions stay through speech, hold for two seconds after speech or a later emotion event, then crossfade back to the listening smile over three seconds. Neutral or unknown labels also return to that resting smile rather than leaving an empty expression indefinitely. Mouth/chin expressions use the fixed numeric inputs. Eighteen upper-face controls use the owned instance's ModifyCurve curve map: blinking, eye widening, cheek raising, inner squint, brows and nose. A fresh linked layer receives the keys before its first animation tick; subsequent updates change existing float values only. No game-wide defaults or other characters' maps are modified. Eye direction stays native. Expressions ease in and out, are attenuated during speech and strong lip closures, and never replace the speech jaw curve.

The expression travels inside the existing generation-stamped weight frame, with no extra per-frame request. Resetting the target/connection clears its mood. Prepared group replies capture their own emotion events and reveal them only when that speaker is activated; an emotion already known before playback can apply from the start. Native face-layer restoration also restores expression inputs. Runtime reply diagnostics expose the active mood and whether it came from Convai or the initial greeting.

First-person gaze reads both uppercase and lowercase rotator members because this UE4SS build returns `Yaw` alongside `pitch`. An isolated gaze-update error retains the camera and body mask and can recover on the next update. Grounded first-person gameplay leases low-priority FaceDirection and KeepInFOV movement modes so native turning follows large look changes. The owned mode handles release during input holds, airborne movement, camera teardown and native scenes; higher-priority native rotation modes remain eligible. No direct capsule rotation or animation-bone writes are used.

Idle greeting smiles are owned by the existing companion attention lease, limited to the two nearby direct-attention companions with conversation support. Selecting a summoned companion transfers only its existing facial lease to the conversation writer. Following, focus, rotation/look handles and native head targets remain under the party manager, so F6 through F9 do not stop actions or change the speaker's movement mode. The selected actor stays eligible for normal party attention, but its idle smile writer is disabled while conversation frames own the face. When selection ends, the face returns to its compatible idle attention lease without relinking or resetting the blink clock; otherwise the previous native layer is restored. World NPCs and explicit movement actions retain their separate hold adapter.

Face acquisition enumerates only the character's own ungrouped linked instances with `GetLinkedAnimLayerInstancesByGroup`, rather than scanning every animation class. It refuses an ambiguous or missing previous layer. A shared face tick runs at roughly 30 Hz while owned faces exist, independently of the slower party and idle UI work. It supplies eased blinks every 2.8 to 6.5 seconds, combines them with speech blinks, and pauses its clock with the game. Upper-face float values are written when they change, with a once-per-second refresh. This supplies eyelid motion while the speech layer replaces the original expression layer. Release restores captured inputs and the original layer.

The gaze helper keeps a bounded cache of borrowed engine weak identities for previously resolved actors and camera anchors. Every reuse validates the engine serial, so destroyed objects are never used as cached raw pointers. Where both camera and function identities support weak references, the initialized reflected look-target template can also be reused. Otherwise normal reflected construction remains in place. A paused-game check measured repeated acquisition at 0 to 16 ms with zero object lookups, compared with 109 ms for the initial lookup; this is a narrow helper measurement, not an end-to-end frame-time guarantee.

Conversation requests for the same live actor revalidate the attached face instance, then renew the request generation and room without rebuilding animation state. Automatic five-second AI dumps and per-second lip-curve debug logging have been removed; explicit diagnostic commands remain available.

### Arrival and native look-target tolerance

The native destination adapter settles within 100 cm of its planned seat, or within 145 cm when native navigation has already gone idle. It keeps that idle state through 145 cm of small root-motion drift. Attention accepts the same settled position, with a 150 cm tolerance, instead of demanding a second movement correction. Previously, actors 81 to 100 cm from the seat neither settled nor qualified as stalled, leaving movement active indefinitely. Genuine no-progress routes now retry after two seconds, with the existing two-retry cap and six-second fallback interval.

Dawnwalker can emit a transient controller look target each frame with a three-second lifetime. A paused runtime export showed 180 ordinary controller targets at approximately 60 Hz; higher frame rates can exceed the old 256-entry guard. The bounded inspection guard is now 4096. Existing game targets are not deleted, and the mod still releases only its own handles. A read-only native `gaze` audit can export these targets when investigating tracking failures.

Parked formation seats reserve their space before arriving destinations are resolved. The planner never moves a parked companion merely because another planned seat overlaps it. Attention acquires only after the native formation lease is settled in the current journey, so arrival's `AIStopFollowing` cannot clear newly acquired focus.

`FollowerCloseness` controls rear depth (100 divided by the percentage); `PartySpacing` scales formation pitch. The layout computes a minimum depth from pairwise capsule clearance and Coen's space, without a second movement driver. That calculation runs when membership or the two settings change, not each tracking tick. Seat geometry snapshots the settings for a journey; a stationary party keeps its current geometry until actual following resumes. Both controls default to 100% and appear in the native menu, Settings guide and `config.ini`.

`NarrowFormation` defaults to 0. When enabled, `followOffset` uses slightly staggered rows rather than the rear fan. The column count grows with the square root of party size, limiting depth for large parties without eliminating lateral spacing. Closeness and capsule-clearance calculations still apply. The planner snapshots this option with the other formation settings for each journey, so changing it while stationary or rotating the camera does not trigger formation churn. No additional runtime loop or visibility scan is introduced.


### Player conveniences and exploration reactions

The F4 camera action reuses the existing settings and camera lease. It uses the helper's foreground-only shortcut registration, including the text-editing and native-menu guards. Camera is the sixth remappable action. When an older keybindings file has no Camera entry, both Lua and the helper select the same unused function-key fallback rather than stealing an existing binding.

`player_abilities.lua` applies the native `GE_AllowHumanAbilities` and `GE_AllowVampireAbilities` effects through the protection helper. The helper verifies a player-controlled pawn, retains the exact effect handles and a borrowed engine weak identity for its ASC, and removes only its own handles on disable or cleanup. Skill trees, costs, the world clock and NPC attributes are unchanged. It checks player identity once a second only while enabled. Both native effects and the opposite-time ability use were verified in the running game.

`player_passives.lua` considers learned `FocusAbilityBase` traits whose `IsAbilityPassive()` is true. It temporarily marks those traits `AlwaysEquippedWithoutSlotCost` and reconciles their native grants through `SetCombatFocusAbilityActive`, using the current learned level. It does not purchase skills or write saved quickslots. Disabling restores the earlier flag and removes extra grants only when the trait is not normally equipped. Player/world changes release the lease; reconciliation is limited to once every two seconds while enabled.

`auto_loot.lua` queries the game's `RebelSpatialSystem.Layers.FocusDetectors` index within 350 cm, with the reflected container handled in a native parameter frame. It does not scan all actors or require physics collision on herbs. Work stops in combat, menus, cutscenes or pause and resumes after two quiet game-time seconds. One candidate is handled per party tick, with per-object retry delays. Native interaction state, risk, theft, lock and visibility checks gate pickup. For small harvestables with embedded pivots, a visibility trace to GetPromptLocation can accept the visible interaction point within the same reach limit; containers retain their original visibility check. Only loot containers, defeated characters, LootableComponent and HarvestableComponent are eligible. Resources use `StartInteraction` to run the full native pickup lifecycle; `InteractionTriggered` alone does not collect harvestables. Containers and defeated characters use `InventorySubsystem.TransferAllItems` in Looting mode, preserving inventory transfer rules. Summoned companions are excluded. On game 1.05, `GetElementsFromLayersInDistance` discards its result, so the native bridge uses synchronous `RunQuery` with an initialized `RebelSpatialQueryRequest`. Lua enumerates components through `K2_GetComponentsByClass`. Do not reject `IsQuestInteractable()`: ordinary lootable animal corpses also return true. The component type whitelist avoids activating arbitrary quest interactions.

`ambient_comments.lua` reads the current world cinematic subsystem at the existing party cadence when a talking companion is nearby. Both automatic reaction settings default to Off. It accepts live Gameplay (1) and CinematicGameplay (2) observations attributed to Coen only after inspecting the authored dialogue graph: all response speakers must be `Character.Main.Coen`, with no choice or nested dialogue nodes. Tower observations use CinematicGameplay and were previously rejected. Full cinematic/cutscene modes and generic Voicesets assets stay excluded. Harmless fact conditions/branches are allowed; unknown, oversized and multi-speaker graphs fail closed. Inspection is bounded at 512 nodes to include the 187-node shared NanoPOI graph with climbing observations. Classification and rejection reasons are cached per graph until world reset; there are no recurring global scans. It inspects both the active native dialogue and active gameplay dialogues, reads `ActiveResponseText` and waits until the solo scene has ended plus two seconds of quiet. Unrelated background NPC speech does not discard a solo observation. Coen speaking in a multi-speaker graph or entering a native cinematic conversation still cancels it. Combat, native scenes, pause and composing suppress the observer. A three-minute cooldown, five-minute repeated-line filter, short expiry and fresh helper readiness gate prevent chatter from accumulating. No audio recording or global dialogue hook is used.

The observation enters `ambient-message.tsv` with a generation, room ID and timestamp. `ambient-comments.mjs` rejects stale or mismatched requests, and the server uses the existing text request queue, voice, subtitle and facial animation pipeline. Per-request dynamic context asks for a short grounded reaction, without follow-up questions or actions. Manual conversations retain their normal context and take priority.

Nightmare is the explicit exception to ordinary Horde story-path exclusion. It uses independent hostile copies of verified boss assets, including alternate boss forms and minibosses. It does not change existing companions or campaign instances. The catalogue contains 32 unique boss paths. Nightmare has its own start button, separate from the ten normal themes. Each round draws starting enemies plus growth plus additional bosses from a shuffled bag retained across rounds. The bag refills only when exhausted and avoids repeating the boundary entry. The complete group stages and activates through the same pipeline as a normal Horde wave; there is no one-at-a-time combat restriction.


### Batched item reactions and skills outside shrines

`loot_comments.lua` observes player and storage inventories once per second while a talking companion is nearby. It baselines on activation, pawn/world changes and game-time rollback. Positive player deltas are reduced by matching storage withdrawals; storage-only batches never trigger speech. Six quiet seconds merge multiple pickups into one event. Unknown acquisition sources remain unknown in the dynamic context rather than being described as a chest or a battle. Only Unique rarity (6) on clothing (6) or weapons (7) qualifies for the special equipment exception; Quest rarity (7) does not. Equipment present in the initial inventory/storage baseline or already observed this session cannot repeatedly trigger that exception.

`reaction_policy.lua` rolls a 20% chance for ordinary loot with a 600-second minimum. Eligible solo Coen observations have no random roll and a 180-second minimum. New Unique equipment bypasses ordinary chance/cooldown but has its own 120-second floor. A shared 30-second floor prevents the reaction types talking over one another. Both reaction settings default On, while explicit saved choices are preserved. Timestamps persist in local `reaction-cooldowns.tsv` across save loads and reloads. Busy conversations, native dialogue, combat and menus defer or discard observations rather than interrupting the player. Loot events use one random eligible companion and temporary Convai context, not profile changes or group conversation.

`skills_anywhere.lua` leases the live native character-development details widget's `Skills Purchasable` property through `Set Skills Purchasable`. The read-only `Requires Roadshrine` result was verified to change from true to false and back when the lease is released. No skill unlock function, currency cost or quest prerequisite is bypassed. Widget discovery runs only while paused and enabled, and notification tooltips are excluded. The optional setting defaults Off. Test skill points were granted once locally through `ReceiveTraitPoints(2)`; that grant is not part of the shipped feature.

`companion_settings.repairConfig` adds missing schema defaults and resolves duplicate/invalid values only in the Companions section. It preserves other sections and valid values. F5 repairs before loading native menu controls, whose config binding requires exactly one matching assignment. The process is idempotent and supports UTF-8 BOM files.

### Fast travel from anywhere

`fast_travel.lua` temporarily enables `MapWidget.FastTravelEnabled` and the separate `WBP_Map_PinTooltip.IsFastTravelEnabled` gate on visible live map widgets while the setting is On and the player is safely outside combat and cinematics. It checks at most once per second while paused, with no exploration actor scans, and invokes the tooltip's native `Setup Fast Travel Button` only when its gate changes. The normal map disables tooltip travel independently, so the map flag alone is insufficient. The native setup retains pin-type and unlock-state checks; the mod never forces button visibility. Original values are restored on close, disable, world reset and hot reload. Shrine unlocks are unchanged. Other visible map icons and custom waypoints gain a separate native DWW button in the tooltip action box. The native map FastTravel action (F on keyboard, with its normal controller glyph) activates the added button. One press captures the current pin and starts travel. A cancellable native `AsynAction_RequestLoadingScreen` request is activated before closing the map and held through arrival, then released on completion, cancellation, timeout or reload. Coordinates come from `GetMappinInstanceLocation`; the request captures them so later hovering cannot retarget it. A temporary hidden CameraActor hosts a WorldPartitionStreamingSourceComponent at the destination, following [Unreal's destination-preloading pattern](https://dev.epicgames.com/documentation/unreal-engine/world-partition-in-unreal-engine). After streaming completes, bounded floor traces and a player-sized capsule clearance check find a standing position within three metres. The UE4SS HitResult table exposes its packed blocking/start-penetrating flags incorrectly in this build: a normal floor hit reports both as true. Ground validation therefore checks positive trace time and distance, zero penetration depth, a walkable normal and a separate full-capsule sweep. Failure or a 45-second timeout cancels without moving the pawn. Transition and cancellation reasons are written to `fast-travel-status.txt`. The WorldSubsystem `FastTravelSystem.FastTravelToLocation` owns actual travel, its safety platform and streaming handoff; the native hub closes after the loading-screen request, before waiting for preloading, because paused World Partition activation cannot complete. No direct pawn teleport or collision disabling is used. Disabling the setting, combat, world resets and hot reload cancel the temporary source. The loading screen covers preload and the destination remains fixed. `FastTravelAnywhere` defaults to 0 and uses the shared configuration repair.

### Passive abilities during save reloads

`CharacterDevelopmentSubsystem` is game-instance scoped and can remain valid after its weak `PlayerASC` is cleared. The save-reload crash entered `SetCombatFocusAbilityActive` and dereferenced that empty reference. `player_passives.lua` now resolves `PlayerASC:Get()` and checks that its live object address matches the current player ASC before either granting or removing a passive. An unbound or replaced ASC only releases the temporary trait flags; it never invokes the native ability setter. UE4SS documents that [resolving a weak object can return an invalid UObject](https://docs.ue4ss.com/lua-api/classes/fweakobjectptr.html), so subsystem validity alone is insufficient.

The same audit added `ai_state.playerReady` and `playerAbilitySystem` checks for possession, actor destruction, world identity and the ASC avatar. Day/night ability updates, auto-loot, loot observations, Coen observations and relationship reads wait for live player context. Loot transfers and snapshots require the inventory subsystem to point to the loaded pawn’s own inventory. Skill-menu changes require the current development binding; map and skill widgets retain their original pawn/world identity and are not called during old-save teardown. Travel source cleanup skips actors already being destroyed. These guards use the existing utility cadence, without additional scanning or timers.
