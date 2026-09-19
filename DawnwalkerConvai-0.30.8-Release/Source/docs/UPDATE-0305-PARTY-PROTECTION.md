# v0.30.5 — companion allegiance, area effects and combat exit

The companion manager now guards both friendship and acquired combat targets. Native retaliation can change these independently: restoring a faction attitude alone does not necessarily cancel an attack already directed at Coen. Every active owned companion is checked before conversation and ordinary stat-update early exits. If native combat targets Coen or another owned companion, the adapter repairs that pair, clears a protected forced target, closes the fight gate and requests the existing acknowledged native combat exit. Cinematic ownership and unbreakable actions are respected. Looking at Coen peacefully is not treated as an attack. Original campaign actors and unrelated enemy relations are excluded.

This is a plausible explanation for the historical Brencis boss-fight incident, not a confirmed reconstruction: no trace of that incident is available. A hostile boss actor's ordinary combat/UI behavior can explain the appearance of a boss fight without establishing that a campaign quest was activated.

## Source-filtered area-effect protection

Faction friendship does not cover every damage path. Some projectile/power blueprints obtain the victim's ability system and apply a gameplay-effect spec directly. The new filter uses the native Gameplay Ability System, before the incoming effect is applied to Coen.

Only party-owned companion ability systems receive `DawnwalkerConvai.Source.OwnedCompanion`. A private, infinite gameplay effect on Coen contains an `ImmunityGameplayEffectComponent` with a `SourceAggregateTagQuery` matching that marker. Ordinary enemy ability systems are never tagged. The filter has no attribute modifiers, health refunds or global invulnerability flag. It rejects effects whose captured source tags include the marker; attacks that bypass GAS or discard their original source still require gameplay verification. This also excludes any future beneficial companion-to-player GAS effect with the same source marker; such support would need a more specific damage-only query.

The narrow `companion_protection_v1.dll` helper constructs tag containers and queries through reflected native calls and `FProperty::CopyCompleteValue`. Lua-side nested array marshalling lost query contents in this engine/loader combination, while assigning arrays directly previously crashed UE4SS. Lua now allocates the private arrays using `Property:ImportText`, and the helper validates their exact lengths and component identity before copying a native query. It checks a positive companion-marker match and a negative unrelated-tag match before enabling the effect. No shared gameplay-effect class defaults are edited.

The helper builds a spec from the private effect object with `AbilitySystemBlueprintLibrary:MakeSpecHandle`, applies it through the target ASC and retains its exact handle. Repeated updates do not stack effects or source tags. Marker changes check that the actor resolves to the same ASC as its AI stub. Dismissal removes the source marker; player/world changes and hot reload remove the exact active filter and release its private root. Removing a nonexistent old actor/ASC is idempotent. The helper does not install damage hooks or retain Lua callbacks.

Relevant primary references: [Unreal immunity component](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameplayAbilities/UImmunityGameplayEffectComponent), [UE4SS property import](https://docs.ue4ss.com/lua-api/classes/property.html). Native signatures and property sizes are checked against the installed game's reflected metadata.

## Finished encounters

The combat controller receives a shared encounter snapshot from Coen, live party members and eligible enemies currently targeting the party. A leftover enemy combat flag alone cannot repeatedly restart combat entry. Once the encounter is inactive and the companion's own native combat flag is clear, the controller allows a 750 ms settle, waits for unbreakable actions and performs one native exit/cleanup. Ongoing native combat and short perception gaps continue to own their movement and animation. Automatic revival uses the same encounter evidence instead of a stale selected enemy.

## Verification and remaining gameplay checks

281 automated tests pass, and all 25 production Lua modules parse. Tests cover protected-target rejection, peaceful gaze, unchanged enemy hostility, native-combat/perception gaps, single exit, source-marker ownership and exact effect cleanup during player replacement/reload. The native helper builds successfully.

In the paused running game, the new helper validated its source query, installed the private effect, returned a valid active handle, avoided stacking on a second ensure call, and removed/released the effect successfully. The game remained running. This establishes construction and lifecycle behavior, not proof that every authored area attack preserves source tags. Bakir's area attack, normal enemy damage, historical boss hostility and Lacra's repeated combat lines still need the requested gameplay check.

Build the helper with `scripts/Build-CompanionNative.ps1 -Protection`; build the complete distribution with `scripts/Build-Prebuilt.ps1 -BundleSharedKey`. Its DLL is included in the explicit distribution allowlist. The development smoke-check script is excluded from the prebuilt package and is never run on startup.
