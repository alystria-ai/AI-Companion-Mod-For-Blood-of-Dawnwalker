# Companion simplification — v0.26, 13 September 2026

## Player behavior

F5 now shows the summon roster, current party, selected member status and Help. The Help topics are Getting started, Conversation and Troubleshooting. Tactics and Orders are removed; there is no Actions tab. Follow and Stop remain conversation requests. Native AI decides attacks, positioning, timing and powers using the summoned character's existing combat definition and equipment.

A single instance has a plain display name. With two Ancas, the labels become Anca #1 and Anca #2, ordered by summoning time. Removing either restores the plain name on the survivor. A later summon is numbered after existing copies. Labels never change instance IDs, actor ownership, the Convai character profile or shared conversation/memory identity.

## Evidence and uncertainty

Evidence captured before this update is in `runtime/session-v026/`; the earlier investigation is in [v0.25.1 notes](COMPANION-COMBAT-V0251.md). Preserved histories from the previous process show Anca, Lacra and Bakir in follower/travel mode, requesting running yet roughly 33–40 metres behind Coen. The movement hook had redirected dozens of paths. Their captured samples have zero combat-start attempts. This supports investigating follower path contention; it does **not** prove the cause of Lacra's reported combat oscillation.

The user restarted before this investigation. The current UE4SS log belongs to the replacement process. No new matching UE4SS dump or game crash report was found for the reported mod stoppage. Its cause remains unconfirmed. Lua guards and offline checks cannot guarantee freedom from native crashes.

Offline executable inspection followed the dump's `StopCombatBehaviors` thunk at RVA `0x5cdf044` to implementation `0x1a0fad0` and body `0x3e0e2cc`. It checks board offset `0x6c0`, matching reflected `Combat` at `0x6b0` plus `bInCombat` at `0x10`. It clears `bCanFight` at `0x2cc` and modifies the weapon selector as part of native exit. This is independent of the start-combat gate diagnosed previously. The disassembly is saved as `stop-combat-disassembly.txt` and `stop-combat-body.txt`. No raw-address calls or executable patches are used in the mod.

## Movement and combat ownership

The global `AIController:MoveToLocation` hook, destination redirects, repeated formation navigation projection and idle-settling MoveTo requests are removed. Native follower movement has sole path ownership during travel. Each companion uses a separate stopping ring, starting at 180 cm; consecutive rings add both capsule radii and 65 cm clearance. This prevents identical requested stopping distances without imposing a second path controller. It cannot guarantee perfect crowd separation on cramped terrain.

Follow starts 35 cm beyond the member's stopping ring. Running starts 120 cm beyond it, or earlier if Coen is moving at least 180 cm/s. A separate run-exit threshold prevents gait chatter. Pace and retreat checks run every 250 ms; enemy discovery remains one shared, bounded query every 750 ms. Static library lookup caching, streamed-pawn backoff and staggered diagnostics are retained.

Running away with an outward velocity can latch retreat at a 1,000 cm gap for the first follower; a stationary distant separation triggers at 1,600 cm. Thresholds grow with that member's assigned spacing. Retreat disables new combat entry and clears the mod's forced-target lease. Unbreakable actions finish first. The manager requests native combat exit, then waits for both the stub's combat report and reflected combat flag to clear before following owns movement again. If native combat remains active, stop requests are spaced by three seconds. The manager never interprets the void stop call as proof of completion.

Retreat remains latched until the member is near Coen, out of combat and Coen has been settled for two seconds. A further three-second re-engagement delay prevents immediately chasing the old enemy again. Existing collision-checked catch-up remains restricted to distant, grounded travellers behind the camera, excluding death, combat, unbreakable actions, scenes and explicit Stop. Global and per-member cooldowns prevent simultaneous relocation bursts. Missing AI retains its population owner and attempts reattachment rather than silently destroying the party slot.

In combat, the adapter no longer applies ForceAggression or preferred role positions. It supplies Coen's hostile target or a nearby engaged enemy, stable temporary target leases and pairwise attitudes so former villains can assist against their own faction. The native combat tree owns movement and attack selection. Perception gaps alone never stop an active native encounter. The native follower damage tag and verified sword/claw preparation remain; there is no blanket damage multiplier or manual power activation. Scripted boss abilities that require a player target, encounter state or special form are still conditional.

## Conversation and migration

Follow on an owned party actor releases the conversation hold and uses that actor's existing party manager. It does not invoke the separate temporary world-NPC follower controller. Stop stores a persistent waiting mode; ending chat releases the conversation hold and the party manager supplies its idle hold. Asking Follow releases it. Look At Player only faces Coen for the conversation, and Leave does not dismiss a party actor. Ordinary world NPCs retain their reversible conversation behavior.

The Node endpoint and Lua mailbox reject tactical configuration, attack/hold orders and plan execution. Old grammar/executor files and saved plans remain as development history, but the active manager imports no order executor and never restores a saved plan. Reserved TSV columns keep rolling Lua/helper updates compatible. Old fields are omitted from the public member model. Authenticated commands retain party epoch, replay, expiry and exact instance-ID checks.

## Validation and deployment

The full offline Node/Fengari suite passed 72 tests. Focused checks were rerun after the final protocol-model cleanup. They cover dynamic duplicate labels, capsule spacing, run thresholds, latched retreat, native exit acknowledgement/retry cadence, active-combat perception gaps, ordinary unbreakable follower actions, and actual app-to-party conversation handoff. The 14 C# loading-lifecycle checks pass. All 18 Lua files parse; TypeScript type checking and the client bundle build pass. The WinForms helper builds, and full-size/720p Help layouts and the loading view were rendered for inspection.

Deployment uses staged files and the existing mod-local reload. Only the helper restarts for the updated UI/client; the game can remain open. Reload releases previously summoned companions. Native spawning DLLs, credentials, character provisioning and quest-memory data are unchanged. See [TEST-NEXT](../TEST-NEXT.md) for the short remaining gameplay check. Offline tests and a successful reload do not prove physical movement, combat quality or frame pacing.
