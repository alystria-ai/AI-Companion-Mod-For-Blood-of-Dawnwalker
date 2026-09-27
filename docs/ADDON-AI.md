# Shared AI for companion add-ons

The version 1 Lua SDK lets a separate mod register its own live pawn with AI NPC Companions System. Players use the existing text and microphone shortcuts. The installed helper supplies the connection, voice playback, subtitles, conversation history and dynamic context. Add-ons do not start another helper or ship another API key.

This API is for locally installed, trusted game mods. A registered Convai character ID must be accessible to the configured account. Installing a model does not create an AI profile. Group speaker selection currently remains limited to the main mod's companion roster; registered external pawns support single-character conversations.

## Registration

Require both main-mod packages, then load `DawnwalkerConvai/Payload/sdk/CompanionAI.lua` using `dofile`. Resolve that path relative to your installed mod, not a developer's computer.

```lua
local base = modsDirectory .. '/DawnwalkerConvai/Payload'
local SDK = dofile(base .. '/sdk/CompanionAI.lua')
local ai = SDK.new(base .. '/runtime', 'creature-companion-mounts')
ai:register('creature', creaturePawn, {
    characterId = configuredConvaiCharacterId,
    name = 'Wolf',
    context = 'An allied wolf companion, currently following on the ground.',
    silentReplies = false,
    localActionsOnly = false,
    actions = {'Follow', 'Stop Walking', 'Come Here', 'Attack Nearby Enemies', 'Look At Player', 'Leave'}
})
-- About once a second, on the game thread:
ai:update(playerController)
-- On despawn:
ai:unregister('creature')
-- On mod cleanup:
ai:close()
```

Use a stable lowercase add-on ID and unique lowercase actor IDs. Registration supports up to 32 pawns per add-on. The host accepts at most 16 add-ons and 128 total registered pawns. Re-register an actor to update its bounded dynamic context, such as following, waiting or mounted. Identity is tied to the current world and player instance, and records expire when the add-on stops sending its heartbeat. Re-register new actor instances after world travel.

The main mod's F6/F7 target selection recognises registered pawns, including a nearest-companion fallback. Mounting or possessing a player-controlled pawn takes it out of the normal nearby-NPC selection path. Dismount before starting a conversation with that pawn.

## Movement and facial ownership

The owning add-on retains following, collision, animation and mount controls. Selecting a registered pawn does not attach the human speech layer, turn it, stop it or change its AI. Voice and subtitles work without a human skeleton.

`ai:pollAction()` returns a new queued conversation action as `{id, actorId, actor, name}`. Available names are `Follow`, `Stop Walking`, `Look At Player`, `Leave`, `Come Here` and `Attack Nearby Enemies`. Each registration advertises only the actions it implements; legacy registrations keep the original first four. Validate the current actor and implement only actions appropriate for your mod. Delivery is reported to the conversation, not completion of the physical action. Unread actions expire quickly and are not replayed after travel.

`ai:faceFrame(actorId)` returns a fresh table of speech blendshape weights only when the active conversation targets that registered actor and the frame generation matches. Map these to the add-on's authored rig if desired. An animal rig does not automatically gain human lipsync. Return missing channels to neutral and release your own face controls when this method returns nil.

## Commands without conversation

Set `silentReplies = true` for an action-only actor. The helper disables Convai TTS and gates local audio, NPC subtitles and face frames for that target. Text entry and microphone capture remain available for player orders. This does not alter the normal companions or the user's HUD settings. Dynamic context disables follow-up questions and asks for supported structured actions only.

Multiple creatures can use the same Convai character ID. Their individual registration and current dynamic context still determine the target and available orders. Each command is bound to the selected actor instance and conversation generation. A cloud profile interprets intent; it cannot run arbitrary Lua or choose an unregistered action.

Creature Companion Mounts uses one shared action-interpreter profile for all its animals and monsters, with silent replies always enabled. It provides no conversation or lipsync mode.

## Mounted camera handoff

Request the shared first-person camera to release its view target and player-body mask before your add-on changes the camera or mounts the player:

```lua
ai:setCameraLease('creature', true)
ai:update(playerController) -- Publishes immediately, even within the same second.
-- On subsequent game-thread updates, before changing the camera or player:
if ai:cameraReady('creature') then
    -- Start your own mounted camera and movement here, once.
end
-- Continue ai:update(playerController) about once a second while mounted.
-- On dismount: first restore your own camera/player state, then:
ai:setCameraLease('creature', false)
ai:update(playerController)
```

