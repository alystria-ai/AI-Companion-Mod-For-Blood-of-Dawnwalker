# Companion code review and combat handoff — v0.26.7

Reviewed 13 September 2026. This build addresses shared control and recovery failures behind wandering, combat/follow oscillation and party update stoppage. **Bakir's area damage against Coen remains unresolved.** The final changes have offline regression coverage and still need a live fight check.

## The game owns fighting

Campaign AI retains each character's attack selection, combat positioning, tickets, powers, dodges, combos and timing. The mod runs no tactical order graph. `companion_orders.lua` remains development history and is now also removed from the runtime watch list. Bridge commands already reject tactical plans and configuration.

`companion_combat.lua` is an ownership coordinator, not an attack graph. Summoned enemy/boss definitions do not automatically become permanent player followers. They need friendship, a travel/combat handoff, missing native equipment initialization and an intentional departure request. Removing those responsibilities without a verified native companion replacement would leave them unhandled.

| Situation | Mod responsibility | Native responsibility |
| --- | --- | --- |
| Summon/travel | Own spawner; configure temporary friendship, follower status and travel pace | Stream, animate and navigate |
| Join encounter | Supply an eligible opponent if needed; initialize missing equipment; request entry | Validate eligibility and start combat |
| Fight active | Release travel overrides and target hint once native AI has an opponent | Choose opponents, attacks, powers, positions and timing |
| Player repositions | Observe without requesting departure | Continue the fight |
| Player leaves | Request exit, prevent immediate detection-driven re-entry, wait for acknowledgement | Finish uninterruptible actions and exit combat |
| Follow resumes | Restore follower movement and bounded weapon cleanup | Navigate and animate |

## Evidence and attribution

`runtime/session-v0267` preserves the pre-update UE4SS log, all 17 member histories, combat/power snapshots, heartbeat and party state. `source-review.diff` records production edits. The installed object dump and exported action trees supplement these observations. `script-reflection.txt` contains native metadata; `bakir-reflection.txt` and `bakir-tree-assets.txt` contain focused projectile findings. The full dump used here is UTF-8, confirmed from its byte prefix.

At **14:51:26**, UE4SS logged `attempt to call a RemoteUnrealParam value`, and the formation callback reported a nil `context` upvalue. Heartbeat and party diagnostics stopped advancing while the game remained running. The old code hooked `AIController:MoveToLocation` and also called it from Lua updates. Callback re-entry/lifetime interaction is a plausible contributor, not a proven explanation of the exact failure. Earlier hook-unregistration entries further limit attribution from the traceback alone.

The encounter recorded accepted starts for some characters and declined starts for others. The old rejection branch immediately cleared target/hostility hints and restored follower mode; the next attempt initialized combat again. This can explain mode oscillation independently of character identity, but does not prove every wandering pawn had this cause.

Bounded disassembly of this build's native `StartCombatBehaviors` path showed separate start-gate, combat-state and cached target-eligibility checks. A false return immediately after a hint does not establish permanent inability to fight. The stub and `AIBoard.Combat.bInCombat` flags must both be observed.

## Implemented corrections

### Global movement callback removed

The companion module no longer registers/unregisters a `MoveToLocation` hook or maintains a controller-to-hook lookup. It may issue an ordinary bounded path request to an idle follower's formation slot. Moving, waiting and paused paths retain native destinations. Combat preparation, combat exit, combat, scenes, conversations and uninterruptible actions exclude this correction.

Five-column arrival/idle spacing remains. **Rigid formation while moving is not guaranteed.** A blocked lane yields to the native direct route; cooldowns and global budgets remain. UE4SS documents callback parameters/timing, but does not establish the cause of the captured callback failure. [RegisterHook documentation](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html).

### Stable combat preparation and acknowledgement

Preparation now retains ownership, equipment and target hints across ticks. Equipment may take time to become ready, followed by a 500 ms settling interval. Rejected starts wait for another observation instead of immediately switching back to follow.

