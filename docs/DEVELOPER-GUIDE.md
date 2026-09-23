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

Required binaries in `bridge/native/`: `ConvaiHost.exe`, `Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.WinForms.dll`, `WebView2Loader.dll`, `companion_native_v9.dll`, `companion_assets_v2.dll`, `companion_protection_v2.dll`, and `background_launcher_v1.dll`. Retain `bridge/fonts/` and its license. Historical DLL versions and diagnostic executables are not all required for a fresh package.

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

A text request has an ID/generation. The client waits for the selected bot, replaces temporary context with `run_llm: 'false'`, clears old captions, calls `sendUserTextMessage`, and acknowledges once. New input can interrupt speech without replaying acknowledged requests after reconnect.

`ReplyTracker` snapshots old message IDs. Only fresh rows/current speech become captions; empty SDK streaming placeholders cannot keep a turn unfinished indefinitely. Initial idle is not completion. Final text, actual speech state and drained facial queues determine completion, with tail guards for delayed TTS. The direct response uses the distance-volume remote-track renderer; current captions travel through Node to the native overlay independently of the setup page.

`Microphone` serializes hardware transitions. `VoiceInput` keeps stable controls per SDK client, enables STT, verifies the live microphone publication and unpublishes stopped tracks between turns. It uses Windows default capture with no device ID/name constraint. Its local analyser reads the same published track for the input meter and has no audible output. The `userTranscriptionChange` event supplies the on-screen transcription. `heartbeat.mjs` preserves the previous timestamp across partial file reads while retaining explicit focus-loss and expiry checks. F7/F9 provide explicit request IDs. A late permission result is closed if ownership changed. Focus loss, target loss and device removal stop capture; denial/failure requires a new user request rather than retrying forever. Group voice uses the finalized first-speaker transcription once and closes capture for the responses. Preconnection and preparation never request microphone access. The native `DialogueOverlay` reads `microphoneRequested`, `microphoneOn`, `microphoneStatus`, `microphoneLevel` and `microphoneTranscript` from `overlay.json`. Listening appears only after capture is verified; the overlay does not display a preparation splash. It renders an independent 480-pixel-wide logical panel for voice alone, with height measured from wrapped transcription, or adds a separate strip below a current subtitle. Its existing window scaling and focus gates also apply to this indicator; showing it does not start capture or take keyboard focus. Local selection/request errors remain visible for eight seconds.

### Simulating group conversation

There is no shared multi-character Convai session here. `GroupChat` coordinates individual clients:

