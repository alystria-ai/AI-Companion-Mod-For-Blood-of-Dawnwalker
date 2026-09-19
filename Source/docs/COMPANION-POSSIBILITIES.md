# Companion research and feature choices

Research date: 12 September 2026. This is a capability survey, not a promise that all 55 options work. **Selected: tactical depth + character powers, with all ten additional companions (17 total).** The v0.21 F5 panel, owned party controller, bounded order engine and ability gates are now integrated. Native class loading succeeded for Anca, and the new Lua controller hot-reloaded while the game stayed paused. Spawning and combat still require user gameplay validation. See the current [README](../README.md) and [test instructions](../TEST-NEXT.md); later historical research notes describe the investigation before this integration.

## What the research established

The read-only live asset-registry query succeeded while the game was paused. It returned **2,698 distinct matching assets: 2,428 NPC definitions, 94 AI definitions, 63 AI configs and 113 AI abilities** across the queried NPC, enemy and quest directories. This is a filtered catalogue, not a dump of every installed asset. No NPC was spawned, no ability was activated, and no game input was sent for this research.

Bakir, Ambrus and Xanthe each have both `NPCDef_Summoned_CoenHelper_*` and `AIDef_Summoned_CoenHelper_*` assets. These are particularly useful candidates: the game contains versions explicitly named for helping Coen. Their names do **not** establish permanent follower support, correct allegiance outside their encounter, unlimited lifespan or safe independent spawning. We should inspect those versions before adapting ordinary bosses.

The dump also exposes native combat-position preferences, attack targets, aggression/ticket settings, health and stamina getters, follower distances and speed, guard areas, combat/cinematic state, and action-completion information. That supports a companion layer which requests goals and lets RebelAI animate and execute combat. It does not justify forcing attack animations every frame.

Evidence files:

- [Asset catalogue](../runtime/companion-asset-catalog.tsv): exact installed package and asset names; no soft-reference loads.
- [Native API evidence](companion-native-evidence.tsv): 1,250 selected reflected names/types, with line numbers in the original object dump.
- [Research counts](companion-research-index.json).
- [Roster candidates](../characters/companion-roster.json): seven requested characters and ten additional candidates, with exact catalogue matches. Generated class paths are candidates and remain unresolved/unvalidated.
- [Offline index builder](../scripts/Build-CompanionResearch.mjs): reproduces the index from the two local inputs without touching the game.

## How much control we actually have

There are three different controls worth exposing separately:

1. **When to engage:** assist Coen, retaliate when attacked, or seek nearby hostiles. The mod can implement target-selection policy using attitude checks, the player's combat target, forced-target requests and combat start/stop calls. Native reactions still need to be reconciled with that policy.
2. **Where to fight:** frontline, behind Coen, left/right flank, or a stand-off distance. Native preferred-location/orbit functions are present. These are preferences subject to navigation and the NPC's own combat behavior; a preferred location is not a hard positional lock.
3. **How often and how to attack:** native config fields include helper cooldowns, ranged cooldowns, blocking, attack parry and aggression traits. These are stronger evidence than a single `bIsAggressive` flag, but config objects may be shared across many NPCs. Per-companion copies or supported instance overrides must be established before exposing those settings. Ranged-only additionally requires a verified attack filter; moving an NPC farther away does not enforce it.

Relevant native interfaces include:

