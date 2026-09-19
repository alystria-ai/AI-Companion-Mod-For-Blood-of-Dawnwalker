# v0.27.1: group conversation and compact parties

This build repairs the group reply lifecycle and conversation-to-follow transition, and coordinates compact travel formations for small or large parties. It uses the existing reflected UE4SS calls and native population/asset bridges. No native DLL change or game restart is required. Reload releases the existing party, so summon fresh companions afterwards.

## Evidence and boundaries

The reported symptoms were a single group reply, a spoken-to Brencis running in place, and summons/followers spread around the player or overlapping. The captured session showed repeated conversation holds and Look At Player actions, then an eventual distance release. There was no recorded group handoff. The current paused party could be ranked into three distinct speakers offline, so ranking itself was not enough to explain the original result. Spawning a second Brencis changed the formation layout; that is consistent with refreshing the first instance's path, but does not prove the original stall's exact cause.

Inspection of the installed `@convai/web-sdk` 1.7.0 implementation found that `MessageHandler` creates an empty streaming row at `bot-llm-started` and marks only the last chat row complete at `bot-llm-stopped`. An intervening message can therefore leave an orphan placeholder streaming. The old reply tracker required every row to finish. Separately, the Lua party catalogue excluded a companion whenever an unbreakable arrival/turn action was active, and handoff published an inactive selection before publishing the next actor. These were independent ways to omit or lose subsequent speakers.

The update addresses those paths. Live audio playback, walking and twenty-character game performance still need the player's visual check; offline tests cannot establish native animation quality or navigation behavior. Existing combat policy and known area-damage limitations are unchanged.

## Group conversation

`bridge/group-chat.mjs` keeps the addressed character first and selects up to two other nearby, distinct character identities using the existing lore relationships and topic relevance. Twenty spawned companions still produce at most three responding identities. Duplicate actors share the same Convai character/session identity and do not occupy multiple speaker slots.

The party catalogue now distinguishes being eligible to join a conversation from being ready to acquire a hold immediately. A short native action does not remove someone from the candidate list. Lua retries a busy handoff, without interrupting that action, until the bridge's twelve-second deadline. Death, combat, cinematics, lost range and stale room/generation remain reasons to skip or cancel safely.

`ReplyTracker` ignores empty streaming placeholders when evaluating reply text and also observes a real responding-to-idle transition from the SDK. An initial idle connection cannot complete a turn. Completion still requires thinking and speaking to stop, the face/audio queue to drain, and a quiet interval; text-only completion retains a grace period for delayed TTS. Audio and lipsync are not deliberately cut short to advance the group.

Lua performs speaker changes without publishing an inactive intermediate target. Room, token and generation checks prevent a replay or late acknowledgement from changing a newer conversation. At the end of the last reply, `GROUPEND` releases that speaker's movement hold once while leaving the room/session available. Speaker order, count and status are recorded in private `runtime/group-status.json`; `group-reply-status.json` records completion and queue flags without copying dialogue or API credentials.

## Returning from a conversation

Before a companion acquires the existing conversation hold, the adapter releases its travel-speed lease and re-evaluates its idle state once. The body animation continues ticking. The hold owns the known suspension, yaw and movement flags; restoration checks that the original actor and AI board still belong together before restoring movement mode.

When a conversation ends, hands off, completes its group round or accepts Follow, the party adapter marks that exact actor instance for resumption. At the next eligible travel tick it invalidates the interrupted follower task/path once and clears its gait, spacing and recovery caches. Combat, scenes and unbreakable actions defer this reset. A replacement or separately summoned clone cannot consume another actor's reset. Stop Walking still returns to the party manager's waiting behavior.

A separate watchdog now detects a Moving path that has made no actual pawn progress for 3.5 seconds, in addition to the existing idle-path recovery. Waiting and paused native paths are excluded. Recovery has a cooldown and a finite progress-based retry allowance. It does not continuously reset combat actions or animation state.

## Small and large party layouts

Summons use front-facing arcs. The first arc has five places; the next has seven and the third nine. With ordinary capsule sizes, twenty reservations fit within roughly 5.8 metres of Coen, with the first arc about 2.6 metres away. Outer arcs gain places rather than repeating the same sparse five-person row. Each projected destination is checked against live companions and in-flight reservations, and must remain in front of the player. A cliff or collapsed navigation projection cannot silently redirect a summon behind Coen. When no valid space exists, summoning reports that open ground is needed.

Travel starts with one companion on either side of Coen, then one behind, then wider side places and additional rear rows. Ordinary centre-to-centre pitch is 1.6 metres; larger capsules increase the pitch. Twenty ordinary followers have assigned offsets within eight metres. This is a destination layout, not a guarantee that every pawn will occupy its slot while moving around obstacles.

The party's frame remains fixed during camera turns and approaches shorter than four metres. A real travel leg advances the frame using movement direction. Native follow restart distances now agree with that rule: settled companions allow the approach, while travelling companions restart sooner. Side companions' gait also accounts for movement toward their assigned place rather than only radial distance to Coen. Talking cancels a leftover arrival adjustment for the addressed actor.

The shared space coordinator uses spatial buckets to compare neighboring companions. A talking, fighting, waiting or otherwise controlled character has right of way; stable summon order breaks other ties. Only the yielding travel companion receives a correction. Brief crossings are tolerated, and both parties are never told to swap the same occupied space. Navigation results and active destinations are reserved so distinct desired slots do not collapse into the same actual point.

If a wide lane has no navigable destination, that member temporarily uses a narrower two-column route behind Coen and later retries its wider place. Crowding alone does not trigger this terrain fallback. If neither route is clear, requests back off and ordinary native following/catch-up remains available. This is local navigation adaptation, not a global route planner or a guarantee that every twenty-person group fits through every doorway.

All travel and separation paths share a four-request-per-second budget with rotating access across members. A member also has its own cooldown and at most three correction attempts without real actor/player progress. Native follower movement continues between these occasional corrections; combat, powers, retreat and unbreakable actions retain their existing owners. No reentrant engine movement hook or new per-frame global actor scan was added.

## Validation and references

Validation covers SDK-style orphan streaming rows, delayed audio, all three group speakers, busy and stale handoffs, one-shot final release, per-instance follow restoration, twenty-person arc/slot geometry at multiple headings, projected collisions, different floors, locked participants, large capsules, narrow routes, bounded retry work and fair access for twenty members. The complete regression suite also exercises the browser client, native ownership adapters, lipsync mapping, clone session sharing and bridge protocol. All Lua sources parse and TypeScript checks/builds successfully.

Implementation references are the locally installed Convai SDK's `dist/core/MessageHandler.js`, `dist/core/ConvaiClient.js` and blendshape queue; this project's existing UE4SS object catalogue and native API adapters; the captured conversation/companion logs; and the existing [mod methodology and references](../README.md). Source files are `bridge/reply-tracker.ts`, `bridge/group-chat.mjs`, `bridge/client.ts`, `bridge/server.mjs`, and the Lua `app`, `engagement`, `companions` and `companion_recovery` modules. Private installation paths and credentials remain local configuration.
