# Group speech latency — v0.27.4

## Cause and approach

Previously the browser held one Convai client. After a reply completed, the server selected the next actor, Lua handed off facial/movement ownership, and only then did the browser disconnect the previous client and perform another Convai HTTP/LiveKit connection and bot-ready handshake. No preparation overlapped the previous speaker's audio. Reply completion also used a fixed 1,200 ms quiet fallback.

The group coordinator now exposes the remaining selected identities in its target view. It continues to choose at most three distinct character identities, preserve relationship/topic ordering, validate generation/token acknowledgements, and skip unavailable actors. This change does not broaden who hears private quest facts.

`bridge/warm-connection.ts` owns one silent upcoming client. `bridge/client.ts` resolves that character from the configured roster, shares the same session and memory timeline keys used for normal selection, and starts the SDK connection while the current speaker replies. Only connection setup runs early. No prompt, microphone capture, audio renderer, lipsync output, cloud-memory upload or action execution belongs to the prepared connection. Its error/disconnect handlers only retire it; they cannot interrupt the current speaker.

At handoff, `take()` transfers the prepared client to the existing active lifecycle. Its original connection promise is reused even if setup is still pending. The active browser handlers and AudioRenderer are installed, including explicit initialization when botReady arrived before promotion. The SDK AudioRenderer attaches already-subscribed tracks. Context is updated with the completed public conversation and the selected character's own verified knowledge before submitting the turn. The following speaker is then prepared. Future replies are not generated speculatively, so later speakers still react to what was actually said.

The installed SDK is `@convai/web-sdk` 1.7.0. Relevant local implementation references are `dist/core/ConvaiClient.js` (LiveKit connection and botReady), `dist/vanilla/AudioRenderer.js` (existing-track attachment and cleanup), and `dist/core/BlendshapeQueue.js` (`isConversationEnded`). Explicit LiveKit transport plus startWithAudioOn false avoids microphone initialization during preparation. No SDK package modifications were needed.

## Completion and cleanup

ReplyTracker uses a 250 ms tail guard only after new-turn audio was observed, final text/responding completion exists, the SDK reports its conversation playback ended, and both speaking state and pending face frames are clear. Resumed speech or new frames reset that guard. Without this explicit signal the existing 1,200 ms quiet rule remains. Final text without audio still allows six seconds for delayed TTS, and initial idle cannot complete an unsent reply.

Warm preparation is scoped to the group round and save timeline. Leaving the room, game loss, disarming, rollback, completion or selecting another upcoming identity closes unused preparation. A pending SDK HTTP connect cannot be aborted through the public disconnect method: cancelled preparations are therefore closed immediately and again after setup settles. Replacement warm requests wait for that cleanup rather than accumulating orphan connections. Failure or a 20-second not-ready timeout disables further warming for that round; the selected speaker can still connect normally. The usual steady-state budget is one active client plus one prepared client, rather than opening connections for an entire party.

## Diagnostics and limits

`runtime/group-reply-status.json` now includes build 0.27.4, warm state/age, whether the active connection was prepared, milliseconds from selection to ready, request-to-first-audio milliseconds, and handoff-to-next-audio milliseconds. The latter starts when the prior reply was acknowledged complete; it excludes that prior reply's tail guard. First-audio timing is based on SDK speaking/spoken-output events, not a hardware speaker measurement. Existing per-second diagnostic sampling remains bounded. No API credentials are included in these fields.

This removes connection setup from the audible gap when preparation finishes in time and shortens the guarded handoff when explicit completion is available. Lua handoff, network latency, Convai LLM generation and first TTS output still contribute. No measured live speedup is claimed. A server that rejects concurrent connections will fall back to sequential setup. Preparing a connection can consume normal provider connection/session resources, but sends no speculative conversation turns.

## Verification and installation

160 offline tests pass and TypeScript checking passes. The actual bundled browser-client test verifies preparation during the first reply, no premature message/microphone/renderer, promotion without extra connections, one request per speaker, correct prior-reply context, and clone session reuse. Dedicated preparation tests cover pending promotion, cancellation during HTTP setup, bounded replacement, rejected concurrent setup, timeout and ownership transfer. Reply tests cover the 250 ms end guard, queued frames, resumed playback, missing markers and delayed TTS.

Only the bridge bundle and group coordinator change. Helper v0.27.3 retains the F8 font fix, and Lua remains v0.27.1. The helper is restarted through the existing game-side watchdog; the game and summoned companions remain loaded. F8 group text is the short gameplay check; F9 uses the same pipeline after transcription. No real microphone capture was used in offline verification.