Requests are spaced three seconds apart, with at most three native start calls in an encounter attempt and a 12-second preparation window. Uninterruptible actions delay release rather than being cancelled by a timeout. Failed preparation returns to travel without stopping a fight that never started. Ten quiet seconds without a target reset the attempt budget; target churn alone does not.

Either combat flag acknowledges entry, including late entry during a perception gap when preparation already owns the pawn. Preparation tolerates a 1.5-second target gap. Established combat retains its existing grace/long-action handling. A start returning false after its board flag activates is acknowledged while restoring the temporarily lowered start gate.

### Native targeting and equipment control

An eligible current native opponent takes priority over player aim. Once native combat has that opponent, the mod releases its own forced-target lease instead of renewing it every three seconds. Foreign forced targets are preserved. The bounded hint path remains available if native AI loses its opponent and needs another entry hint.

Adopting an already-active native fight no longer initializes equipment. Repairs run during preparation only. Native hostility requires no temporary attitude lease. Exhausting the internal 128-record attitude override budget defers a new hint rather than throwing an error that dismisses the companion; it is not a party limit.

### Catch-up and fair recovery

Ordinary successful catch-up previously set a five-second `noEngageUntil`, feeding the retreat suppression path and disabling perception/fighting immediately after arrival. That assignment is removed. Actual retreat alone supplies the disengagement grace period.

Catch-up remains off-camera, collision checked and grounded, with neither combat flag nor an uninterruptible action active. Stop, death, conversation and scenes exclude it. It is not a combat teleport.

Fixed-order iteration could repeatedly award shared one-operation budgets to early members. The first updated member now rotates while display order and budgets remain unchanged. Each member of a stable 24-member party gets first access once per 24 update cycles. This bounds starvation; it cannot guarantee an unloaded or unreachable pawn becomes available.

Existing marker mobility leases, navigation checks, failure backoff and native bridge v8 serial/index validation remain. Retaining a population owner is distinct from keeping its pawn continuously loaded.

### Party identity and conversation boundaries

Owned stubs are excluded before enemy hostility checks. Temporary native attitude changes cannot turn another summon into this adapter's enemy hint. The saved ownership key is replaced on attachment and removed on dismissal even if its old UObject has become invalid. **This is not an area-effect damage filter.**

Single-chat selection, group-speaker availability and holds check both combat flags, preparation/exit and uninterruptible actions. Readiness is checked before selection/face inspection acquires a hold. The separate world-NPC conversation Follow/Stop adapter also avoids resetting goals or starting another assist while native combat/actions own the actor.

### Queue failures and repeated lookups

The app and reload router clear their pending latch if scheduling throws. Successfully queued work is not duplicated. The router still requires two identical snapshots, rejects bad Lua, preserves the old application on failed initialization/cleanup and discards old-generation callbacks.

This covers synchronous rejection, not an engine deadlock or an accepted callback that never executes. No blind watchdog submits overlapping work.

`companion_native.loadedClass` caches successful lookups while retaining UObject destruction, postload and CDO readiness checks. Missing results are not treated as loaded. This reduces repeated full-array searches for known classes, not every streaming/postload stall.

## Bakir's area damage: findings and remaining work

The user identified **Bakir**. His current summon uses `NPCDef_Bakir_Base` and runtime `AIDef_Bakir`. The captured `AssetTree_Bakir` references the single ground-slam abilities, teleport ground slam, `AssetTree_BakirGroundSlamProjectile`, `DA_CA_Bakir_Projectile`, and shared `BP_AI_Projectile` through `BP_AssetNode_FireProjectile`.

The loaded projectile's `Apply Effects` function has an `Actor To Apply To` parameter and calls GAS outgoing-spec, set-by-caller and apply-to-self functions on the target ability system. Its graph has a separate `Make Target Player React To Hit` path. This is a plausible route around faction-based target selection. Metadata is not an execution trace: it does not prove which specific hit caused the reported damage.

