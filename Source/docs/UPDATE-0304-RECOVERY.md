# Menu recovery and combat audit — 19 September 2026

## Recovery

The working baseline was commit `5154137` (v0.30.3). The intervening work had made uncommitted edits, not additional commits. Its patch, startup probe and notes were archived privately before changes were made.

The menu failed on `SetHitTestVisibility`, a nonexistent widget method. The transparent CommonUI click catcher now retains normal hit testing; only the painted UMG layer is hit-test invisible. Native construction, repeated selected-latch consumption, all five pages, the combat roster and Escape navigation passed in the running game.

The extra standalone startup probe was disabled. It failed on `Actor:IsPlayer` (the relevant game API is on an AI stub) and treated any friendly pawn as an owned companion. The retained on-demand inspection uses the manager's identity snapshot, has bounded traversal, and does not alter combat state. No startup dependency installation was added. The installed bootstrap matches the tracked source, the configured Node path is unchanged, and the application dependency manifests/lockfile were unchanged.

## UI work

- Cache engine class/library lookups through the validated object cache. Repeated global object searches are expensive on this UE4SS build.
- Update text and enabled state only when their values change.
- Cache the visual state before calling the theme helper: the helper writes native brush proxies even if its returned alpha is unchanged.
- Keep enabled Summon and Dismiss actions highlighted.
- Update setting values and key-capture labels in place instead of rebuilding the page. Keep native click latches intact between ticks.

## Combat findings and changes

A proximity health refund was removed. It could not identify the attacker and could refund legitimate enemy, environmental or damage-over-time hits. Raw `CurrentValue` writes were also removed; a gameplay attribute's current value is the result of native effect aggregation, not a standalone writable setting. Unreal's [gameplay attribute and effect documentation](https://dev.epicgames.com/documentation/unreal-engine/gameplay-attributes-and-gameplay-effects-for-the-gameplay-ability-system-in-unreal-engine?application_version=5.2) describes this base/current distinction.

Before changing the damage route, the live 500% setting produced the expected values on owned companions: Anca's physical base damage was 3965 from an unboosted 793; Bakir's was 6240 from 1248. Their AI-versus-AI source damage was 50 from 10. Attack frequency at 250% produced a native additive attack-speed value of 1.5. Player damage, level and attack-speed attributes were unchanged by these settings. These readings establish attribute application, not a promise that every power scales or that every attack occurs 2.5 times as often; native cooldowns, tickets, defense and ability-specific formulas still apply.

Level matching has been removed from the menu, configuration and tuning code. The recovery toggle has also been removed: defeated companions always revive after the existing quiet period following combat. Characters retain their authored levels. New installations use 250% damage and 180% native attack frequency; existing custom percentages are preserved. Damage now revalidates cached values after native stat changes, rebases without stacking, and rolls back its owned base writes on partial failure.

The earlier route was insufficient: the AI-versus-AI fallback only changed 10 to 50 at the maximum setting, and forced `DealFollowerDamage` selected a separate campaign-helper calculation. Owned clones now clear that tag; their combat adapter already releases follower locomotion and temporary-follower identity. Their `DamageAIvsAI` uses the greater of original AI damage and unboosted melee/unarmed strength, multiplied once by the slider. All baselines are captured before writes, so attribute enumeration order cannot stack the coefficient. At 100%, this means normal physical strength, not the old helper value of 10. Standard AI-versus-AI attacks should now produce meaningful damage, but final health loss and authored powers still require gameplay validation. Only manager-owned clone ASCs and tags are edited; enemy ASCs and shared effects/configuration are not changed.

An async spawn now reacquires character and AI classes immediately before use. If another asset load allowed an earlier class to be collected, loading returns to that stage instead of passing a stale object to the native bridge.

## Travel recovery

Rapid running first reuses the existing owned pawns: hidden, grounded, idle companions can move to separated walkable positions behind the camera. Native attacks, cinematics and uninterruptible actions keep their existing guards. The normal sustained-departure detector still handles disengaging from a fight; fast movement does not permanently suppress retreat.

A position jump or sustained super-speed run prioritizes owned spawn-marker updates and starts a bounded recovery period. Missing pawns get time to return through their original population owner. Replacement is a fallback after a grace period, with the exact old owner stopped first and at most one replacement per travel period. World transitions preserve the party's identities/order and rebuild through the async loading path in bounded steps. Queued commands, defeated status and dismissal remain separate from returning a lost travelling pawn. This reduces unnecessary asset loads; it does not promise zero engine work when a whole new world needs character assets.

## Remaining validation

Boss area-effect friendly fire is not claimed fixed by faction friendship. The temporary `damagetrace` development command observes source/target information at six reflected damage/effect entry points; it changes no parameters, results or health. It stops after five minutes, 200 rows or Lua cleanup, and is never enabled at startup. Its source file is outside the distribution allowlist. The trace did not identify Bakir's area-hit source, and that hit still knocked the player out. A subsequent private native effect-immunity construction probe crashed inside UE4SS. The stack included UE4SS array-property marshalling frames. The probe was quarantined, its command route removed and the mailbox cleared; no constructed effect/filter is enabled in the mod. A source-specific fix remains unresolved. Do not mistake source stat scaling for friendly-fire protection.

The native attack-speed attribute is not a timer that forces AI attacks. Do not edit shared EnemyConfig assets or global NPC level overrides to change an owned companion; those can affect campaign enemies too.

## Verification

All 277 automated tests pass and all 24 Lua modules parse. Focused Lua behavior, loading, lifecycle, combat tuning, input and restoration tests cover player-ASC rejection, unchanged authored levels, frequency rebasing, native damage refresh, descriptor-order independence and partial-write rollback. Native menu construction and input navigation passed in the running game. Gameplay observations are recorded separately from synthetic test results.
