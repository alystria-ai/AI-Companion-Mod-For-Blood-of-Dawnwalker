# Companion cleanup and damage — v0.26.3

## Evidence and boundaries

Investigation on 13 September 2026 used the existing paused game (PID 5732), the local UE4SS object dump, current owned-party records, bounded native-function disassembly, and the mod's explicit development command interface. No computer inputs or unpause were issued. Two brief, scoped live checks exercised the new setter and native weapon cleanup on the existing owned Ambrus and Crake. Damage was restored after verification. Native sword cleanup deliberately left them stowed. This is not a gameplay damage-per-second or animation test.

Evidence is saved in `runtime/session-v0263` and `runtime/companion-native-party263*.txt`. No API credentials or new Convai profiles were involved.

## Loading lifecycle

`CompanionLoadBatch.Browse` previously latched `Choosing=true` indefinitely. Selecting or scrolling after the final summon disabled auto-close until another summon or manual close. The batch now expires this state after 3,000 ms without another intentional roster interaction. Browse does not reset the all-ready timer; the two independent timers require the entire batch to be ready for 1,200 ms and the browsing grace to have elapsed. A new summon resets readiness and has its own request/epoch identity. HTTP requests, failed summons, stale game snapshots, world changes and manual close retain their existing safeguards. Rendering and list refresh do not count as user interaction.

`CompanionLoadingTests.cs` covers out-of-order arrivals, pending HTTP, repeated browsing, eventual close after abandoned browsing, new requests, failures, stale state and cancellation: 14 original plus 14 batch scenarios pass.

## Inventory swords after combat

Both captured companions were Follower/Idle with combat flags false and weapon selector None, yet their straight-sword actors remained visible at `socket_weapon_r`. `RebelAIStub.StowWeapon` checks the selector first and returns immediately for None. Its implementation returns false even after issuing native stow, so its Boolean cannot confirm success.

`ai_state.travelWeapon` runs separately from the cached travel pose. It inspects the existing combat weapon and accepts only a physical instance matching the equipped inventory class at a hand socket. A cleared selector is temporarily restored to Sword, then native `StowWeapon(true)` is requested. Physical readback determines completion. Attempts are spaced 1.5 seconds apart and limited to three per travel period. Combat entry resets this state.

The live check also showed the native equipment proxy can leave weapons created through `CombatComponentBase.SpawnEquippedWeapon` in place. On a later attempt, if the same sword remains and the combat component is idle, `RemoveAllWeapons(true)` releases the native combat weapon instances. This is the native counterpart to spawn; it does not unequip inventory or change a shared NPC definition. Active combat, dead/detached AI, scenes, suspension, uninterruptible actions and claw setups are excluded. Native combat preparation recreates the equipped weapon on the next fight.

Live results for both Ambrus and Crake: physical weapon absent after cleanup, equipped inventory class preserved. A full fight → retreat → fight sequence still needs gameplay verification.

## Damage tuning through GAS

The follower effect `GE_Combat_Follower_Health_Damage` uses `MMC_CombatDamageFollower`; its captured source attributes include BaseMeleeDamage and BaseUnarmedDamage. The alternate `GE_Combat_Health_DamageAIvsAI` captures source DamageAIvsAI. The existing DealFollowerDamage tag is preserved.

A crucial distinction: these NPCs have zero raw BaseValue for the main damage stats, but effective CurrentValue is supplied by native effects. Multiplying zero would do nothing. `companion_damage.lua` enumerates actual attribute descriptors with `AbilitySystemComponent.GetAllAttributes`, reads the CharacterBaseAttributeSet and calls the game's reflected `CombatBlueprintFunctionLibrary.SetAttributeValue`. It adds `(multiplier - 1) × effective damage` to the original base, and verifies both the new base and effective current values. This uses the native GAS setter instead of directly overwriting CurrentValue or editing shared gameplay-effect defaults.

The per-ASC lease stores the original base and owned new base. Same-ASC reattachment does not compound the boost. A replacement ASC gets its own baseline. Cleanup restores only values still matching this mod's owned value, preserving later native edits. Failed setup restores any partial changes. No regular attribute scan runs during follower updates.

Verified effective readbacks at 2.5×:

| Owned companion | Melee / unarmed before | After | AI-vs-AI fallback |
| --- | ---: | ---: | ---: |
| Ambrus | 1,092 | 2,730 | 10 → 25 |
| Crake | 1,301 | 3,252.5 | 10 → 25 |

A second application left the values unchanged; restoration returned both characters to their original stats. The coefficient is configured in companion_config.lua and preserved in the JSON/generator default. It applies at attachment against that pawn's current native stats; later native stat changes are not continuously multiplied. Native armor, defense, follower damage balancing and frequency remain active. This does not modify magic-specific effects or guarantee an exact ratio of final health loss.

## Display identity and verification

The summon configuration and candidate catalogue now display Crake. Internal `marat` IDs, asset paths, conversation routing and search aliases remain compatible with existing data. No cloud identity migration is needed.

All 97 Node/Fengari tests pass, 19 Lua modules parse, the helper compiles, and the C# loading lifecycle scenarios pass. Deployment backs up changed files and installs matching source/fallback Lua plus the helper through its existing background restart mechanism. The game remains running. Gameplay verification is listed in TEST-NEXT.md.
