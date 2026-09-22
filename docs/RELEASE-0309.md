# 0.30.9 Preview release notes

- Fixes a repeated companion cleanup error after loading a save, including when all companions were dismissed before loading. This error could repeatedly interrupt the companion update and cause stuttering.
- Cleanup now accepts a protection effect or player ability system that the game has already destroyed, and an effect handle that the game has already removed.
- Uses engine-assigned weak object identities, where available, to avoid confusing an expired object with a replacement that has the same name. Exact effect ownership checks remain in place.

## Updating

Close the game before replacing files, then install Complete or both matching Scripts and Runtime archives. This fix changes the native protection DLL in Runtime; installing Scripts alone does not apply it. Keep your existing user settings and conversation data. No account or character reset is required.

## Validation

All 283 automated tests pass, including compiled native cleanup checks for destroyed objects, already-removed effects, reused object names and rejection of unrelated handles. The protection DLL builds successfully. The player confirmed the save-reload fix works in game. GitHub Actions built and verified the release packages and recorded build provenance.

Requirements remain game 1.05, UE4SS 1.2.1 RC6 and Dawnwalker Mod Menu 1.0.6.2 or later. Scripts and Runtime remain two required halves of the split installation.

## Optional multilingual voices

The additional `DawnwalkerConvai-0.30.9-Multilingual.zip` replaces one Runtime JSON configuration file with IDs for separate copies of all 26 cloud conversation profiles. It contains only that JSON file and a text installation note. These copies retain the character biographies, actions and quest context while using Azure multilingual voices. English alone is selected on each copy, and the owner has disabled the dashboard language restriction. All 26 copies produced Russian replies in testing; the profiles that responded in English through the Core API were also checked through the Web SDK used by the mod, where all nine produced Russian text and audio. Spanish and French text and audio were also tested on Anca. The owner tested Arabic in the dashboard. Other languages may work but have not all been tested. In-game microphone recognition remains untested. The original English Kokoro profiles are unchanged. Reinstall normal Runtime or Complete to switch back. Because the copies use distinct character IDs, they begin separate conversation histories and cloud memories.
