# Dawnwalker Convai character profiles

The 14 September research catalogue has 28 portable profiles: 17 researched named NPCs, Coen as a reference, and ten original ambient personas. The active account has 26; Pieter and Vladimir were absent and were not recreated. The F5 companion roster remains 15.

Descriptions include biography, personal relationships, speaking rules and original sample exchanges. Established spoilers are allowed; conditional quest choices still require save evidence. No complete verified game script was found, and the samples are not presented as quotations.

## Paste into your own account

Open a text export below and paste its contents into the character's **Core Description**. Select a currently available Convai Kokoro voice, enable LTM in Memories → Memory Settings if your account permits it, and map your own character ID in `runtime/convai-config.json`. The source account's character IDs are not portable. The separate speaking-style controls can remain blank: their instructions and examples are included in these Core Descriptions.

| Profile | Description | Facts | Relationships | Samples | Current cloud voice |
| --- | --- | ---: | ---: | ---: | --- |
| Anca | [Pasteable text](profile-text/anca.txt) | 20 | 7 | 6 | Emily (Friendly Young-Adult American Female) |
| Brencis | [Pasteable text](profile-text/brencis.txt) | 18 | 7 | 6 | Harry (Deep Middle-Aged British Male) |
| Lacra | [Pasteable text](profile-text/lacra.txt) | 18 | 6 | 6 | Freya (Authoritative Adult British Female) |
| Crake | [Pasteable text](profile-text/marat.txt) | 20 | 9 | 6 | Arthur (Husky Middle-Aged British Male) |
| Xanthe | [Pasteable text](profile-text/xanthe.txt) | 17 | 6 | 6 | Freya (Authoritative Adult British Female) |
| Ambrus | [Pasteable text](profile-text/ambrus.txt) | 10 | 6 | 6 | George (Light Young British Male) |
| Bakir | [Pasteable text](profile-text/bakir.txt) | 11 | 7 | 6 | Oliver (Husky Middle-Aged British Male) |
| Coen | [Pasteable text](profile-text/coen.txt) | 11 | 6 | 6 | Ethan (Calm Young-Adult American Male) |
| Roadside Laborer | [Pasteable text](profile-text/male-1.txt) | 1 | 0 | 6 | Oliver (Husky Middle-Aged British Male) |
| Market Trader | [Pasteable text](profile-text/male-2.txt) | 1 | 0 | 6 | George (Light Young British Male) |
| Cautious Townsman | [Pasteable text](profile-text/male-3.txt) | 1 | 0 | 6 | Harry (Deep Middle-Aged British Male) |
| Traveling Artisan | [Pasteable text](profile-text/male-4.txt) | 1 | 0 | 6 | Arthur (Husky Middle-Aged British Male) |
| Young Villager | [Pasteable text](profile-text/male-5.txt) | 1 | 0 | 6 | Ethan (Calm Young-Adult American Male) |
| Market Woman | [Pasteable text](profile-text/female-1.txt) | 1 | 0 | 6 | Amelia (Expressive Young-Adult British Female) |
| Village Weaver | [Pasteable text](profile-text/female-2.txt) | 1 | 0 | 6 | Freya (Authoritative Adult British Female) |
| Roadside Traveler | [Pasteable text](profile-text/female-3.txt) | 1 | 0 | 6 | Isla (Expressive Young British Female) |
| Weathered Villager | [Pasteable text](profile-text/female-4.txt) | 1 | 0 | 6 | Linda (Deep Middle-Aged American Female) |
| Quiet Townswoman | [Pasteable text](profile-text/female-5.txt) | 1 | 0 | 6 | Helen (Gentle Middle-Aged American Female) |
| Bakr-Erga | [Pasteable text](profile-text/matriarch.txt) | 10 | 5 | 6 | Linda (Deep Middle-Aged American Female) |
| Leonica | [Pasteable text](profile-text/leonica.txt) | 10 | 4 | 5 | Helen (Gentle Middle-Aged American Female) |
| Ocha | [Pasteable text](profile-text/ocha.txt) | 11 | 5 | 6 | Isla (Expressive Young British Female) |
| Vicho | [Pasteable text](profile-text/vicho.txt) | 11 | 5 | 6 | Arthur (Husky Middle-Aged British Male) |
| Drogos | [Pasteable text](profile-text/drogos.txt) | 8 | 5 | 5 | Oliver (Husky Middle-Aged British Male) |
| Sara | [Pasteable text](profile-text/sara.txt) | 10 | 5 | 5 | Amelia (Expressive Young-Adult British Female) |
| Catalin | [Pasteable text](profile-text/catalin.txt) | 12 | 6 | 5 | Ethan (Calm Young-Adult American Male) |
| Pieter | [Pasteable text](profile-text/pieter.txt) | 12 | 8 | 6 | Research only; no active cloud profile |
| Vladimir | [Pasteable text](profile-text/vladimir.txt) | 11 | 7 | 6 | Research only; no active cloud profile |
| Isbrand | [Pasteable text](profile-text/isbrand.txt) | 12 | 4 | 6 | Harry (Deep Middle-Aged British Male) |

The display name is **Crake**. `marat` remains the compatibility key and export filename. Coen is excluded from automatic NPC matching. Ambient personas are original roleplay designs, not undocumented canonical characters.

## Files and workflow

[profiles.json](profiles.json) is the structured portable export. [research](research/) holds sourced facts, uncertainty, speaking rules, samples and candidate quest branches. [companion-lore.json](companion-lore.json) supplies concise runtime lore and group relevance; [QUEST-KNOWLEDGE.md](QUEST-KNOWLEDGE.md) explains the 54 recipient/branch rules.

Run `node scripts/build-character-profiles.mjs` to rebuild exports. `python scripts/apply-researched-profiles.py` previews changes to existing owned characters; add `--apply` to write and verify them on an account that allows Core API writes. Do not run cloud maintenance merely to play.

The active installation now reuses one player end-user ID across characters. Their cloud memories remain separate by character; clones share their character memory. Generic actors assigned the same persona share its cloud LTM even though their sessions differ. Local save timelines branch, but old cloud memories are not automatically erased.

See full research, Convai API methodology, validation and limitations and [installation/customization instructions](../README.md).
