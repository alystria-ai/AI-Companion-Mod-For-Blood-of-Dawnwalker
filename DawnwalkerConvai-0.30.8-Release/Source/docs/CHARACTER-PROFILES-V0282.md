# Character research, Convai profiles and one-player memory

Updated 14 September 2026. Browser bridge v0.28.2; the Lua and native components are unchanged by this update.

## What was changed

The portable catalogue contains 28 profiles with 242 sourced background facts, 108 directed relationships and 164 original dialogue examples. Descriptions range from 406 to 927 words, below Convai's documented 1,000-word core-description limit. The ten ambient profiles are original personas; their jobs and mannerisms are not claimed as named game canon.

The active account contained 26 matching characters: the 15 summonable companions, Coen's reference profile and ten ambient personas. All 26 were updated through Core API and checked with a separate readback. Their descriptions contain identity, background, relationships, speaking rules and sample replies. Their current voices are from the Convai Kokoro catalogue, with no ElevenLabs voices. The existing `fast-gemma-4-31b-it` model choices were preserved.

Pieter and Vladimir remain research templates but were absent from the account and were not recreated. They remain excluded from F5. Coen is a reference profile, not a selectable world NPC or companion.

## Research method and confidence

Start with the [publisher's character pages](https://en.bandainamcoent.eu/dawnwalker/the-blood-of-dawnwalker/characters) and [Coen's family bulletin](https://en.bandainamcoent.eu/dawnwalker/news/community-bulletin-board-9-coens-roots). Cross-check them with the indexed character, quest, readable and lore records at [DawnwalkerDB](https://dawnwalkerdb.com/characters), including its [readables](https://dawnwalkerdb.com/readables) and [lore](https://dawnwalkerdb.com/lore) catalogues. Quest walkthroughs provide branch context; the live UE4SS journal supplies evidence of this save's actual outcomes. Every fact and relationship keeps its source URLs in `characters/research/*.json`.

No complete, verified public English script was found. The profiles use concise paraphrases of researched facts. Speaking rules and example exchanges are original editorial writing, not quotations represented as game dialogue. Sources differ in reliability: uncertain reports remain labelled in the research rather than silently becoming verified canon. Bakr-Erga's personal history is sparse; the profile does not fill that gap with an invented life story.

Established personal history is available, including spoilers. Optional quest choices, deaths, romance and current loyalties still require current-save evidence. Examples of researched relationships are the Isbrand → Brencis → Lacra sire chain, Anca and Leonica's convent friendship and betrayal, and Crake's estrangement from his father Ascar. These are directed descriptions: a maker, an ancestor and an enemy are different relationships, not a single generic friendship score.

## Rebuilding and updating

The files have separate responsibilities:

| File | Purpose |
| --- | --- |
| `characters/research/*.json` | Sourced facts, personal relationships, uncertainty, original speaking rules and examples. |
| `scripts/build-character-profiles.mjs` | Validates coverage, provenance and word counts; builds the portable exports and local personal lore. |
| `characters/profiles.json` | Rich structured profiles without API keys or account-specific character IDs. |
| `characters/profile-text/*.txt` | Core Descriptions ready to paste into the Playground. |
| `characters/companion-lore.json` | Concise runtime background, directed relationship knowledge and editorial group-speaker relevance. |
| `scripts/apply-researched-profiles.py` | Updates existing owned cloud characters, verifies description/voice/LTM readback and checkpoints the live mapping. |
| `characters/quest-knowledge.json` | Explicit current-save recipient and branch rules; maintained independently of the biography. |

After editing the research, run:

```powershell
node scripts/build-character-profiles.mjs
python scripts/apply-researched-profiles.py
python scripts/apply-researched-profiles.py --apply
```

The second command is a read-only plan. `--apply` writes profiles using the configured account's permissions. `--only anca lacra` limits the selection. The compatibility entry point `update-managed-profiles.py` now delegates to this updater and is also read-only unless given `--apply`. Older provisioning scripts create baseline profiles and can overwrite enriched descriptions, so inspect them before use and apply the researched profiles afterward.

The updater verifies that each ID exists on the configured account and retains the mod's ownership marker. It does not recreate missing characters. It preserves each current Kokoro voice when allowed by the fetched voice catalogue and checks every write with `/character/get`; a success message alone is not sufficient. Private backups and reports stay under `runtime/profile-enrichment/`.

### Core Description versus speaking-style fields

The confirmed description write is `POST /character/update` with `{charID, backstory}`. LTM uses `memorySettings: {enabled: true}` on writes and appears as `memory_settings` on reads. The camelCase memory field is confirmed by the [official Unreal SDK implementation](https://github.com/Conv-AI/Convai-UnrealEngine-SDK-V4/blob/98575b10a0b85facd570ed29decb5a65a8b3b49b/Source/Convai/Private/RestAPI/ConvaiLTMProxy.cpp#L224-L258).

Attempts to write the native speaking-style fields were acknowledged but did not persist. Consequently, all rules and examples are included in the verified Core Description. The separate Playground speaking-style/sample fields may remain blank. `profiles.json` also exports a `speakingStyle` object for developers who prefer to paste those parts into the dedicated controls manually. Do not mistake an empty dedicated field for an empty core description.

## Free-account setup

Create characters through your own Playground and paste each `profile-text` file into its Core Description. Choose a currently available Convai Kokoro voice, then put your character IDs and API key in `runtime/convai-config.json`. Do not copy the original account's IDs as if they were portable profiles. See the root README for installation and identity aliases.

Account entitlements are separate. On the supplied free account, profile reads succeeded but the Core API memory-setting write was rejected as requiring an upgrade. That does not establish that its dashboard's one-LTM-end-user allowance is unavailable. Where permitted, open each character's **Memories → Memory Settings** and enable Long Term Memory in the Playground. See [Convai's memory guide](https://docs.convai.com/api-docs/convai-playground/character-customization/memory). The active mod account's 26 toggles were enabled and verified by API.

Using Kokoro avoids an ElevenLabs voice requirement; it does not remove Convai's credit or concurrent-connection limits. The mod's parallel group preparation and warm party connections also depend on the account's separate connection allowance.

## One player identity across characters

An LTM end user identifies the human player. `QuestMemory.user()` now returns the same player ID to every character, generic persona and clone. Convai separates memories by character plus end user; sharing the player ID does not make Anca automatically know Lacra's conversations. [Convai end-user documentation](https://github.com/Conv-AI/Convai-Documentation/blob/main/plugins-and-integrations/unity-plugin-beta-overview/features/long-term-memory/end-user-management.md).

Set optional `endUserId` in the private configuration to reuse the end-user ID you already have. An empty value creates and persists one local UUID per API-key fingerprint. The hash scopes storage without another plaintext key. For a key rotation, another machine or a WebView reset, retain the explicit ID if you want to keep using the same cloud end-user slot. Use different IDs for different real players; never distribute your personal ID as a shared default.

For the existing installation, the current Anca player ID was reused as the shared ID. Old per-character end-user records were not deleted or automatically merged. Old memories recorded against other IDs do not migrate merely because the new code shares one ID.

Session IDs remain distinct by player, character and local timeline. Named clones share their character session; generic actors have separate sessions by actor path. Two generic actors assigned the same cloud persona still share that persona's long-term memory for this player. Their local sessions and the mod's listener records remain separate. Truly separate cloud memories for those actors would require separate cloud character profiles or additional end-user identities.

## Quest memory versus conversational LTM

The UE4SS journal export is matched against 54 reviewed recipient/branch rules across 17 researched named identities. Current-save facts enter temporary context immediately; eligible facts may also be submitted through `memoryManager.addMemories` in batches of at most 16 with deduplication and retry backoff. A cloud-memory failure does not disable the live quest context or prevent sending a response request.

Rules now distinguish Anca's ritual and Font choices, Lacra's mandrake outcomes, Ocha's destinations, reports to her mother, Vicho's later revelations, and additional participant-specific events. Xanthe's general confrontation memory no longer assumes the keep was its location. Ocha's friendly resolution requires a supported ending and rejects hostile/death branches. Unknown internal IDs, unobserved relationship flags and ambiguous outcomes remain withheld; research coverage is not a claim that every quest branch can be detected. See [the rule catalogue](../characters/QUEST-KNOWLEDGE.md).

Save rollback or a changed knowledge policy branches local quest and heard-dialogue timelines and starts fresh sessions. It no longer allocates another LTM end user. This means cloud LTM can still contain older-save facts for the same player and character. Current-save context is explicitly authoritative, but it cannot guarantee that an LLM never recalls a stale cloud fact. The mod does not delete cloud history to simulate a rollback.

## Validation

All 26 cloud descriptions matched the compiled exports on readback; each voice belonged to the fetched Convai Kokoro catalogue, and all 26 returned `memory_settings.enabled: true`. Fresh, text-only Interaction API questions supplied no mod lore or quest context. Anca identified Leonica's library betrayal; Lacra correctly identified the sire chain; Crake named Ascar and described their estrangement. These three responses took approximately 4.3, 2.4 and 2.7 seconds respectively. These are individual REST test timings, not a measurement of in-game voice latency or exhaustive lore accuracy.

Offline checks cover shared end-user persistence, account separation, character session separation, clone reuse, group response sequencing, quest recipients and positive/negative branch cases. Cloud profile updates and bridge reloads do not require changing UE4SS or dismissing the existing party.