The acknowledgement is tied to the registered actor instance, current world and current player pawn. It must be newer than the request and no more than three seconds old. Allow a short handshake delay; do not switch the view target before `cameraReady` succeeds. Keep checking it while mounted and release your own mount state if it expires or the world/player changes. Re-registering the same actor to update its context preserves its lease request. Replacing that actor does not.

The main mod yields even when its first-person setting is Off. It resumes ordinary camera handling after the request is withdrawn or expires. Only one add-on receives the camera acknowledgement; simultaneous requests are ordered by add-on ID and actor ID. The lease does not change game-global camera settings, control possession, or implement the mount itself. A mount that changes the player pawn must establish a new registration and handoff for that new player identity.

## Transport and lifecycle

The SDK writes bounded TSV data into the existing `Payload/runtime` directory. The Node bridge validates complete records, IDs, size and age, then publishes a combined registry. The Lua adapter matches actual actor, world and player identity at selection time. It never evaluates registration text as Lua or invokes supplied function names. No global actor scan is added to the frame loop.

The optional actor-record fields are the camera-request flag, the silent-replies flag, a comma-separated action allowlist and the local-actions-only flag. Older records remain valid. `localActionsOnly = true` implies silent replies and bypasses Convai for the selected target, including connection warmup, voice capture and context updates. The text endpoint accepts only the fixed commands Follow, Stop, Come here, Look at me, Attack and Leave, intersected with the registered action allowlist. Unsupported text is rejected instead of sent to an AI. `silentReplies` by itself still permits AI interpretation.

`addon-camera-ready.tsv` carries the bounded acknowledgement. Registrations and acknowledgements refresh at most once per second, apart from an explicit lease change; acknowledgement files are not rewritten every frame.

`ai:available()` reports the helper heartbeat. A missing dependency or unavailable character profile should disable conversation features while leaving the add-on's non-AI systems usable. Do not copy the main mod's configuration, character roster, generated end-user ID or credentials into your add-on.

`ai:cameraPreferences()` returns the saved first-person toggle, FOV, height and forward offset, with a cached local configuration read. Creature Companion Mounts uses these for its owned camera while riding. Its first-person camera carries the `CreatureMountFirstPerson` actor tag; the main mod applies its existing body-visibility guard only when that tagged camera belongs to the leased creature and Coen is attached to it. The add-on continues to own camera position and rotation.

## Owned creature service

`CompanionCreatures.lua` is a separate, narrow SDK used by Creature Companion Mounts. It routes approved native creature definitions through the main mod's existing summon queue. `summon(catalogueId)`, `dismiss(memberId)` and `action(memberId, name)` return request IDs; check `status(requestId)` on later updates. A dismissal is complete only after the owned actor has gone. The service does not grant ownership of ordinary world NPCs.

Call `tick(playerController)` from the game thread. Before riding, request `setControlLease(memberId, true)` and wait for `controlReady(memberId)` as well as the AI camera acknowledgement. The service preloads the fixed compatible rider animation asynchronously and captures restoration state only after menu input ownership has ended. Restore the rider before withdrawing the lease. A host-side snapshot handles an expired client lease; failed restoration is retried rather than allowing the creature's AI to resume under an attached rider.

Protocol 2 binds commands to a host epoch, client session, world and player. A reset cancels old queued work, while monotonic command numbers prevent replay after the bounded result history rolls over. The service currently accepts only the owning `creature-companion-mounts` add-on, with at most 32 owned members internally; its menu manages one active creature. It is not a general-purpose spawn or asset-loading interface.

### Riding combat handoff

Creature control ends when Coen or the owned creature enters combat. The addon restores its seat, input, camera and movement profiles before releasing control. The host also checks combat when validating the lease and performs rider rollback if needed. Normal follow mode resumes after release; it does not issue generated attack commands or add combat abilities to peaceful animals. Additional addon-only NPC definitions are in `mod/Scripts/creature_catalog.lua`.

## Shared world context

Spoken addon conversations refresh the same bounded journal and environment snapshots as ordinary companion conversations. They receive the current tracked quest and revealed objectives (excluding the persistent family quest), regional time and weather, recent battle reports and the global follow-up preference. Their recipient identity includes the addon, registered actor ID and Convai profile ID, preventing another character’s private quest knowledge from being copied into their context. Their own profile supplies species lore and personality; being summoned does not establish that they witnessed past campaign quests.

Registered speaking creatures owned by the shared creature service can join the existing exploration, loot and battle-reaction candidate pool while unmounted. The existing settings, random selection, batch merging and cooldowns still apply; this does not create a second reaction loop. Nearby mounts are recorded as witnesses at battle capture. Local-actions-only and silent registrations are excluded. External actors still do not join the main roster’s group-chat selection.