- `RebelAIBoard.SetForcedTarget`, `GetTarget`, `GetForcedTarget`, `IsBeingAttacked`, `IsBeingAttackedBy`, `GetAttackers`, `HasAnyUnbreakableActiveAction`, `HasFinishedActionRecently`.
- `RebelAICombatBlueprintFunctionLibrary.StartCombatBehaviors`, `StopCombatBehaviors`, `BP_SetPreferredLocation`, `BP_SetPreferredOrbitAngle`, `BP_SetDestinationLocationOnOrbit`.
- `RebelAIStub.SetAttitudeTowards`, `IsFriendlyTowardsPlayer`, `IsHostileTowardsPlayer`, `IsInCombat`, `IsInCinematicMode`, `PerformDynamicAction`, `StowWeapon`.
- `RebelAISubsystem.ForceAggressionTowardsTarget` and `ResetAggressionBetweenStubs`.
- `CombatComponentBase.GetHealthPercentage` and `GetStaminaPercentage`; numeric scale and per-character availability still require a small live read before setting thresholds.
- `RebelAIConfig.MinHelperTicketCooldown`, `MaxHelperTicketCooldown`, low-health equivalents, `MinHelperRangedAttackCooldown`, `MaxHelperRangedAttackCooldown`, `bCanBlock`, `bCanAttackParry`, `bIgnoreGuardAreas`; `RebelAITrait_Aggression.BaseAggression`.

## Feature menu

**Established** means the underlying behavior has already worked in this mod, not that it is integrated with the new party UI. **Native hook** means a reflected interface exists but the proposed companion behavior is untested. **Mod logic** means we can build the decision/UI/persistence layer; any required engine actions still depend on their adapters. **Experimental** means an important native capability or ownership detail is unresolved.

### A. Tactical orders and team coordination

| # | Option | What it would do | Evidence and practical limit |
|---|---|---|---|
| 1 | Follow / regroup | Return to Coen using native follower navigation. | Established for the existing follower; party lifecycle remains to be built. |
| 2 | Wait here | Stop travelling while retaining idle animation. | Existing conversation hold is a starting point; a combat-capable guard stance needs a separate controller. |
| 3 | Close / normal / loose following | Set comfortable separation for exploration. | Native hook: follower distance and movement thresholds. |
| 4 | Walk / keep pace | Prefer a follower movement speed. | Native hook: `FollowerSpeed`; enum values and locomotion acceptance need checking. |
| 5 | Assist my target | Help fight the enemy Coen is engaging. | Assistance code already exists; the combat outcome has not been separately gameplay-confirmed. Enemy and current-order validity must be checked. |
| 6 | Focus this enemy | Have selected companions converge on one hostile. | Native hook: per-board forced targets; expiry prevents permanent stale targets. |
| 7 | Spread targets | Assign different hostiles to reduce everyone chasing one opponent. | Mod logic with hostile validation; bounded target discovery and reachability checks needed. |
| 8 | Protect Coen | Prefer enemies currently attacking the player. | Native hook: attacker queries and forced targets. Does not guarantee enemies switch their own targets. |
| 9 | Protect another companion | Help Anca or another selected ally when pressured. | Mod logic over the same native attacker interfaces. |
| 10 | Aggressive / defensive / passive engagement | Change whether the companion initiates encounters or waits for danger/orders. | Mod logic plus native combat controls; passive mode must account for native retaliation rather than merely stop issuing attacks. |
| 11 | Frontline | Prefer a position between Coen and the current enemy. | Native hook: preferred combat location; not a guaranteed taunt or shield wall. |
| 12 | Rearguard | Stay behind/near Coen and help with threats that approach. | Mod logic and positioning hooks; requires targets and a navigable location. |
| 13 | Left / right flank | Approach a target from its side relative to Coen. | Native hook: preferred location/orbit; define and verify angle convention before using it. |
| 14 | Loose encirclement | Give each companion a different combat position. | Mod logic; spacing must adapt to party size, target motion and navigation. |
| 15 | Hold an area | Defend a chosen spot with a limited pursuit radius. | Guard-area and preferred-location evidence; unrelated quest guard volumes must remain untouched. |
| 16 | Short / long pursuit leash | Break off rather than chase enemies across the map. | Mod logic over distance/combat state; native arena leashes may be stricter. |
| 17 | Fight at range | Prefer stand-off positioning for a capable NPC. | Native hook. This alone cannot guarantee ranged-only attacks. |
| 18 | Strict ranged-only / melee-only | Reject attacks outside the chosen family. | Experimental: per-NPC action/ability classification and an effective instance-level filter are required. Unsupported characters must say so. |

