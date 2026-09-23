# AI Companion Manager 0.30.9

This update fixes the heavy stuttering and repeated UE4SS errors that could start after reloading a save, even if you dismissed your companions first. Companion cleanup now handles game objects that have already gone away. The fix was confirmed in game and passes the automated tests.

## Install or update

Close the game, then install **Complete** or both **Scripts** and **Runtime** for 0.30.9. The save-reload fix is in Runtime, so replacing Scripts alone will not fix it. Keep your existing settings and conversation data when updating.

Requires The Blood of Dawnwalker 1.05, UE4SS 1.2.1 RC6, and Dawnwalker Mod Menu 1.0.6.2 or later.

## Optional multilingual voices

The **Multilingual voices** ZIP switches all 26 conversation profiles to new cloud character IDs with voices supporting 25 languages, including Russian, Spanish, French, Arabic and Japanese. The characters keep their personalities and quest knowledge, but the new IDs start fresh conversation histories. The ZIP contains only a configuration file and an installation note.

Install the main mod first, then copy the multilingual ZIP into the game folder and replace the configuration file. The original English voices remain the default if you skip this add-on. To switch back later, reinstall the normal Runtime or Complete ZIP.
