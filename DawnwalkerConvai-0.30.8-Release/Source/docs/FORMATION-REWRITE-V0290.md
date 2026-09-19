# Formation rewrite — v0.29.0

## v0.29.1: sprint catch-up and battle reunion

The live snapshot had Anca, Xanthe and Brencis near Coen but still `returning=true`, with sensing suppressed and fighting disabled. Their recent samples showed ordinary sprint speed around 464–480 cm/s; the previous fast recovery cooldown required over 650 cm/s, so those sprints still used eight seconds. Crake streamed back in and received a new `Parked` assignment about eight metres from Coen. Other companions were fighting an older boar encounter behind the player.

The planner now retains seats for registered companion IDs when their pawns temporarily disappear; actual dismissal still removes the seat. Sprint recovery starts at twelve metres for ordinary party seats with a three-second cooldown, while slower recovery starts at sixteen metres with five seconds. Large outer arcs expand these thresholds. Spawn anchors follow at a smaller departure distance to reduce streaming churn. Collision, off-camera, grounded and combat/action restrictions on relocation remain.

New combat entry waits until a travelling companion is within roughly fourteen metres of the party, keeping distant members on their follow task rather than allowing a new local fight to consume movement. Already-active combat is preserved. A fighter more than twenty-four metres behind with its own enemy over twenty-two metres from Coen can regroup after two seconds; another enemy beside the player no longer vetoes departure from that older encounter. Short flanks around an enemy beside Coen remain native combat.

A separate battle-reunion decision checks a current targeted or nearby active enemy, player movement relative to that enemy and companion proximity. After 500 ms of approaching/circling evidence it clears the old retreat and combat-suppression timers, allowing normal target selection. Fleeing directly away from a pursuer does not clear retreat. Ordinary stationary reunion also clears the leftover suppression timer when it completes.

195 offline checks and changed Lua syntax passed, including streamed reattachment, a battle while circling, pursuit during escape, older encounters, earlier catch-up and the actual new-combat gate. Gameplay confirmation remains with the user. Captured before-state and validation are under `runtime/session-v0291/`.

## Original rewrite

The v0.28.7 live snapshot showed ten companions with accepted requests (`2`), idle path controllers (`0`), zero or limited motion and unfulfilled seats. Merely generating separated coordinates and accepting `MoveToLocation` was insufficient. Each pawn's controller uses `RebelRoadsFollowingComponent` and an active behavior tree. The previous patch also held main behavior suspended while issuing those requests. The precise native cancellation path was not proved; the observed lack of motion was.

## One plan, one native destination per companion

`party_formation.lua` computes all positions together, using the shared spawn-arc geometry reflected behind Coen. It keeps stable instance identities and gives locked combat/conversation actors their actual space. It retains spawn positions until the player departs, keeps a settled frame during short approaches and camera rotation, and yields within the same arc if a locked actor occupies a seat. It never replaces the party with a single-file queue. The old overlap-triggered MoveTo correction, lane abandonment, historical reservations, predicted origins and path-token scheduler no longer drive following. Historical recovery helpers remain for compatibility and other recovery uses.

`formation_native.lua` creates a stock `TargetPoint` through UE4SS's `UWorld:SpawnActor`, hides it, disables collision and makes its scene root movable. Every clone gets a separate marker even when its Convai session is shared. No character, movement profile or behavior-tree asset is duplicated or synchronously loaded.

The inspected `DawnwalkerAIControllerBase:AIMoveToActor(TargetActor, bShouldFollowTarget, bShouldTrackPosition, bUseFastOut)` writes the controller's `MovementTargetActorBBKey`, `ShouldFollowTargetBBKey` and `ShouldTrackTargetBBKey` into its blackboard and refreshes its behavior tree. `AIStopFollowing` clears that movement target. The adapter verifies a live board, actor, controller, blackboard and brain before calling either API. An existing foreign movement target has priority. It disables only the ordinary Coen follower mode while this native movement target is owned; main behavior remains enabled. Native combat retains its existing target/ability system.

The authored `BT_BasicNPC:BTTask_MoveTo_5` selects `MovementTargetActor`. The paused inspection found a fixed 100 cm acceptance radius, no automatic moving-goal tracking, no agent-radius addition and goal-radius inclusion. A hidden point has no collision radius. The adapter extends the marker 100 cm beyond the desired seat along the approach direction, preventing native acceptance from leaving every actor short of its seat. It keeps the last marker near arrival to avoid flipping its direction. Material target movement during travel refreshes the native intent at most once per second; this is necessary because the authored task does not automatically track goal position changes. Shared assets remain untouched.

## Ownership and failure handling

Combat entry and conversation acquisition release the native destination first. Release clears the blackboard target only if it still refers to our marker, restores the captured tracking flags and ordinary follower mode, and destroys the marker. Replacement actors, blackboards or native movement targets are not adopted. Scene suspension remains external and is respected. Markers have a 15-second lifespan refreshed once per game second; paused game time does not expire them. A measured lack of movement allows two spaced rebinds, then releases to ordinary following for six seconds before retrying. Population spawn-anchor and out-of-view catch-up logic remain separate from travel destinations.

The native probe is a deliberately reversible paused operation, distinct from the read-only formation audit: it selects one owned clone, creates a marker, issues the binding, reads back the target, calls cleanup and restores the previous Lua lease reference. In the running game it returned `accepted=true`, `nativeTargetMatches=true`, `mainSuspended=false`, and cleanup completed. The UObject remained observable immediately after destruction while paused; that result is not proof of garbage collection. No game time was advanced, so this proves API binding and cleanup execution, not locomotion or final formation quality.

189 offline checks passed. New tests cover ten/forty-seat geometry, locked actors, departure and approach behavior, native target retention, moving marker reuse, combat release, foreign targets, detachment, bounded retries, and the native stopping-radius compensation. Lua syntax passed. Movement appearance, navigation around obstacles and performance with large parties remain for the user's test.

## Evidence and references

Local evidence: the UE4SS object dump; `runtime/companion-native-formation290.txt`, `formation290c.txt` and `formationbinding290.txt` (the latter two also have the `companion-native-` prefix); bounded executable disassembly and test results under `runtime/session-v0290/`. Installation paths and credentials are not embedded in the implementation.

The native wrapper at RVA `0x627ca9c` calls the implementation at `0x62a2048`; it uses the reflected controller blackboard keys. `AIStopFollowing` forwards to `0x62a2184`. These addresses are research evidence for this build, never memory patches or runtime calls from the mod.

[UE4SS documents the Lua world spawn API](https://docs.ue4ss.com/dev/lua-api/classes/uworld.html). [Epic describes Target Point actors as generic AI/path points](https://dev.epicgames.com/documentation/en-us/unreal-engine/target-point-actors-in-unreal-engine). [Epic's MoveToLocation reference](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/AIModule/AAIController/MoveToLocation) documents acceptance and path replacement, but Dawnwalker's authored movement behavior and blackboard mapping were established from the local game, not inferred from that generic API.