### B. Reactions and combat style

| # | Option | What it would do | Evidence and practical limit |
|---|---|---|---|
| 19 | Fall back when hurt | Regroup below a health threshold; optionally resume above a higher threshold. | Native health getter + mod logic. Retreat does not itself heal. |
| 20 | Rest when exhausted | Stop committing to attacks until stamina recovers. | Native stamina getter + mod logic; native defense remains necessary. |
| 21 | Rescue an overwhelmed ally | Temporarily override the assigned role when several enemies attack an ally. | Attacker queries and target-selection logic; needs debouncing to avoid role thrashing. |
| 22 | Cautious / normal / relentless attack pace | Change helper attack opportunities and recovery cadence. | Experimental instance config: helper ticket/cooldown fields and `BaseAggression` exist. No global difficulty/config edits. |
| 23 | Prefer blocking / parrying | Give eligible fighters a defensive style. | Experimental: `bCanBlock`/`bCanAttackParry` exist; animation/equipment support is character-specific. |
| 24 | Reserve a special ability | Use ordinary actions until a trigger or explicit command allows a special. | Experimental ability filtering; cannot merely ignore a Convai request while native AI continues auto-casting it. |
| 25 | Punish a stagger/opening | Request an attack after the enemy is vulnerable or just missed. | Action/character-state and attack event evidence; exact tags and timing need validation. |
| 26 | Avoid interrupting a committed move | Queue a new order until an uninterruptible action ends. | Native hook: active/unbreakable action checks; urgent cancellation still needs a bounded fallback. |
| 27 | Avoid large attacks near allies | Withhold selected AoE abilities when allies are in the affected area. | Experimental: per-ability shape/target rules needed; not equivalent to disabling friendly fire. |
| 28 | Recover when stuck | Report a failed path, then regroup or offer a recall. | Path/remaining-distance fields exist; a safe recall position needs nav/ground validation. |

### C. Character-specific powers

All entries here are **experimental**. The exact ability assets are in the catalogue. Owning the right class does not guarantee it is granted, off cooldown, correctly targeted, or independent of an encounter script. Use the character's existing action system and respect its conditions. Never blindly call every ability whose name sounds useful.

| # | Option | Concrete game evidence | Possible companion use |
|---|---|---|---|
| 29 | Anca: anti-magic support | `GA_AI_Combat_Anca_Counterspell`, follower AI definition/config. | Save her counterspell for threats to Coen; offer a support preference. |
| 30 | Bakir: heavy pressure | `GA_AI_Bakir_GroundSlam_Single_Left/Right`, `GA_AI_Bakir_BerserkStun`. | Frontline pressure or controlled crowd attacks, if target filtering is correct. |
| 31 | Ambrus: mobility and clones | `GA_AI_Ambrus_CreateClones`, `Teleport_Escape`, `AstralAmbush_A`. | Flank/escape behavior and optional decoys; spawned clones need party ownership and limits. |
| 32 | Xanthe: ranged control | `GA_AI_Xanthe_BloodPull`, `BloodBoil`, `Far_Whip_*`, `LifeDrain`. | A stand-off controller preset. Life drain cannot be advertised as party healing without evidence. |
| 33 | Lacra: mobile attacker | `GA_AI_Lacra_WolfAttack` and `_Right`. | Aggressive flank preference using her own supported moves. The name alone does not prove a permanent alternate form. |
| 34 | Matriarch: summon support | `GA_AI_UriashMatriarch_SummonWolves`. | Limited summons associated with the companion; cleanup and allegiance must be established. |
| 35 | Matriarch: form preference | `GA_AI_UriashMatriarc_Shapeshift_Base`, `_Shapeshift_Bear`, wolf dodge and bear charge attacks. | A situational form preference, after form transitions and collision/navigation are understood. |
| 36 | Leonica: mobile area control | `GA_AI_Leonica_AoE`, `GA_AI_Combat_Teleport_Leonica`, `_ToNun`, resurrection asset. | Possibly an AoE/mobility caster. The nun resurrection/teleport paths appear encounter-dependent and should start unavailable. |
| 37 | Brencis: boss powers | `GA_AI_Brencis_Telekinesis`, `ScreamAoE`, `BodyExplosion`, several summoning assets. | A restricted boss companion preset; scripted phases, arena teleports and summon dependencies make him a harder integration. |

