Nightmare brings full waves of random bosses to the Horde page. This update also adds optional exploration and loot reactions, a camera shortcut, and player settings for travel, looting and learned abilities.

## New features

- **Nightmare mode:** start it from its own button on the right of F5 > Horde. Bosses are drawn from a 32-entry pool, including Brencis, Xanthe, Ambrus and Bakir, without repeats until the pool is exhausted. The full group loads before combat and fights together. Clear the wave, rest, then face the next group. Defeated bodies remain.
- **Camera shortcut:** F4 switches between first- and third-person view. Remap it under Controls; existing key assignments are preserved.
- **Exploration reactions:** a nearby companion can respond after Coen finishes a solo observation. There is at least a three-minute gap, and his scripted conversations with other characters are excluded.
- **Loot reactions:** one random companion can comment after a completed batch of pickups. Ordinary loot has a 20% chance and a ten-minute minimum gap. New Legendary-tier weapons or clothing have a separate two-minute exception. Storage withdrawals stay silent.
- **Player conveniences:** use learned day and night abilities at either time, activate learned passives without slots, spend skill points away from shrines, automatically collect nearby free loot, or travel from the map to icons and custom waypoints. Each feature has its own toggle.

## Optional settings and defaults

All new settings are optional. Change them independently in F5 > Settings. These are the bundled defaults; restoring an existing configuration keeps your saved choices, and missing entries receive their defaults automatically.

| Setting | Default | When enabled |
| --- | --- | --- |
| React to Coen's observations | **On** | Allows occasional replies to solo exploration lines, outside combat, cutscenes and manual chat. Turn Off to disable these automatic replies. |
| React to collected loot | **On** | Allows occasional comments about completed pickup batches, with cooldowns and no storage-withdrawal comments. Turn Off independently of exploration reactions. |
| Day and night abilities | **Off** | Uses learned human and vampire abilities outside their usual time restrictions. It does not grant skills or remove their costs. |
| Passives without slots | **Off** | Activates learned passives without assigning slots. Time restrictions remain unless Day and night abilities is also On. |
| Spend skill points anywhere | **Off** | Removes the shrine requirement from the normal Skills page; costs and prerequisites remain. |
| Auto-loot nearby items | **Off** | Collects free loot, herbs and resources within 3.5 metres after combat ends. Locked, stealable and obstructed items are skipped. |
| Fast travel from anywhere | **Off** | Enables travel away from shrines to unlocked shrines, map icons and custom waypoints, outside combat and cutscenes. Press F once on an icon or waypoint. |
| First-person camera | **Off** | F4 toggles the existing first-person option. No camera change happens until you enable it or press the shortcut. |

**Nightmare is started manually, not enabled automatically.** It shares the Horde defaults: **8 starting enemies, 1 additional boss, +2 enemies per level, 10 levels and 10 seconds of rest**. Every slot becomes a boss in Nightmare, so the first round has **9 bosses fighting together**, followed by 11 in the second. Adjust these values before starting. The Starting wave selector only affects normal Horde runs, which retain their ten themes.

## Fixes and improvements

- Added safeguards for save reloads and opening F5 immediately after fast travel, including cleanup of old player and menu references.
- Missing, duplicate or invalid configuration entries are repaired before the menu opens, preventing the recurring missing-key errors.
- Map travel prompts appear sooner, and the native loading screen covers destination preparation.
- Corrected missed tower and climbing observations, including lines in the larger shared exploration graph. Unrelated background speech no longer discards Coen's observation.
- Improved mushroom and herb pickup detection when the visible interaction point sits above a rock or log, while retaining visibility, lock and theft checks.
- Reorganised the Horde panel with separate Start horde and Nightmare mode buttons, shared run status and End run.

## Installation

Close the game. Install **Complete** for one download, or extract **both Scripts and Runtime for 0.5.4** into the game installation folder, merging the included `Dawnwalker` folders. Neither split ZIP works on its own. The Runtime ZIP includes the helper, configuration files and `enabled.txt`, so Scripts alone will not enable the mod.

To keep your preferences, back up `config.ini` and `keybindings.ini` before extracting and restore them afterwards. New options use their defaults when missing from an older configuration. Keep your generated conversation data. Reapply the matching optional **Multilingual** pack after updating if you use it.

Requires **The Blood of Dawnwalker 1.05**, **UE4SS for Dawnwalker 1.2.1 RC6**, and **Dawnwalker Mod Menu 1.0.7 or later**. Use borderless or windowed mode for the conversation overlays. No Convai account, API key setup or command-line commands are needed.

The **Source** ZIP is for developers. The optional **Multilingual** ZIP contains a character-ID configuration file and an installation note.

[Player guide and settings](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker#readme) · [Full changelog](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/blob/main/CHANGELOG.md) · [YouTube channel](https://www.youtube.com/@AlystriaAI)
