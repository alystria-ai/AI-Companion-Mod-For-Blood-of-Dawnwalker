# v0.26.8 — approaching companions, Ambrus idle and retreat

This Lua update addresses the September 13 reports that small player movements rearrange the party, Ambrus stands in a T-pose, and companions repeatedly resume combat instead of following a departing player. Native AI continues to choose attacks, abilities and combat movement. The native bridge remains v8.

## What the evidence shows

The old formation frame followed the player's velocity heading every 250 ms, even after a short sidestep. Idle path recovery counted distance to a newly rotated formation slot as if the player had walked away. Separately, the native follow restart distance was only 35 cm beyond its stopping distance. Together these could make a settled group move when the player approached somebody to speak.

Bakir's recorded retreat alternated between `leaving` and `travel` at 23:08:21–32 while `returning=true`. The sampled native actions were not unbreakable, and reaction tags were `None`. This establishes repeated combat re-entry; it does **not** prove a particular incoming hit caused it. Code inspection found that one-way friendly relations were applied only once per retreat, even if native damage/instigator handling subsequently made that enemy hostile again. Enemies outside the discovery radius around Coen were also easily missed after the mod released its target hint.

Ambrus's paused live mesh had animation mode 0, `bPauseAnims=false`, `bNoSkeletonUpdate=false`, a live `ABP_NPC_Main_C`, and a linked `ABP_AmbrusLocomotionLayers_C`. The layer was present, not simply paused or absent. Its parent is `ABP_NPC_HumanLocomotionDefaultLayers_C`. Ambrus's idle selector contains an unconditional `Ambrus_Idle_01` combat animation. The parent's ordinary idle selector instead includes an unarmed `Coen_Idle` fallback. Their walking, starting, stopping and pivot selector references matched; idle, fixed-direction idle and turn-in-place selectors differed.

These observations support trying the ordinary human idle selectors on the spawned Ambrus instance. They do **not** establish the rendered T-pose's exact cause or prove the visual fix. That requires the next gameplay check.

Read-only reports are archived under `runtime/session-v0268/`. `mod/Development/inspect_party_pose.lua` reads only existing owned Ambrus instances and loaded selector assets; it does not load assets or change animation. The temporary dispatcher was restored and `runtime/dev-command.txt` cleared after inspection.

## Implementation

### Settled party positions

`companion_recovery.formationFrame` retains a fixed position and heading until Coen moves four metres from the settled frame. A real travel leg updates that frame while moving. After 750 ms below jogging speed, it captures a final position and retains the travel heading. Turning the camera or briefly changing direction nearby cannot continually rotate the formation.

Each member records the travel epoch. `formationCorrection` permits one successful arrival adjustment for a new leg, then leaves a settled member alone. Being within three metres of a member cancels its pending adjustment so approaching to speak wins over arranging the formation. Native moving paths are not cancelled. Real distance from Coen can still wake an idle follower; a changing slot alone cannot do so repeatedly.

`companion_combat.followPace` supplies 2.5 metres of separation between native stopping and restart distances. Running and sprinting thresholds on existing paths retain their previous prompt response. This is a movement dead zone, not a timer that delays running. Idle path recovery uses the same minimum separation, its existing stagnation/cooldown checks, and bounded retries.

### Departure and combat re-entry

`companion_recovery.retreat` adds a departure path for a known recent fight: player speed at least 4 m/s, an outward velocity component greater than 65% of speed, at least 1.5 seconds of continuous departure evidence, at least nine metres of net player travel, a meaningful companion gap, and at least eight metres from the known enemy. The enemy does not have to fall farther behind: a pursuer can keep pace while the player clearly runs away.

Short dodges, tangential movement, and close combat still retain native fighting. The existing slower departure and distant-separation fallbacks remain available. Once this faster departure is latched, merely catching up beside a still-running player does not reopen combat. Stopping before the distant companion has reunited also does not let a pursuer 8–18 metres away cancel regroup. Returning within eight metres of the actual fight releases that exception.

`companions.retreatSensing` maintains the existing temporary, one-way friendly relationship toward encounter enemies throughout retreat. Each update considers the native board target, the previous target/instigator, recorded encounter relations, nearby enemies, and existing retreat leases. A hostile relation that returns during retreat is repaired; unchanged relations cause no extra write. Discovery remains bounded and deduplicated. Coen and owned companions are excluded. Restoration preserves native changes that no longer match the mod's value.

The native `StopCombatBehaviors(stub, true, false)` exit still owns combat cleanup. The booleans mean switch to Idle and do not restore the pre-combat instigator attitude; they are not force-cancel options. Unbreakable actions remain protected. Re-entry caused by an unobserved engine path is still possible, so the runtime now logs `returnKind` and `retreatHostilityRepairs` to distinguish intent detection from repeated native hostility changes. No invulnerability or damage rejection was added.

### Ambrus travel idle

`travelIdle` finds the **live linked Ambrus instance**, using the existing `GetLinkedAnimLayerInstanceByClass` API. `ai_state.leaseIdleSelectors` temporarily assigns three already-loaded references from its human parent CDO: `IdleAnimSet`, `FixedDirectionIdleAnimSet`, and `TurnInPlaceBlendSpaceSet`. It validates all references before applying them. It does not replace the animation blueprint, skeletal mesh, locomotion graph, face layer, or shared selector contents.

The lease is kept during ordinary conversation so his body can idle while lipsync runs. `combatPose` restores it before combat preparation, even when an existing native action prevents a character-state change. Scene takeover, reattachment, death, dismissal and hot reload also release it. A changed or invalid linked instance is handled separately, and a later native selector override is preserved rather than overwritten. Live instance lookup is throttled to once per game second.

The diagnostic `travelIdle` field distinguishes a successful lease from an unavailable linked instance. A successful reference assignment is not proof that the rendered pose is correct.

## Reference and verification

The primary evidence is this game's UE4SS object metadata, live owned-instance reads, and companion combat histories. Epic documents that [Get Linked Anim Layer Instance by Class](https://dev.epicgames.com/documentation/unreal-engine/BlueprintAPI/Animation/LinkedAnimGraphs/GetLinkedAnimLayerInstancebyClas-) returns an existing linked instance and can check child classes. That API explains how the instance is located; the Dawnwalker-specific selector choices come from the local comparison, not generic Unreal assumptions.

Before deployment, all 19 Lua files parsed as Lua 5.3 and 88 staged companion/integration checks passed. Eight new behavioral regressions cover local approaches, one arrival adjustment per travel leg, meaningful follow gaps, equally fast pursuers, short/circling movement, selector restoration/native overrides, and repeated hostility outside the discovery radius. The older follow threshold assertion was updated to the new intentional dead zone. These checks do not simulate game animation rendering, navigation or native combat damage.

Deployment completed at 23:32:21 local time on September 13. UE4SS logged v0.26.8, released all four previous companions, and confirmed reload completion. The game remained paused and responsive, with a fresh companion heartbeat. All five changed source/installed Lua files match the staged files. The complete post-deployment Node/Fengari suite passed **126/126**; its output is `runtime/session-v0268/tests-final.txt`. Native v8's SHA256 remains `0a63fef6a10adccfd16cc6465200c4935ce6a9c356e04484038dbd4703fa9955`.

Gameplay validation: summon fresh Ambrus and a few other companions; approach one after the group settles; then compare circling an enemy with a sustained run away. The hot reload dismisses the old party, so it must be summoned again. See `TEST-NEXT.md` for the short user procedure. Bakir's separate area-damage friendly-fire problem remains unresolved.