The catalogue also contains `NPCDef_Summoned_CoenHelper_Bakir` and `AIDef_Summoned_CoenHelper_Bakir`, with Ambrus/Xanthe counterparts and Brencis abilities that summon them. These merit comparison, but their names do not establish lifetime, permanent allegiance, powers or damage safety. No unvalidated helper-definition swap is installed.

`AttackTargetFilterClass` was the player class on working and non-working companion setups. Its semantics are not established, so it is not blindly changed. Movement collision ignoring also does not establish immunity to overlap/gameplay-effect damage. [Epic IgnoreActorWhenMoving contract](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UPrimitiveComponent/IgnoreActorWhenMoving).

UE4SS's ordinary hook for a `/Game/` Blueprint runs after the function. Returning from a hook on the projectile's void damage function is not a verified veto. A fix needs validated pre-damage target exclusion or source/target-scoped effect rejection. GAS has immunity queries and attribute/source conditions, but the general API does not prove safe runtime construction in this loader build. [UE4SS hook timing](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html), [Epic effect queries](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameplayAbilities/FGameplayEffectQuery), [Epic immunity component](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameplayAbilities/UImmunityGameplayEffectComponent).

### Developer probe crash — excluded from production

The core update reloaded at **15:10:54**, dismissed the old 17-member party and resumed its heartbeat. At approximately **15:12:05**, our later developer-only probe constructing transient GAS immunity data crashed the game. The stack enters UE4SS array/table conversion and Lua iteration; the exact assignment responsible is not established.

This was our experimental probe, separate from the earlier update stoppage. It was never added to production Lua. Its source and dump are archived in `runtime/session-v0267/probe-crash`. The temporary dispatcher was restored byte-for-byte, the executable probe removed and `runtime/dev-command.txt` emptied. No automatic retry or damage immunity is installed. Native bridge v8 is unchanged.

## Other lifecycle cases reviewed

| Case | Handling / limitation |
| --- | --- |
| Queued summons | Independent requests, reservations and owners; async class/CDO readiness required; v8 spawn lifetime code unchanged. |
| Player moves during loading | Final position recomputed against current player and live/pending reservations. |
| UI while loading | Existing independent helper/batch close logic retained; no UI rebuild in this correction. |
| Duplicate copies | Separate game actors and stable IDs, shared Convai identity; labels number only current duplicates. |
| Death | Defeated status; no intentional resurrection or catch-up. |
| Detached pawn/board | Validate live board; retain owner/slot; throttle owner-scoped reconnect and require stable replacement observation. |
| Repeated recovery failure | Backoff plus rotating work order. |
| Long native attack | Wait; no follow/catch-up interruption. A permanently stuck native action still needs runtime diagnosis. |
| Retreat versus repositioning | Existing sustained-departure and near-fight veto rules retained; native exit precedes travel. |
| World/time/player change | Clean up old party/owners; no cross-world actor reuse. |
| Hot reload failure | Previous code retained on parse/init/cleanup rejection; queue failure clears its latch. |
| Damage tuning | Existing per-owned-ASC 2.5× physical base damage; no new shared-effect/player-stat edits; not exact final HP scaling or friendly-fire immunity. |

## Verification

All **118 repository Node/Fengari checks** pass, including existing legacy tests. Added/updated cases cover delayed equipment, rejected/late entry, perception gaps, long actions, both combat flags, target lease release, native-opponent priority, foreign forced targets, 24-member fairness, attitude budget exhaustion, conversation guards and queue failure/retry. All production Lua files parse as Lua 5.3. These are controlled offline checks, not the native combat system.

The earlier core reload/heartbeat was observed before the probe crash. Final edits, including target-lease release and reload-router handling, require the next launch. No computer inputs or live combat tests were performed. See [TEST-NEXT.md](../TEST-NEXT.md); Bakir damage protection must not be represented as complete.