1. The addressed actor speaks first. Other available summoned members within twelve metres are ranked by explicit name mention, topic matches and weighted relationships from `companion-lore.json`, then distance. At most two more **distinct identities** are selected; twenty Anca copies are not twenty speakers.
2. The player's utterance records nearby listeners. Each response receives that character's own background/quest facts and applicable heard transcript, not another character's private context.
3. When first-speaker text finalizes, the second starts generating. When second-speaker text finalizes, the third can start while the first still speaks. This overlaps generation/playback while preserving conversational dependency.
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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-BackgroundLauncher.ps1
```

These commands produce the current `companion_native_v9.dll`, `companion_assets_v2.dll`, `companion_protection_v2.dll` and `background_launcher_v1.dll`. `Build-WebView.ps1` expects the WebView2 SDK at `vendor/webview2/sdk`, including `lib/net462` assemblies and `runtimes/win-x64/native/WebView2Loader.dll`. It uses Windows Framework64 `csc.exe`. The native build scripts expect Zig 0.14.1 at `vendor/zig/zig-x86_64-windows-0.14.1/`. These ignored dependencies must be supplied on a fresh checkout. Keep versions compatible with the tested loader/ABI rather than silently upgrading a native dependency.

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


## Appearance and relationships in 0.4

`companion_appearance.lua` stores choices by character key in `Payload/runtime/companion-appearance.tsv`. The menu updates preferences without rebuilding the page. Each summoned actor gets its own material instances; shared material assets are never recoloured. Parameter discovery follows material parent chains and targets inspected eye, hair and armour channels. Reset restores the original material only while the mod owns that slot. Mesh swaps are checked periodically. A channel may have no visible effect if an outfit exposes no supported parameter.

`companion_romance.lua` reads `q.s.721.fact.anca_romance` and `q.s.717.fact.lacra_romance` from the active save's FactsDB. The bridge rejects stale or incomplete `relationships.tsv` snapshots and gives relationship facts only to the relevant character. `characters/romance-config.json` maps exact ordinary profile IDs to English or multilingual romance copies. Duplicate companions reuse that character's profile/session. The mapping is restricted to Anca and Lacra.

`AncaRomance` and `LacraRomance` are independent manual preferences, both defaulting to 0. Version 3 of `relationships.tsv` carries an effective profile flag per character: confirmed story romance, a previously recorded encounter, or manual activation enables that character’s romance ID. Automatic activation is derived from the current save and never written into the manual preferences, so it does not leak into an older save. The menu shows automatic activation as On. The bridge also reads version 2 snapshots for compatibility. The obsolete shared RomanceCharacterID and EarlyRomance settings are ignored. No new encounter counters or quest facts are written.

Romance support is conversation-only. No scene action is advertised or accepted, and the mod does not change the player camera, outfit, position or game time for romance. Story relationship facts and previously recorded encounter counters remain readable for save compatibility.

Appearance rows render the game's `WBP_Settings_Control_Picker` widget without a colour-swatch box. The native picker supplies the artwork, with explicit left/right arrow targets and a mod-owned value label to prevent its delayed placeholder refresh from replacing the selected colour; separate CommonUI click targets and the menu's keyboard routing save the mod's character presets. The stock widget is not assigned a game settings entry, and its input is disabled so colour choices cannot alter unrelated game settings.

Clothing tinting has been removed, including its mesh refresh and dye writes. Old saved clothing entries are ignored. The remaining channels continue to create actor-owned dynamic material instances and restore the original materials on reset or cleanup.

The captured family definitions distinguish civilian/follower AI from Pieter's dedicated combat AI. Protection applies only to summoned non-fighters: damage is disabled and pairwise friendly attitudes are leased between each protected actor and nearby enemies. The leases do not alter enemy damage, global factions or enemies' attitudes toward Coen. Fighting companions retain the existing native combat controller.


## Camera and horde lifecycle in 0.4

`first_person_camera.lua` owns one temporary CameraActor and a controller view-target lease. It reads the player head socket (with BaseEyeHeight fallback), control rotation and current FOV. One 16 ms dispatcher updates the camera and schedules conversation work at approximately 33 ms and companion work at 250 ms. A two-second watchdog retries a lost callback; generation tickets prevent superseded callbacks from running. This avoids independent pending flags that could leave the camera stopped after a rejected callback. The mode yields to the native menu, chat input, input blockers, finishers and active cinematic dialogue. It restores the pawn view only when the same controller still views its owned camera, then destroys that camera. It does not hide or replace player meshes. This is an experimental viewpoint, not a new animation set.

`horde_catalog.lua` defines ten encounter themes using 39 verified catalogue IDs. It rejects story-category paths even when those paths also appear under combat entries. `horde_native.lua` uses the async class/asset loader and population bridge with separately owned action handles. No handle is inserted into the companion registry, so companion tuning, recovery and friendly-fire protection are not applied to horde enemies. Hostility is instance-specific, and pairwise friendly attitudes between owned enemies prevent different enemy species fighting one another. The encounter does not write quest facts, shared definitions or global faction defaults.

`horde_mode.lua` progresses through preparing, loading, armed, combat and rest phases. Settings are snapshotted per run: 8 starting regular enemies, 2 added per level, 10 levels, 1 extra boss per level and a 10-second rest by default. Enemies load serially at projected walkable positions ahead of the player. Each owned actor stays hidden, collision-free, damage-disabled and AI-suspended during preparation, with temporary friendly player attitudes. Once every actor is ready and a one-second settling period passes, the complete wave becomes visible and hostile. The adapter registers the player as combat instigator, initializes inspected native weapon state and retries combat entry while no live native target exists. It leaves target and attack choices alone once native combat owns them. Player attitude leases are restored on cleanup. Already-resident dependencies are traversed in a bounded pass; no synchronous asset-load loop is used. The player enters combat through the normal game combat system, after which native AI owns individual attack choices.

A cleared wave requires confirmed deaths for every queued enemy. An unloaded actor is not counted as a kill and does not automatically end the run. A temporarily missing AI attachment stays pending. Death checks consult the retained board before requiring live AI; health fallback requires prior positive health plus the native IsAlive result to avoid counting initialization as death. Confirmed bodies keep their population handles so ragdolls settle naturally, and remain through later waves and ordinary run completion. World resets and hot reload perform full cleanup; naturally unloaded bodies release their remaining handles. Death, a changed world/player, travel, a failed spawn, or leaving the encounter ends and cleans up the run. A five-second quiet period outside combat distinguishes retreat from a momentary combat-state change; moving more than 140 metres from the encounter also ends it. End horde stops only horde-owned population handles. Individual companion dismissals do not end a run. Whole-party resets release horde ownership before the native bridge's global stop, and hot reload does the same. Cleanup failures remain retryable.

Game time drives rest intervals, so pause does not spend the countdown. `horde-state.tsv` is a fresh versioned status snapshot; the helper derives only a display string from it. `DialogueOverlay.cs` shows this text only when there is no composer, microphone panel or conversation subtitle. Conversation text/generation is never overwritten by the horde timer.