### D. Travel, party management and conversation

| # | Option | What it would do | Evidence and practical limit |
|---|---|---|---|
| 38 | Mirror crouching / stay quiet | Keep a travel stance consistent with Coen. | Native follower crouch/noise fields exist; quiet travel does not prove stealth detection immunity. |
| 39 | Rally point | Send everyone to a chosen nearby place, then resume their previous roles. | Mod logic plus navigation; actual arrival must be sensed rather than assumed after a timer. |
| 40 | Party presets | Save combinations such as Anca support, Bakir front, Lacra flank. | Mod-owned configuration; only offer capabilities verified for each NPC. |
| 41 | Remember individual preferences | Restore role, leash and engagement style for each companion. | Mod-owned configuration. Save configuration/identity, never raw UObject handles. |
| 42 | Travel/load recovery | Reacquire or respawn owned companions after travel or save load. | Experimental lifecycle integration; must distinguish a new world from a temporarily unavailable actor. |
| 43 | Conversation without dismissing the party | Temporarily pause travel for a chat, then resume the assigned companion order. | Existing hold/follow foundations; companion ownership must be independent of F7 and conversation radius. |
| 44 | Party-aware dialogue | Let a companion know who is travelling with Coen, their role and immediate danger. | Mod logic over observed state and the existing Convai context bridge; avoid global hidden-enemy knowledge. |
| 45 | Battle memories | Remember that a companion fought beside Coen or was ordered to retreat. | Mod-owned event log + Convai context/memory. Record only observed events; inferred kill ownership must not become a fact. |
| 46 | Relationship/reliability layer | Track fulfilled orders, rescues and chosen treatment; optionally affect responses. | A new mod-authored system, not an existing discovered native affinity system. Quest lore remains separately gated. |
| 47 | Party banter with one speaker at a time | Short contextual remarks with speaker-labelled subtitles and lipsync. | Existing Convai audio/subtitles plus a new speaker queue; other rigs still need individual validation. |
| 48 | Recall/dismiss individual or all | Manage spawned companions without deleting story NPCs. | Native despawn requests exist; strict ownership is essential. No destructive cleanup on borrowed quest actors. |

### E. Complex orders

| # | Option | What it would do | Evidence and practical limit |
|---|---|---|---|
| 49 | Ordered sequences | “Follow me, then hold here, then attack my target.” | Mod graph; explicit completion rules and timeouts for every step. |
| 50 | Conditional branches | “If I am attacked, protect me; otherwise stay behind.” | Mod graph over allowlisted sensors; an unknown condition must report unsupported. |
| 51 | Temporary overrides | “Help Anca, then return to your flank role.” | Mod graph with saved intent and cancellation rules. |
| 52 | Group plans | “Bakir take the front, Lacra flank left, Anca stay back.” | Mod coordinator plus per-companion graphs; keep target identities and completion signals separate. |
| 53 | Ready / execute signal | Move companions into staging positions and begin on a command. | Mod graph; native travel control must prevent premature engagement first. |
| 54 | Saved tactics | Name and reuse a validated plan from F5 or conversation. | Local data, not executable Lua generated by a language model. |
| 55 | Explain current orders | Show “waiting for a path”, “target lost”, or “ability unavailable” in the panel. | Mod graph status and actual adapter results; never claim an action happened merely because Convai acknowledged it. |

