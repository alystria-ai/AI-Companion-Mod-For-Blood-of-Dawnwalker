# v0.27.0: long-fight passivity investigation

The user reported that Brencis and Xanthe became passive after fighting for a while. The captured v0.26.9 fight lasted from approximately 00:17:57 to 00:19:40 on 14 September 2026. Both retained native combat ownership throughout that period, with follower movement disabled and no repeated mod combat entry. Xanthe remained in Defensive behavior across several later samples; Brencis also settled into Defensive. Both subsequently entered `OpponentOutsideCombatGuardArea`, including a Xanthe sample only about 88 cm from her enemy. All evidence is preserved privately under `runtime/session-v0270`.

## Native rules behind the symptoms

The exported shared `LogicTree_Basic_Phases_Offensive` contains a non-player-target branch: `LTC_IsFollowerOrLeaderForPlayer`, then the negation of `LTC_DistanceToPlayerLessThan` with Distance=900, then `LTT_ChangeBehavior` to Defensive. Turning off follower locomotion alone does not bypass this rule. Offline disassembly of `IsLeaderOrFollowerOfPlayer` confirms that it also accepts `bIsTemporaryFollower`. The mod previously left that flag true during combat. This explains a mechanism for a companion to become defensive while the player repositions, independently of spell availability. It does not prove this is the sole cause of every passive interval.

The clones also inherit boss guard-area behavior. `SetIgnoreGuardAreas` is a reflected per-stub operation; its inspected native wrapper writes only the initialized stub's own AI board (offset 0x8c0 in the tested executable). The mod now calls it once after attaching each owned population clone, and again when attaching a replacement pawn. No shared AI definition/configuration or campaign actor is edited. This removes the original arena boundary while the party manager still detects actual departure and handles following.

The movement repair added in v0.26.9 had a timing bug. `PushMovementProfile` queues a stack entry, while `GetCurrentMovementProfile` returns a cached pointer. The inspected push implementation does not write that cached pointer. Immediate readback therefore caused the mod to pop Xanthe's new profile before locomotion could adopt it. The repair now allows 750 ms of game time for the original walking profile to be replaced. A native defense/attack profile, character-state change, scene or unbreakable action still wins immediately. A profile that remains unapplied after the grace period is released with a three-second retry delay. No repeated pushes are made while a lease is pending or active.

## Combat identity ownership

`ai_state.combatFollower` captures and temporarily clears only `Follower.bIsTemporaryFollower` while companion combat owns the character. `Follower.bFollowerModeEnabled` stays off under the existing combat ownership code. The saved identity returns through `releaseCombatFollower` when leaving combat, following, retreating, conversing, entering a native scene, dying, reattaching or dismissing. Restoration validates the original stub/board pair and does not write through a detached board. An originally false identity remains false.

This is not an attack state graph or a forced aggression loop. Native AI continues selecting targets, abilities, defensive actions, tickets and cooldowns. The faction/friendship setup and existing follower damage tag remain separate. The change removes the campaign helper's proximity restriction during a fight; it does not globally disable defensive behavior.

## Spells and further observation

Xanthe's authored logic includes a ten-second `Special Ability Used` cooldown, a thirty-second shared Blood Pull/Exploding Star cooldown, and an eighty-second Summon Clones cooldown in one branch. These are specific branch settings, not a universal timing guarantee. Brencis inherits substantial shared sword AI and adds teleports and authored attacks. The mod does not reset these timers or grant duplicate abilities.

A paused read after the encounter found zero active ability counts for the sampled party, including both bosses. That rules out an ability remaining active at that later snapshot, not an ability being stuck during the fight itself. The old roughly sixteen-second per-character diagnostic spacing was too coarse to establish a spell timeline. A new bounded trace records Brencis and Xanthe's behavior, Standard/Helper ticket queries, unbreakable-action flag and active ability counts once per game second. It retains 180 samples per character and writes at most once every four game seconds. It calls no activation/cancellation/reset API and runs no global actor scan.

`Combat.DistanceToTarget` retained a float-max sentinel in these captures despite a valid nearby target. The independent measured target distance is recorded separately. This update does not overwrite that legacy field based on an assumption that the new AI consumes it.

## Portable source and private paths

The installer takes `-GameDirectory` or `DAWNWALKER_GAME_DIRECTORY`. Python analysis tools use the environment override or the ignored installation manifest. The research generator accepts an explicit dump path and otherwise uses the same private installation source; its published index records a generic `<game>` path. The developer's installation folder name was removed from public code and documentation. Runtime logs/manifests, backups, reference archives and Python caches remain local and excluded from shared source. Actual local installation records retain working paths.

## Validation

All 19 Lua files parse, and the full suite passes 144 tests. Focused tests exercise deferred movement adoption, genuine priority loss, immediate native-state precedence, follower identity restoration and detached-board refusal, and per-board guard-area setup. The new activity reader also ran successfully against the paused party: its ticket queries and active-ability reads completed without errors. The development entry point was restored and its command cleared afterward.

Hot reload completed at 00:35:52 local time on 14 September 2026, with v0.27.0 active, the previous party dismissed, and the game still responsive and paused. All four changed Lua files match between staging, workspace and installed fallback. Native population v8 and asset-loader v1 are unchanged. A scan covering public source, documentation and mod binaries found no remaining developer installation label. The portable Python, JavaScript and PowerShell analysis/install scripts pass syntax checks.

These checks establish code behavior; sustained combat and spell cadence still require the short gameplay check in `TEST-NEXT.md`. Bakir's previously reported area-damage friendly fire remains a separate unresolved issue.
