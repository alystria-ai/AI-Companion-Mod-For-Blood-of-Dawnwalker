# Streaming, pace and catch-up — v0.26.2

## Evidence

The user confirmed Ambrus fighting on v0.26.1, then reported stuttering after running away and followers falling behind during fast travel. Evidence is preserved in `runtime/session-v0262/`, especially `UE4SS.before.log`, the Anca/Ambrus histories and `streaming-probe.txt`.

At 12:46:18 both companions began losing their pawns. Ambrus reattached at 12:46:32, 12:46:38 and 12:46:41, then lost the replacements within seconds, sometimes less than one second. The final snapshot had both party slots but no attached actors. This is a native population unload/recreation cycle, not evidence of the mod summoning new cloud characters. Repeated native actor creation is a plausible cause of the reported stutter; no frame-time capture establishes it as the only cause.

A bounded read-only paused-game probe resolved only recorded population owners, their owned dynamic spawn points, loaded movement profiles and a UEnum. Both owned spawn points still had the original summon coordinates, while their owners' pawn maps were empty. The owner is a persistent population manager, not the pawn itself. Moving the pawn does not move that source marker.

The live UEnum unambiguously returned Walk=0, Run=1, Sprint=2. This corrects the inaccurate Sprint=1 comment in v0.26.1. Loaded follower profile speed settings were Walker=140, Runner=450, Sprinter=590 cm/s. A replacement Ambrus had the Running character state but a Walker movement profile. The profile and current enum can change independently of the mod's cached request.

The old catch-up search selected the first navigable point 320 cm behind Coen, then rejected it outside the search if it was still in front of the third-person camera. It had already spent the eight-second relocation cooldown. Consequently it could repeatedly reject the same first point without trying a farther, unseen candidate. Old `playerGap` diagnostics were also stale while in combat; this version updates that distance before deciding combat ownership.

## Changes

Follower pace now distinguishes running and sprinting. Sprint is requested when Coen moves at least 320 cm/s or the gap exceeds the stopping distance by 400 cm, with a separate exit threshold. The adapter checks the actual FollowerSpeed every travel update. If a slower movement profile still wins, it pushes the already-loaded native follower Runner/Sprinter profile once, retaining the returned handle. It pops only that handle on release, with live stub/board/component guards. No shared movement asset, combat speed, attack, ability or animation rate is edited. The profile's speed remains native; off-camera catch-up handles travel faster than that profile can sustain.

Catch-up moves its candidate search far enough behind the actual camera, then validates the projected point inside that search. Ordinary successful relocation keeps the eight-second cooldown; player speeds over 650 cm/s use three seconds. Failed attempts retry after two seconds. A shared 1.5-second throttle staggers party work. Existing live-board, ground, collision, camera, scene, death, Stop and combat checks remain; both native combat indicators now block relocation.

The retreat direction uses the member's own recent combat target position. A new enemy beside Coen no longer changes the direction of that old encounter. In addition, a recent fighter farther than max(2400 cm, stopping ring + 1600 cm) for two seconds regroups even if Coen still has another nearby enemy. The separate timer survives a sprint-to-stop transition, but resets when the gap closes or following ends. Close repositioning stays in native combat. This prioritizes staying with Coen over sustaining a distant fight and is not a configurable pursuit limit.

The manager captures the spawner returned by its existing owned native registry, then resolves its single DynamicSpawnPoint once. Only that marker is eligible for relocation, and only in the same world for a following, non-defeated member. It selects nearby walkable positions after Coen moves over 1800 cm from the old marker. Attempts are spaced at least three seconds per member and 1.5 seconds across the party. Stop, scenes, death and airborne player movement yield. This changes the source for later native streaming arrivals; it does not force a new spawn, revive a character or move a combatant directly. Whether every native population path consumes the relocated marker immediately remains a gameplay question.

Reattachment waits until the same replacement pawn survives at least one second across observations. Poll backoff is not reset until a reattached pawn stays healthy for ten seconds. Thus a rapid sequence of transient replacements does not repeatedly run equipment, pose and friendship initialization. Failed or detached objects retain the population owner for later recovery; no global object scan was added to the regular tick.

Performance reporting retains the session's maximum Lua tick cost and a bounded list of slow reconnect/attach/marker/catch-up/diagnostic operations. Those measurements cover work performed by the Lua adapter, not unrelated render or native population frames. They persist into the paused state so the next report need not reproduce the issue repeatedly.

## Validation and rollout

All 89 offline Node/Fengari checks passed before final documentation; targeted checks cover the new movement and recovery cases. All 18 Lua modules parse. The mocked checks exercise state ownership and geometry, not physical gameplay or FPS. The WinForms menu, native spawning DLL, Convai connections and character data are unchanged by this Lua update. The existing mod-local reload releases the prior party without restarting the game.

The exact next gameplay check is in `TEST-NEXT.md`. Keep the original evidence when evaluating improvement: the goal is fewer pawn identity changes, successful behind-camera catch-ups, native sprint profiles during travel, preserved attacks after rejoining and improved frame pacing.
