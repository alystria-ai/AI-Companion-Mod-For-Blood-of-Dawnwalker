# v0.27.8 — spatial character responses

**Updated in v0.30.8:** the shared output now uses equal-power panning rather than HRTF. Left/right positioning, distance falloff and movement smoothing remain; the binaural filter is removed to preserve voice timbre. Live and buffered speech use matching 48 kHz playback contexts. The player confirmed improved clarity in game. The HRTF description below records the original implementation.

**Correction in Lua v0.27.9:** the original browser tests passed, but game position export failed because `GetCameraRotation()` returned `{pitch=..., Yaw=..., Roll=...}` rather than the all-uppercase field names used by the test. The protected call discarded this error and the renderer used centred fallback. The adapter now accepts the observed lowercase `pitch`, validates all nine numeric inputs without `ipairs` skipping nil fields, and logs changed failures to `spatial-status.txt`. A fixed read-only `spatialinfo` probe confirmed successful export and agreement with the running game's `GetRightVector`, `GetUpVector` and `GetForwardVector` projections. Regression coverage includes the exact mixed-case representation. Browser/helper versions need not change for this Lua repair.

Direct text/voice responses and prepared group replies now play through Web Audio HRTF panners. The speaking character is positioned relative to the active camera, including yaw, pitch and roll. Rotation changes apparent direction; distance changes volume. Pending group voices remain silent and use the newly selected speaker's live position at playback, not the position where the reply was generated.

## Game data and coordinates

`Targeting.spatial` converts Unreal centimetres (+X forward, +Y right, +Z up) into camera-relative Web Audio metres (+X right, +Y up, -Z forward). It uses the already-validated selected pawn/controller and the same camera location/rotation APIs used by targeting. The source is actor origin plus 60 cm: an approximate humanoid mouth location, not a newly discovered skeleton socket. Nonhuman shapes can need a different source offset.

The active conversation writes `runtime/spatial.txt` about ten times a second: timestamp, actor generation and three coordinates. There are no additional global scans, socket searches, traces, network calls or changes to native movement. Node reads at a bounded cadence; both protocol and browser reject stale, malformed, nonfinite, distant-out-of-bounds and wrong-generation samples. Coordinates remain local and are not included in Convai context.

## Audio routes

- `bridge/spatial-audio.ts`: direct remote WebRTC source → shared spatial output → speakers. A hidden muted/zero-volume element primes decoding, so the original stream cannot bypass the panner or double playback. Track removal/renderer disposal disconnect sources and remove consumers.
- `bridge/reply-audio.ts`: the existing silent PCM capture is unchanged; only its playback worklet is routed through a spatial output. Preparing the next voice does not make it audible.
- `bridge/spatial-output.ts`: common HRTF graph for both routes. Inverse distance model, reference distance 2 m, rolloff 0.65, maximum-distance parameter 60 m. A 45 ms smoothing constant removes abrupt position steps. Unchanged polls do not queue repeated automation.

The camera is the listener, which is appropriate to third-person viewing. Missing position data falls back to centred near-field playback so a delayed mailbox cannot erase a response. If spatial graph initialization is unavailable, direct speech falls back to ordinary SDK playback and exposes an audio diagnostic. The native game dialogue mixer is not involved: game dialogue volume sliders and game acoustic environments do not automatically apply to browser voices.

HRTF provides binaural direction cues, most clearly heard with stereo headphones. It is not environmental occlusion, reverb, obstruction or native game audio injection. For Web Audio behavior see [PannerNode](https://developer.mozilla.org/en-US/docs/Web/API/PannerNode); remote audio input uses [MediaStreamAudioSourceNode](https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamAudioSourceNode).

## Verification

171 offline tests passed, including camera-axis/scale/roll transforms, stale-generation rejection, smoothing, group sequencing and silent buffered capture. TypeScript checking passed. An isolated browser rendered the actual production HRTF graph: left-source channel RMS was 0.562/0.387, right was 0.387/0.563, centred near was 0.645/0.645, and 10 m distance was 0.179/0.179. These validate direction and attenuation, not subjective in-game positioning.

The real Convai group benchmark uses analyser taps on production panners to verify decoded audio reaches direct and prepared outputs. An extra silent panner after playback is allowed because the client restores a direct renderer for subsequent input; the check requires exactly three outputs carrying the three replies. Tests use isolated, muted Edge, fresh Convai identities and no microphone/game input.

Reproduce with `node scripts/verify-spatial-audio.mjs runtime/spatial-check`, or `node scripts/benchmark-group-client.mjs runtime/group-spatial-check --spatial` for live Convai. The latter requires configured Anca/Lacra/Pieter profiles and consumes ordinary requests. Results for this update are under `runtime/session-v0278/`.

The update changes watched Lua and the browser/server. Lua reload dismisses current companions; summon them again with F5. The game itself need not restart. Use F6/F8, rotate while a character speaks, and step sideways/back to check directional movement and distance while captions/lipsync continue normally. `group-reply-status.json` now includes `spatial.position` and `audioError` diagnostics.
