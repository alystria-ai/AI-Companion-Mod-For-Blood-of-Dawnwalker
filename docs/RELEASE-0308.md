# 0.30.8 Preview release notes

- Improves character voice clarity in both text and microphone conversations. Spatial playback uses equal-power panning instead of HRTF filtering, preserving left/right positioning and distance volume without the hollow or drummy coloration reported in the previous release.
- Uses consistent 48 kHz playback contexts for live speech and buffered group replies.
- Keeps the existing companion, menu, memory and conversation behavior. No combat tuning or voice profiles changed.

## Installation

The revised split packages contain Lua files only in **Scripts**, and all other files in **Runtime**, including configuration, JavaScript, PowerShell, data, executables, DLLs, documentation and licenses. File destinations and executable/script contents are preserved. Install both revised archives together, including when updating an existing 0.30.8 installation. The packaging change has been checked by archive integrity tests and per-file content comparisons; Nexus Mods acceptance has not been verified.

Use the Complete archive, or install both matching 0.30.8 Scripts and Runtime archives into the game installation folder. Close the game before replacing files. The shared-service setup remains included in the player runtime; players do not need npm commands or account setup. See the prebuilt installation guide for prerequisites and customization.

## Validation

All 282 regression tests pass. Browser audio checks verify directional panning, distance falloff, preservation of a centred multitone signal to better than 100 dB signal/error, and successful buffered playback. The player confirmed that the updated voices sound good in game. Binaural front/back and elevation filtering is intentionally absent; there is no wall occlusion or room echo simulation.

This remains a preview for game 1.05, UE4SS 1.2.1 RC6 and Dawnwalker Mod Menu 1.0.6.2 or later. Previous per-character gameplay and Vortex validation limitations still apply.