## Additional roster candidates

All seven requested characters have definition assets in the catalogue. Use **Ambrus** as the display spelling, with “Ambrose” accepted as an input alias. Keep Crake/Marat aliases for compatibility with the existing roster. The publisher lists the main characters under their official names in its [character directory](https://en.bandainamcoent.eu/dawnwalker/the-blood-of-dawnwalker/characters).

The following are worthwhile additions to choose from, not automatically activated companions:

| Candidate | Why consider them | Local asset evidence / qualification |
|---|---|---|
| Uriash Matriarch / Bakr-Erga | Distinct spellcaster and possible shapeshifting/summoning role. | Boss definition and AI loaded in the earlier dump; full ability catalogue now available. |
| Leonica | Another distinctive caster with native teleport/AoE assets. | `NPCDef_Leonica_Base`; encounter mechanics make some powers unsuitable initially. |
| Ocha / Bakr-Ocha | A brawler could provide a different frontline style. | `NPCDef_Ocha` and fistfight variant; independent combat equipment/AI still unverified. |
| Drogos | A natural choice for a rebel party. | Boss and non-boss definitions exist. |
| Sara | Another rebel option. | Asset spelling is `Sarah`; do not use `Fight_with_Coen` as proof of alliance—it could mean fighting against him. |
| Catalin | Suits a human military party theme. | Named NPC definition exists; soldier assets are separate characters. |
| Pieter | A human swordsman option. | An explicit `NPCDef_Pieter_armed` variant is available. |
| Vladimir / Vlad | Another named human candidate. | Appearance and gameplay definitions are present. |
| Vicho | Useful for a conversation-oriented party option. | Named definition exists, but his lore makes an eager default combat role questionable. |
| Isbrand | An optional boss/sandbox character. | Base, boss, wounded and chained variants exist; use no assumption that all are interchangeable. |

The character glossary describes Ocha as a brawler, Drogos and Sara as rebels, Pieter as Coen's sword teacher, Catalin as a military claimant, and Vicho as reluctant to join the fight. Those descriptions guide these proposed roles; they do not establish a native moveset. [Character glossary](https://www.gamerguides.com/the-blood-of-dawnwalker/database/glossary/characters).

Rayko is another potential boss option: the Open Doors author's [local encounter findings](https://github.com/AlonResearch/OpenDoors-Dawnwalker-Mod/blob/master/Findings.md) identify him. I have not established his exact definition mapping, so he is not yet in the resolved candidate manifest. Ordinary guards, archers and creatures could form an optional generic roster once their variants are mapped; do not present every named villager as combat-ready.

## Things I would not promise from the current evidence

- **Full control over combos, attack direction, parry timing or guaranteed enemy aggro.** Those involve native decision/animation ownership, and a companion's target choice does not force the enemy to focus on them.
- **Ranged-only for every character.** A character needs a real ranged action set and an effective filter. Some may only support a range preference.
- **Generic party healing, revival or guaranteed nonlethal combat.** Health setters and resurrection-labelled encounter assets do not establish these systems.
- **Mounts, shared inventory/loot, pickpocketing, companions opening every door, or copying Coen's traversal powers.** No complete companion mechanism has been established for these.
- **Bosses working everywhere.** Guard/arena constraints are reflected; author reports of other mods also show encounter barriers. Prefer adapting owned clones over modifying world encounter systems.
- **Unlimited party size.** Navigation, AI tickets, animation, effects and audio all carry costs. A small configurable party is the sensible initial target; no measured safe maximum exists yet.

## Implementation decisions from this research

### Spawning is the first engine integration gate

The game exposes `Dawnwalker.SpawnPopulationActorAsyncAction.RunAsyncAction`, taking a world context, NPC-definition soft class, AI-definition soft class, location and rotation. This is preferable to creating an ordinary pawn and guessing how to initialize its appearance, equipment, population identity and AI. The helper variants give us concrete inputs to investigate.

The unresolved issue is safe soft-class marshalling in the supplied loader. An earlier crash in this project entered the native soft-reference copy path; Lua `pcall` cannot catch that kind of access violation. We have **not** called this factory during the research. A typed bridge or a verified compatible conversion may be required. The [UE4SS world-spawn helper](https://docs.ue4ss.com/dev/lua-api/classes/uworld.html) is an alternative actor constructor, but its existence does not establish Dawnwalker NPC initialization. Spawning remains unproven, despite now knowing the asset paths.

The catalogue fix was separate: RC5 still returns **struct elements** in result arrays as wrappers, requiring `assets[i]:get()`. Its non-struct outputs behave differently. Reading known `FAssetData` name fields after that unwrap produced the catalogue. The previous empty results were not evidence that these characters were missing. [Loader author's RC5 notes](https://www.nexusmods.com/thebloodofdawnwalker/mods/18).

### One owner for each kind of behavior

The party manager should own recruitment/spawning/dismissal. Conversation owns a temporary hold. The order runner owns high-level intent. RebelAI owns actual movement and combat execution. A conversation ending must release its hold without deleting party membership; a new combat order must not fight a continuously re-applied facing/stop command.

Native actions that cannot be interrupted should delay the next order, with a timeout and visible failure. Death, cinematics, travel, missing actors and cancellation must explicitly end or suspend the relevant graph. Use instance-specific relationships among party members and Coen; changing a global faction would affect unrelated quest NPCs.

### The graph is local and observable

Convai may interpret a sentence into a bounded command vocabulary. The game adapter validates targets and capabilities, then runs a local graph. Combat must continue without a network response every frame. Keep graph nodes, transitions, timeouts and current state visible in the F5 panel. The proposed graph is a Lua-owned state machine; we are not claiming to author new cooked Unreal StateTree assets at runtime.

Example intended plan: follow until combat starts → prefer left flank → assist the current hostile target → if wounded, regroup → resume only after recovery or another order. A recovery branch must fail or wait when there is no healing source, rather than invent healing. If flanking is unsupported for that actor, report it and use an explicit fallback chosen by the player.

Convai's [actions guide](https://docs.convai.com/api-docs/plugins-and-integrations/unreal-engine/guides/actions-guide) supports the separation between requested actions and application-side behavior. It does not supply Dawnwalker-specific adapters. Epic's [gameplay ability documentation](https://dev.epicgames.com/documentation/unreal-engine/using-gameplay-abilities-in-unreal-engine) explains ability eligibility, tags, costs and cooldowns; our installed-game dump, rather than the latest documentation's function list, is the authority for callable interfaces here.

### Focused verification

Use offline checks for manifest correctness, malformed/stale commands, graph termination and syntax. They cannot prove a character's combat behavior. The first useful gameplay checks are one owned spawn/dismiss cycle, native following, and assisting a single encounter. Reuse hot reload for Lua iterations. Special powers, strict ranged filtering and companion travel recovery need their own short checks only when implemented. No repeated broad test suite or gameplay-driving computer use is needed for this research stage.

## Choices to make before expanding implementation

The base F5 selector, requested roster, companion lifecycle, roles/engagement settings and complex-order foundation remain the requested work. Beyond that, the strongest optional directions are:

- **Tactical depth:** target spreading, protecting allies, pursuit limits, retreat/rest triggers, formations, staging and saved plans.
- **Character powers:** selective support for native counterspells, slams, clones, summons and forms, with unsupported powers clearly unavailable.
- **Travel and roleplay:** crouch/spacing preferences, persistent party presets, party-aware dialogue, observed battle memories and optional relationship/banter systems.

My recommendation is tactical depth plus a small selection of character powers, followed by travel/roleplay features the player actually wants. The research does not justify presenting every experimental option as enabled.
