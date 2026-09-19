# v0.26.6 follow and combat investigation

## Captured failure

`runtime/session-v0266` preserves the prior log, party snapshot, combat histories and marker probes. Eleven companions were summoned, including two Xanthe instances. Brencis, Leonica, Xanthe, Ocha and Ambrus repeatedly detached, and several reattached when Coen returned. Anca's history shows regroup latched with player-to-enemy distances around 105–150 cm. That is not evidence of leaving the fight. Ocha was also recorded idle, stationary, with follower mode enabled, no unbreakable action and a 14.48 m player gap against a 10.58 m stopping distance.

The old separation shortcut ignored the nearby enemy when companion separation exceeded its threshold. It could therefore force a far flanker out of combat while Coen circled the enemy. The new current-fight proximity veto applies before that shortcut and before retaining a previous regroup. `fightKnown` distinguishes a recent enemy position from fallback companion position. A distant fight can still request retreat even if Coen has reached a different enemy. The separation shortcut now requires distance from the old fight and a sustained 3.5 seconds. Existing sustained outward-travel evidence and native combat-exit acknowledgement remain.

## Population marker correction

The live probe found DynamicSpawnPoint.SceneRoot.Mobility=0 (Static). This explains repeated declined marker moves. A second probe used only the owner returned by the bridge's registered action poll, changed its root to Movable, called K2_SetActorLocation for a 25 cm X offset, verified acceptance, then restored the position and original mobility. Readback was exactly +25 cm and then 0/0/0 with Mobility=0 again. No character or story actor was moved.

The production helper `AI.moveSpawnAnchor` keeps a per-marker mobility lease, uses the proven setter with sweep disabled and teleport enabled, and verifies position within two centimetres. A replaced/invalid root is rejected; a later native mobility change is respected. Dismiss/world-change/hot-reload releases the lease. The marker is already scoped to a companion's registered spawner and world by the caller. Marker updates are checked after one second per member and staggered at 250 ms globally, with existing failure backoff and navigation validation. They begin around ten metres or the row's stopping distance plus four metres, whichever is larger.

This establishes that the recovery marker actually moves. The live population system's subsequent unload/respawn behavior still requires gameplay validation. The release does not change global population ranges or advertise AlwaysSpawned protection.

## Idle wake and catch-up scheduling

`Recovery.wakeFollow` watches actual pawn progress while AIController.GetMoveStatus is Idle. Outside the row's stop distance plus 180 cm, 1.5 seconds without one metre of progress permits one ordinary MoveToLocation request toward its current slot (or direct player position when a lane is blocked). Player movement refreshes the retry budget but does not postpone the stagnation timer indefinitely. Native moving, waiting and paused paths are never interrupted. Eight seconds separate attempts; at most two occur without meaningful pawn/player progress. Conversation, Stop, scenes, suspended AI, both combat flags and unbreakable actions exclude the operation. A global 250 ms budget prevents a same-frame burst across the party.

Off-camera physical catch-up now uses a 250 ms party interval rather than 1.5 seconds. Eleven eligible followers can consequently be serviced over roughly 2.5 seconds instead of fifteen seconds, subject to terrain/visibility/action gates and per-member cooldowns. This matters when the player is fast enough to leave the population's ordinary range before the end of the old queue. Collision and grounded checks remain unchanged; movement is never forced through an active combat action.

## Validation

Focused regressions cover far flankers with a nearby current enemy, cancelling a false regroup upon returning to the same fight, distant real encounters, brief separation, continued player movement during idle-wake observation, path ownership, retry and party budgets, marker mobility restoration, position readback failure, invalid/replaced roots and respecting native edits. The full Node/Fengari suite and Lua parsing run before deployment. Native bridge v8 is unchanged. Real-time following, combat and marker-driven population recovery still need the user test.
