Companions now keep a more natural walking pace during exploration, with closer positions for small parties. This release also fixes two startup and settings problems.

- **Walk together:** companions match walking and running pace instead of sprinting across short gaps. Haste still helps distant followers catch up, then eases as they reach their place. Travel speed changes stay on the summoned companion and release for combat and scripted actions.
- **Closer small parties:** one or two companions take side positions, with additional companions just behind. Groups of up to four start following sooner when Coen walks away. A short forward prediction compensates for path delay while moving and clears when he stops. Approaching a stationary companion keeps the larger movement tolerance. Keep Narrow formation off for the side-by-side layout.
- **Startup recovery:** a saved helper process ID can belong to an unrelated Windows process after a restart. The launcher now discards that stale record safely instead of refusing to start, which could leave F5 and chat shortcuts unresponsive.
- **Mod Settings:** corrected the missing On/Off values for Narrow formation, fixing the invalid choice definition error.

## Installation

Close the game. Install **Complete** for one download, or extract **both Scripts and Runtime for 0.5.3** into the game installation folder, merging the included `Dawnwalker` folders. Neither split ZIP works on its own. The Runtime ZIP includes the helper, configuration files and `enabled.txt`, so Scripts alone will not enable the mod.

To keep your preferences, back up `config.ini` and `keybindings.ini` before extracting and restore them afterwards. New options use their defaults when missing from an older configuration. Keep your generated conversation data. Reapply the matching optional **Multilingual** pack after updating if you use it.

Requires **The Blood of Dawnwalker 1.05**, **UE4SS for Dawnwalker 1.2.1 RC6**, and **Dawnwalker Mod Menu 1.0.7 or later**. Use borderless or windowed mode for the conversation overlays. No Convai account, API key setup or command-line commands are needed.

The **Source** ZIP is for developers. The optional **Multilingual** ZIP contains a character-ID configuration file and an installation note.

[Player guide and settings](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker#readme) · [Full changelog](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/blob/main/CHANGELOG.md) · [YouTube channel](https://www.youtube.com/@AlystriaAI)
