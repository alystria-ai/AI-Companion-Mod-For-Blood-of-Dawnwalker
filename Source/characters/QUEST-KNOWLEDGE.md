# Quest knowledge and companion lore

Reviewed 14 September 2026. Policy version 4 contains **54 grants across 27 quests and 17 named identities**, expanded from 32 grants. The 22 new grants resolve additional participant events and optional outcomes. This is curated coverage, not a claim that every quest branch is supported.

Pieter and Vladimir retain policy entries for existing/world identities; this file does not recreate their Convai characters or restore them to the summon menu. The 15 other named identities have reviewed quest coverage. The ten generic male/female profiles receive no named-character secrets or quest memories. Coen is the player reference, not a recipient of NPC quest grants.

| Character | Grants | Quest coverage |
| --- | ---: | --- |
| Anca | 10 | Withering Away; Smoke and Ashes; Echoes of Silenced Bells; Between the Words; Where Old Devils Lie; Stronger Than Achilles |
| Lacra | 6 | A Friend Like This; Song of the Mountain; Hive and Seek; Our Rotten Roots; The Night of Horrors |
| Crake | 6 | What Hunts the Night; Shadows in the Woods; What Moves the Dead; Who Pulls the Strings; Rise at Dawn; Where Loyalty Lies |
| Brencis | 3 | Bad Blood; Sacred Covenant |
| Xanthe | 2 | The Cycle of Love |
| Ambrus | 1 | The Gilded Gauntlet |
| Bakir | 1 | The Lunar Game |
| Bakr-Erga (the Elder) | 4 | Song of the Mountain; A Mother's Plea |
| Leonica | 1 | Echoes of Silenced Bells |
| Ocha | 4 | The Heart Wants What It Wants |
| Vicho | 4 | A Study in Crimson |
| Drogos | 1 | Shadows in the Woods |
| Sara | 2 | Shadows in the Woods; Where Loyalty Lies |
| Catalin | 1 | Rise at Dawn |
| Pieter (legacy/world identity) | 4 | Like Father, Like Son; Bad Blood; Sacred Covenant |
| Vladimir (legacy/world identity) | 2 | Bad Blood; Disturbed |
| Isbrand | 2 | Hive and Seek; Our Rotten Roots |

## Three kinds of knowledge

**Biography** supplies the character's established history, relationships, motives and speaking style through `personalLore`. Spoilers and established past secrets can belong here. Knowing one's past is different from knowing that Coen discovered it in this save. Pieter, for example, can know his own mercenary history without assuming that Coen has completed an investigation of it.

**Current-save quest facts** are the narrowly approved messages returned in `knowledge(snapshot, npc).facts`. They describe shared encounters or reports the recipient actually received. The raw player journal is never pasted into these messages: its first-person interpretation and private discoveries are not automatically an NPC's knowledge.

**Conversation memory** records what the player and characters said. A player can tell a companion something the quest policy has not established; that is a reported claim, not a new witnessed event. Group-chat relationship selection is separate and does not authorize copying one companion's quest memories to the others.

The game and browser maintain local timeline/session information, but Convai long-term memory uses the shared player identity chosen for this mod. The same character's cloud memory can retain dialogue or facts from an earlier save. Current-save context tells the character which quest facts now apply; loading an older save does **not** delete the character's cloud history. This policy provides current-save facts, not guaranteed cloud-memory erasure or isolation.

## How a grant is selected

The collector's journal snapshots are captured in `runtime/quests.txt` and `runtime/quest-memory.json`. They include the native instance identifier, displayed title, state and selected ending. The reviewed prefixes in this policy come from those captures; wiki titles alone are not used to invent native identifiers.

Each rule in `quest-knowledge.json` has:

