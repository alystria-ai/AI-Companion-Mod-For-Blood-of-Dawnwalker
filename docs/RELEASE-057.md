Crake now has his own romance conversation profile, and a damaged configuration file no longer silences every character.

## Changes

- Added a Crake romance profile with its own Auto, On and Off setting in the companion menu. In Auto it turns on once you choose the intimate ending of his quest *A Closer Look*. On and Off always work. Like Anca and Lacra's profiles, it changes conversation only and plays no cutscene, and Crake never takes part in the Anca and Lacra rivalry banter.
- Fixed the helper stopping all character talk when a configuration file was damaged. It now names the damaged file and line in the log and carries on without that file. A damaged `runtime/convai-config.json` is set aside as `.broken-<time>` and built-in defaults are used. A single unexpected error in one request no longer ends the helper.

## Settings and defaults

Existing settings and saves are unchanged. The new **Crake romance profile** setting defaults to Auto. Anca and Lacra keep their own independent settings.

## Installation

Close the game. Extract **Complete**, or **both Scripts and Runtime for 0.5.7**, into the game installation folder, merging the included `Dawnwalker` folders. Neither split ZIP works alone: the helper, character data and Lua scripts change together.

Requires **The Blood of Dawnwalker 1.05**, **UE4SS for Dawnwalker 1.2.1 RC6**, and **Dawnwalker Mod Menu 1.0.7 or later**. Back up and restore `config.ini` and `keybindings.ini` to preserve preferences. Keep generated conversation data and reapply the matching optional **Multilingual** pack after updating. No Convai account or API key setup is needed.

If the helper still reports a damaged file after updating, use Copy logs and send the result: the log now names the file.
