Talk while exploring with a transparent HUD, or hide conversation text and keep just the microphone indicator. This update also adds controls for the first-person camera.

- Refined chat and voice UI with brass details, ivory text and a microphone ring that responds to your voice. Removed the voice heading, text-entry prompt and Send button; press Enter to send.
- **Hide chat boxes** leaves only the microphone indicator during voice input and hides the UI after text submission. Spoken replies continue. **NPC subtitles** can also be disabled separately while keeping the normal voice-input HUD.
- **Chat HUD bottom offset** moves text input, subtitles, voice indicators and Horde countdowns together. It defaults to zero, keeping the original position. Higher values move the HUD upward by a percentage of screen height.
- Adjust first-person **FOV from 60° to 120°**, camera height by **±20 cm**, and forward offset from **20 to 70 cm**. Changes apply live to the mod camera.
- Removed the first-person camera's fixed aspect ratio for 16:10 and ultrawide screens, and kept the camera and body mask through F5 menu transitions.
- Corrected small fonts on scaled displays and kept the HUD within the visible screen. Fixed offsets being ignored when sliders saved values such as `28.0`.
- Kept Connecting visible until the microphone is ready, so it can transition to Listening without another press. Reworked how the overlay appears to prevent an old window frame from flashing.

Find the HUD options under **F5 → Settings → Conversations**, and camera controls under **Camera**. Hide chat boxes takes priority over NPC subtitles; Horde countdowns remain available.

## Installation

Close the game. Install **Complete** for one download, or extract **both Scripts and Runtime for 0.5.1** into the game installation folder, merging the included `Dawnwalker` folders. Neither split ZIP works on its own. The Runtime ZIP includes the helper, configuration files and `enabled.txt`, so Scripts alone will not enable the mod.

To keep your preferences, back up `config.ini` and `keybindings.ini` before extracting and restore them afterwards. New options use their defaults when missing from an older configuration. Keep your generated conversation data. Reapply the matching optional **Multilingual** pack after updating if you use it.

Requires **The Blood of Dawnwalker 1.05**, **UE4SS for Dawnwalker 1.2.1 RC6**, and **Dawnwalker Mod Menu 1.0.7 or later**. Use borderless or windowed mode for the conversation overlays. No Convai account, API key setup or command-line commands are needed.

The **Source** ZIP is for developers. The optional **Multilingual** ZIP contains a character-ID configuration file and an installation note.

[Player guide and settings](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker#readme) · [Full changelog](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/blob/main/CHANGELOG.md) · [YouTube channel](https://www.youtube.com/@AlystriaAI)