- `key`: stable fact identifier.
- `recipient`: exact local character key. Crake remains `marat` internally, but his display name is Crake.
- `quest` and `idPrefix`: both must match. The exact title protects against related native prefixes, including Anca's two Font quests.
- `state`: currently always `EQS_Success`. An active or failed quest does not grant a completion memory.
- `endingPattern`: an optional reviewed positive regex. Branch facts require recognizable selected-ending evidence.
- `endingNotPattern`: an optional rejection regex. Contradictory choices or hostile outcomes reject the relevant branch.
- `text`: short authored knowledge from this participant's perspective.
- `source` and `reason`: evidence and explanation of what completion actually guarantees.

The bridge compiles the trusted patterns once when loading the policy. It searches for a journal row satisfying the complete rule, including positive and negative ending checks. An earlier nonmatching instance cannot hide a later matching one; repeated matching rows emit the fact only once. It never compiles a regex supplied by the game or a conversation.

The returned ledger contains hashes of journal state and ending, plus a policy hash. The knowledge revision includes policy, snapshot and recipient identity. Revising a rule changes the policy revision; changing NPCs changes the recipient revision. Regenerating facts from an older snapshot removes incompatible current-save facts. The ledger supports the surrounding timeline logic and is not character prose.

A missing fact means **not established for this recipient**, rather than proof that the event never happened. Missing or unavailable journal data cannot be filled from a wiki, a generic quest-complete count, friendship or faction ownership.

## New branch coverage

Anca has separate memories for performing or being prevented from performing Leonica's remedy, and for receiving the Font, watching Coen use it, or seeing it destroyed. Performing the ritual does not establish romance or eventual recovery. Leonica only gets her own encounter; she does not inherit the decision made after her defeat. The recorded ending alternatives are documented in [Echoes of Silenced Bells](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/echoes-of-silenced-bells) and [Stronger Than Achilles](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/stronger-than-achilles).

Lacra distinguishes sharing the mandrake with Coen from taking its power when he declines. Both are separate from abandoning the swamp search, and neither establishes a kiss or particular confession. Isbrand gets the completed Broken Shade encounter, without an automatic invitation into Coen's mind. See [The Night of Horrors outcomes](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/the-night-of-horrors) and [Our Rotten Roots walkthrough](https://www.powerpyx.com/blood-of-dawnwalker-our-rotten-roots-walkthrough/).

Crake remembers admitting Coen into the Manumits, and Sara remembers the hideout escort. Neither receives the scouts' findings merely because Coen discovered them: Crake's report arrives through the next quest. Vladimir's optional reunion is withheld because induction does not prove his survival or presence. See [Where Loyalty Lies](https://www.powerpyx.com/blood-of-dawnwalker-where-loyalty-lies-walkthrough/) and [What Hunts the Night](https://www.powerpyx.com/blood-of-dawnwalker-what-hunts-the-night-walkthrough/).

Ocha distinguishes returning to her clan, staying in Svartrau and planning to leave the valley. Her mother receives a return/independence update only from her own completed report quest. A dead Ocha or an explicit vengeance/revenge ending receives no friendly resolution. The death ending alone does not prove why she died, so it cannot safely create a clan-vengeance memory either. See [Ocha's outcomes](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/the-heart-wants-what-it-wants) and [A Mother's Plea](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/a-mothers-plea).

Vicho's initial Simeon investigation remains distinct from a later explicit confrontation over his own killings. The later outcomes distinguish continuing life with Coen's blood-supply promise, facing dawn with Coen beside him, and facing dawn after Coen leaves. A private discovery the player conceals grants none of those later memories. A promise to provide blood is not a completed delivery. See [A Study in Crimson outcomes](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/a-study-in-crimson).

