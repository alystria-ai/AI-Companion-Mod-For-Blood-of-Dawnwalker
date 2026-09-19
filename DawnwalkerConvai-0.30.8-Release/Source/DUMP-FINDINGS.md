# Native dump findings — 9 September 2026

UE4SS DumpAllObjects completed against the running game at 02:59 local time. Output: `<game>/Dawnwalker/Binaries/Win64/ue4ss/UE4SS_ObjectDump.txt` (152,778,854 bytes). Forced asset loading was disabled. This reflects loaded objects, not every asset in the installed game.

Official references: [DumpAllObjects](https://docs.ue4ss.com/dev/lua-api/global-functions/dumpallobjects.html), [dumper options](https://docs.ue4ss.com/dev/feature-overview/dumpers.html).

- RebelAIBlueprintFunctionLibrary.GetAIStub(Pawn) returns RebelAIStub; its GetNPCDefinition() returns CommunityNPCDefinitionBase.
- DogwoodNPCDefinition exposes CharacterName (TextProperty), VoiceTag (GameplayTag), and inherited BodyType (NameProperty). These precise fields are read once per selection. No arbitrary runtime property traversal or SoftObject reads.
- Live results: Anca / Woman / vt.e.anca / NPCDef_Anca; Lacra / Woman / vt.e.lacra / NPCDef_Lacra. Matriarch has BodyType Uriash. A rabbit reports Man, so body type alone is insufficient to identify a human.
- The UI loads Afacad-Regular, Afacad-Italic and Afacad-SemiBold font assets. The overlay uses a separately obtained OFL-licensed Afacad font; license is in bridge/fonts/OFL.txt.
- Native UI candidates include DogwoodUI.MovieSubtitleWidget.UpdateSubtitle(FText) and WBP_GameplayDialogue_HUD. Their lifetime, subtitle ownership and input behavior remain unverified; the mod does not alter them.
- DogwoodNPCDefinition also exposes face-layer class references and soft idle-animation references. The working face adapter remains intact. Soft idle references are not dereferenced, given the previous loader crash.

Filtered metadata is saved in runtime/identity-metadata.txt. Live identity rows are in runtime/npc-identities.tsv. Native dumps are explicit, one-shot development actions, not repeated per frame or F6.

## Companion asset catalogue — 12 September 2026

A read-only `AssetRegistry.GetAssetsByPath` query succeeded while the game was paused, without loading the returned assets. Query roots were `/Game/_Dawnwalker/NPC`, `/Game/_Dawnwalker/Combat/Enemies`, and `/Game/_Dawnwalker/Quest`, recursively, filtered to `NPCDef_`, `AIDef_`, `AIConfig_`, and `GA_AI_` names. The output contains 2,698 unique packages (2,428 NPC definitions, 94 AI definitions, 63 configs and 113 abilities). See [the catalogue](runtime/companion-asset-catalog.tsv) and [companion research](docs/COMPANION-POSSIBILITIES.md).

The supplied RC5 loader returns struct entries in result arrays as wrappers requiring `:get()`. Earlier attempts read wrapper fields directly and produced nil names; passing the wrong wrapper to helpers produced empty names. Unwrapping `assets[i]:get()` and reading only the reflected `AssetName`, `PackageName` and `PackagePath` FNames fixed discovery. Non-struct return-array elements follow different rules; do not add `:get()` indiscriminately. The [loader author's notes](https://www.nexusmods.com/thebloodofdawnwalker/mods/18) describe this distinction. No generic property traversal, soft-object reads or TArray callback iteration were needed.

An earlier fixed `AssetRegistry.DumpState ObjectPath` console request returned without a Lua error, but no resulting file was located in the checked game/local Saved paths. That was not treated as a successful catalogue. The current TSV comes from the successful reflected registry query.

Bakir, Ambrus and Xanthe have `NPCDef_Summoned_CoenHelper_*` and `AIDef_Summoned_CoenHelper_*` packages. These are promising inputs for the native population spawner, but no spawn or combat trial was performed. A generated asset name does not establish its lifespan, allegiance, arena independence or ability eligibility. The remaining safe soft-class marshalling issue is documented in the research report.
