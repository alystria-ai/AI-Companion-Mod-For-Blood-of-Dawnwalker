# 0.30.9 Preview release notes

- Fixes a repeated companion cleanup error after loading a save, including when all companions were dismissed before loading. This error could repeatedly interrupt the companion update and cause stuttering.
- Cleanup now accepts a protection effect or player ability system that the game has already destroyed, and an effect handle that the game has already removed.
- Uses engine-assigned weak object identities, where available, to avoid confusing an expired object with a replacement that has the same name. Exact effect ownership checks remain in place.

## Updating

Close the game before replacing files, then install Complete or both matching Scripts and Runtime archives. This fix changes the native protection DLL in Runtime; installing Scripts alone does not apply it. Keep your existing user settings and conversation data. No account or character reset is required.

## Validation

All 283 automated tests pass, including compiled native cleanup checks for destroyed objects, already-removed effects, reused object names and rejection of unrelated handles. The protection DLL builds successfully. Gameplay confirmation of repeated save loads is still pending.

Requirements remain game 1.05, UE4SS 1.2.1 RC6 and Dawnwalker Mod Menu 1.0.6.2 or later. Scripts and Runtime remain two required halves of the split installation.
