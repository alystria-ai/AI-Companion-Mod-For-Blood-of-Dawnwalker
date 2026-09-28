Addons can now control whether their creatures join automatic conversations, without changing how your regular companions behave.

## Changes

- Added an optional per-character reaction opt-out to the shared addon API. Rideable Mount Companions uses it to keep beasts quiet during exploration, looting and battles while retaining direct text and voice conversations and commands.
- The game checks the preference when choosing a speaker, and the helper checks again before sending an automatic request. Older addon registrations keep their existing behavior.
- Improved shortcut recovery when Windows cannot register the mount key combination. Successfully registered shortcuts do not use the fallback polling path.
- Copy logs includes addon startup errors and status.

## Settings and defaults

Your main-mod settings and defaults are unchanged. Regular companions still follow the global battle, loot and exploration reaction settings. The new opt-out belongs to each addon registration; it does not disable spoken replies, subtitles or commands. Pets are managed entirely by the separate mount addon.

## Installation

Close the game. Extract **Complete**, or **both Scripts and Runtime for 0.5.6**, into the game installation folder, merging the included `Dawnwalker` folders. Both split downloads are required: the shared registration change uses Scripts and Runtime together.

Requires **The Blood of Dawnwalker 1.05**, **UE4SS for Dawnwalker 1.2.1 RC6**, and **Dawnwalker Mod Menu 1.0.7 or later**. Back up and restore `config.ini` and `keybindings.ini` to preserve preferences. Keep generated conversation data and reapply the matching optional **Multilingual** pack after updating. No Convai account or API key setup is needed.

For the new Pets category, also install [Rideable Mount Companions 0.1.1](https://github.com/alystria-ai/Rideable-Mount-Companions/releases/tag/v0.1.1).
