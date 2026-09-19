# v0.27.7: measured Convai latency and remote audio repair

## What failed

The previous silent response buffer was tested with a local synthetic MediaStream. Real Convai WebRTC behaved differently in Chromium: the SDK delivered text and speech events, but Web Audio captured zero PCM until a media element consumed the remote track. The baseline real test reproduced this: speech began at 2,619 ms, but captured audio remained empty. Depending on completion signals, preparation could fail after the 25-second startup timeout or appear finished without audible playback. The live v0.27.6 diagnostic also recorded a 25,438 ms handoff. That observation is consistent with this failure; it does not prove every reported delay had the same cause.

`ReplyAudio` now attaches a hidden, muted, zero-volume audio element to the remote track before capturing PCM. Capture output remains silent; only the local playback worklet becomes audible at the character's turn. LiveKit's `Room.startAudio()` explicitly unmutes attached elements, so preparation calls it before attaching its consumer and also sets the consumer's volume to zero. A later handoff cannot expose the original live stream or double its buffered playback. Capture detaches and removes the element on completion or cancellation.

`PreparedReply` now reports completed speech with empty capture as an error after its short decoder-tail guard, instead of declaring a silent turn successful. A preparation failure remains visible in diagnostics. Startup timeouts still cover a server that never delivers speech; this change does not shorten valid remote generation by discarding it.

## Real tests on 14 September 2026

The tests use isolated headless Edge profiles, real Convai character IDs, fresh end-user identities and real MetaHuman lipsync/audio streams. Browser output is muted, no microphone is requested, and the tests do not write game commands or use the player's saved conversation sessions. They consume ordinary Convai requests. The group test runs the actual browser client and group coordinator; only Lua's actor handoff and world context are simulated. Therefore these measurements exclude game-side selection/UI delay and are not a guarantee for every prompt, network condition or history length.

Two complete three-character runs with the existing model:

| Run | First speaker: Anca | Lacra after handoff | Pieter after handoff |
| --- | ---: | ---: | ---: |
| 1 | 2,590 ms | 40 ms | 41 ms |
| 2 | 3,120 ms | 40 ms | 40 ms |

All six replies supplied audio and subtitles and completed without preparation errors. Later replies were already generating during preceding speech. Handoff times are sampled by the actual browser bridge at approximately 20 ms intervals and exclude Lua's in-game handoff acknowledgement. The first reply must still be generated from the player's new message; an open connection cannot precompute an unknown question. These prompts requested one short sentence per speaker.

The production capture path separately produced real PCM at 2,218 ms and retained 4,651 ms of speech. The original synthetic test now also checks the muted consumer and drains all captured PCM; it remains supplementary to real remote testing.

## Model comparison

Convai's live `getSupportedModel` catalogue was queried, rather than assuming a documentation example named an available model. Anca's `model_group_name` was temporarily changed through the Core API, read back before each pair of trials, and restored afterward. Voices, biographies and other character settings were preserved.

| Model | Request to SDK speech, two isolated trials |
| --- | --- |
| `fast-gemma-4-26b-a4b-it` | 2,054 / 3,117 ms |
| `gemini-3.5-flash-lite-minimal` | 3,633 / 3,594 ms |
| `gpt-5.6-luna-none` | 3,884 / 2,985 ms |

The existing `fast-gemma-4-31b-it` produced speech at 2,128 ms in the fixed capture check and 2,491 / 2,637 ms in attachment experiments. These are small sequential samples, not a statistically controlled ranking. None of the alternatives demonstrated a consistent improvement sufficient to justify replacing the current model, so it is retained. Anca's current ElevenLabs voice was preserved. TTS/NeuroSync and transport account for part of the delay after initial text, so LLM token latency alone is not a speech-latency result.

Model APIs: [Convai Core AI settings](https://docs.convai.com/api-docs/api-reference/core-api-reference/character-crafting-apis/core-ai-settings-api). Pipeline timing definitions: [Convai live metrics](https://docs.convai.com/api-docs/api-reference/core-api-reference/live-apis-beta/metrics). The SDK metrics event did not supply server metrics in these tests; the reported numbers are measured browser events/PCM.

## Diagnostics and reproduction

- `scripts/benchmark-convai.mjs OUTPUT_DIR [prepared|attached|primed] [profileKey]` tests one real response. `prepared` exercises the production capture path; the other modes are diagnostic experiments. A missing PCM result or unsuccessful completion fails the process.
- `scripts/benchmark-group-client.mjs OUTPUT_DIR` runs Anca, Lacra and Pieter through the real three-turn client pipeline, using configured profiles and isolated sessions.
- `scripts/compare-convai-models.mjs MODEL...` temporarily modifies Anca's model, verifies it, runs two trials per model and restores the saved original in `finally`. The current research catalogue/snapshot lives under `runtime/session-v0277`; this script is a developer experiment, not an automatic startup task.
- Detailed results: `runtime/session-v0277/{baseline,fixed-capture,group-real-1,group-real-2}/result.json` and `model-comparison.json`. Runtime files stay private and are excluded from distribution.
- `runtime/group-reply-status.json` now includes both single and group conversations (the filename is retained for compatibility). `connection.readyMs` measures selection-to-ready, `requestToTextMs` measures first text, and `requestToAudioMs` measures the SDK's speech signal. Prepared `capturedMs` and `handoffToAudioMs` distinguish buffered playback. `lastPreparationFailure` survives subsequent frames. These are metadata, not API secrets.

Verbose SDK RTVI message logging is disabled to avoid retaining every streaming event in the browser console. Failure and timing diagnostics remain enabled.

168 offline tests and TypeScript checking pass, including regressions for muted attachment, LiveKit unmuting at handoff, missing PCM and group sequencing. The bridge bundle/server are updated; Lua v0.27.5 and UI helper v0.27.3 remain unchanged. The helper reloads without restarting the game or dismissing companions. After installation, use F6 for a single message or F8 beside several distinct companions. Actual game audio/subtitle/lipsync presentation remains the user's final visual check.