Pieter and Brencis get different memories depending on whether Esme survived Blood Mass or Brencis killed her there. Brencis does not thereby learn how Coen prepared her medicine. See [Sacred Covenant outcomes](https://www.gamerguides.com/the-blood-of-dawnwalker/database/journal/quests/sacred-covenant).

Xanthe's base encounter is now location-neutral. A separate rule adds the keep only when the captured ending explicitly places Coen there. Cathedral success must not imply a keep visit, and a keep visit does not establish a bargain or blood-drinking choice. See [The Cycle of Love walkthrough](https://www.powerpyx.com/blood-of-dawnwalker-the-cycle-of-love-walkthrough/).

## Current capture and limits

The reviewed local capture contains 105 journal entries. Running the policy against that capture produces 36 recipient facts in total: Anca's performed ritual and Font choice, Lacra's shared mandrake, the Manumit induction/escort and the surviving-Esme branch all match. Ocha's failed quests produce no facts; the still-active outpost quest produces no completed-outpost memory for Catalin. These observations describe the captured save, not every user's game.

The policy explicitly lists **65 captured quest titles with no reviewed grant** in `withheld` and **36 unresolved recipient/branch candidates** in `pendingCandidates`. Those counts overlap in subject matter: the latter also covers unsupported optional branches inside otherwise supported quests. Both lists are documentation only and never enter runtime facts.

Important gaps include:

- Crake's Ascar investigation, private confession, wound-care choices and optional intimacy need captured identities or selected dialogue evidence.
- Drogos's referral/scouting and optional hideout conflict need proof he participated or received a report.
- Sara's churchyard participation needs a stage signal that does not give her knowledge of later events after her fatal encounter.
- Lacra's optional solitary-memory discussion, Isbrand invitations and finale participation need distinct choices/stages.
- Brencis's parley, deals and family outcomes; Catalin's prisoner choices and final government; and Xanthe's bargain or actual castle assistance need outcome evidence.
- Ambrus's poison/drain/invitation and Bakir's feast/treasury/drain/invitation cannot be inferred from their deaths.
- Ocha's exact memento, hex result, Nora's survival and vengeance cause need their own branches.
- Vicho's blood deliveries need an observed delivery event and ordering, not repeated polling of a promise.
- Pieter's knowledge of Coen's discoveries and Vladimir's rescue, reunion or reports about Mert need explicit participant evidence.

All four files under `characters/research/` were reviewed. Their quest candidates are research suggestions; adding richer static biography does not activate a candidate. Court activities remain withheld from rulers who did not witness a loss or receive a report. Being a friend, ruler, clone or group-chat responder never grants global quest knowledge.

Summoned copies of characters who died in the campaign do not undo that outcome. A memory can describe their own encounter without claiming they observed later private player choices, visited a place their route skipped, or survived every subsequent scene.

## Validation and extension

`tests/quest-knowledge.test.mjs` currently has **55 passing tests**. Independent fixtures exercise every one of the 54 grants and check all named recipients, the player reference and ten ambient profiles. Every positive route is also tested with a wrong title, wrong identity, active state and failure state. Additional cases cover opposing choices, hostile Ocha endings, concealed Vicho truth, mother/report separation, Leonica's limited perspective, duplicate instances, apostrophe variants, rollback and the withheld candidates.

To extend coverage:

1. Capture the actual native identity, exact English title, selected ending or objective event. Do not derive an ID from a wiki slug.
2. Verify the event in a reliable quest/dialogue source and identify exactly what this recipient witnessed or was told.
3. Separate optional choices into guarded rules. Add negative evidence when a hostile or contradictory ending could otherwise match. Do not use a reward, ability unlock or another NPC's friendship as a substitute for a missing scene.
4. Write a short original participant memory with explicit limits where they matter. Link the source and explain why this event is guaranteed.
5. Add an independent positive fixture plus wrong-recipient, failed/active and alternative-outcome tests. Assert `.facts` for quest isolation; the combined `.text` deliberately includes the character's richer static biography.
6. Test a real snapshot without changing the save or its journal, then refresh the bridge so the policy is loaded and the changed policy hash reaches subsequent context updates.

Run the focused check with `node --test tests/quest-knowledge.test.mjs`. The source path and command are portable; this policy does not require a particular installation directory.
