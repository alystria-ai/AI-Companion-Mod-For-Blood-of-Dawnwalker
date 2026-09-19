# Batch summons and retreat intent — v0.26.1

## Captured engine evidence

The paused-game read-only inspection and pre-change histories are retained in `runtime/session-v0261/`. The development probe `mod/Development/inspect_ambrus_transitions.lua` exported the owned Ambrus clone, its definition, logic trees and reflected reaction APIs. It was run once through the existing fixed `partyaudit` mailbox; the original audit probe was restored afterwards. No shared default object or story actor was modified by inspection.

Ambrus's history alternated between native Idle and Combat Start/Offensive/Defensive while the mod's `returning` flag stayed set. Every captured entry had zero mod combat starts. Several had no target or weapon selector. This supports native detection reactions restarting a fight which the mod immediately cancels; it does not establish a complete diagnosis of every character's campaign AI. A 486 cm gap still failed v0.26's 380 cm reunion threshold.

`LogicTree_DefaultEnemy_Main` contains HostileDetected and FightIsNearby triggers with EngageInCombat reactions, plus a Target.Escaped return reaction. `LogicTree_Follower_Leader_Enter` tests IsFollower when entering Idle and selects follower behavior. `LogicTree_Follower_Phase` breaks the follower loop when that flag becomes false. Native combat flags and phase can temporarily differ: the paused sample reported combat false while the tree phase was Combat and behavior Start.

## Movement intent and native ownership

`companion_recovery.lua` implements a pure decision rule. Running retreat needs a recent encounter, separation greater than max(900 cm, stopping ring + 500), nearest engaged-enemy distance over 1800 cm, speed over 180 cm/s and outward speed greater than 65% of total planar speed. Those conditions must persist for at least 2.5 seconds, with at least 600 cm net player travel and 450 cm growth in enemy separation. Falling out of the conditions resets the candidate. Circling, turning back and approaching another nearby engaged enemy therefore cancel pending departure. Ordinary travel never latches combat retreat.

A member stranded in recent combat while the player stands still gets a separate five-second rule: companion gap over max(3500 cm, stopping ring + 2500), enemy distance over 3000 cm and player speed below 170 cm/s. Enemy discovery stays shared at 750 ms; the cheap decisions run at 250 ms. The nearest engaged threat, a recently observed combat-target position, or the member's encounter location supplies the direction. This deliberately conservative heuristic can delay retreat if an enemy stays very close or keeps pace with Coen. It cannot directly read player intention.

During confirmed retreat or a catch-up cooldown, only the owned clone's perception is disabled and detection stimuli reset once. Known combat-entry/escape reactions are cancelled when no unbreakable action owns them. Known enemy attitudes on the companion's side become temporarily friendly so nearby-fight notifications do not reopen combat; enemies' attitudes toward the companion are not made friendly. Restoration checks live stubs and the value still owned by the mod. Encounter attitude restoration is deferred until this suppression ends, avoiding nested-override leakage. Perception is re-enabled for the owned clone on release; no per-stub original-enabled getter was found, so this relies on summoned clones' normal enabled perception.

The follower flag is armed before `StopCombatBehaviors`, allowing native Idle entry to choose its follower loop. No MoveTo call or forced phase/behavior transition is added. The manager still waits for native combat exit and unbreakable actions, with spaced retries. Reunion allows the stopping ring plus 500 cm and a settled player for 1.5 seconds, then a 2.5-second engagement cooldown. Normal noncombat catch-up has a cooldown but does not latch retreat. Native-initiated combat also runs the existing equipment/stance preparation once even if the mod currently has no eligible target; it does not replay StartCombat.

Some Ambrus attacks use a player-specific target filter. This update does not rewrite those shared filters or promise all boss abilities against NPCs. Further gameplay evidence is needed for his resulting attack quality.

## Responsive summon batch

`CompanionLoadBatch` owns one independent `CompanionLoading` per click. The UI records each item before awaiting its local HTTP request, so an earlier arrival cannot close over an outstanding newer request. Request ID and party epoch bind completion to its exact spawned instance. Failure wins over a lingering actor; stale snapshots cannot complete loading. A current exact-ID actor can confirm arrival if older SUMMON history was pruned. Pending native requests stay in Lua history; completed outcomes are pruned beyond 64 retained records.

The roster and Summon button remain interactive. Selecting or scrolling the roster disarms auto-close, and another summon rearms it for the extended batch. The menu waits for all requests, no failures, no outstanding local posts, a live snapshot and 1.2 quiet seconds before closing. Manual close cancels only menu completion tracking, not accepted summon requests. Failures remain visible. The progress list prioritizes pending requests and reports additional pending items beyond its visible rows.

The bridge can accept further spawn requests during a short game-thread stall if the same known epoch has an existing queued/loading summon and its snapshot is less than 60 seconds old. Other mutations still require a fresh snapshot. Epoch changes discard the transport queue, and commands retain their 60-second expiry. The 32-command transport backlog is a transient flow-control bound, not a party or duplicate cap. Asset preparation remains asynchronous, but final native actor construction can still hitch; keeping WinForms responsive cannot eliminate that engine work.

## Validation and rollout

All 81 Node/Fengari tests passed, all 18 Lua modules parsed, the helper compiled, and 14 original plus 12 batch C# scenarios passed. Focused Node/Fengari tests cover movement scenarios, follower entry, native-initiated combat, sensing restoration, live-board guards, commands and prior combat ownership behavior. C# checks exercise out-of-order batch arrivals, pending HTTP, browsing, new additions, failure precedence, stale snapshots, expiry, epoch changes and manual close. The helper is compiled and its Help/loading views rendered offline. These checks mock native calls and do not prove physical movement, attacks or frame timing.

Changes are staged, backed up and deployed through the existing Lua reload and helper replacement. The game process stays open; previously spawned party members are released during reload. Gameplay instructions are in `TEST-NEXT.md`. Native spawning DLLs, Convai profiles and quest data require no changes for this update.
