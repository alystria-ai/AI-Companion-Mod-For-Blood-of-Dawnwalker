# Prepared group replies — v0.27.6

## Bottleneck and connections

The latest diagnostic showed a promoted connection ready in 67 ms, followed by 10,336 ms from request to first audio. Preconnection worked, but response generation still started too late. This is one observed sample, not a general service benchmark.

`companions.mjs` now records connection intent immediately when a summon request is queued. The target API exposes those intentions and live party identities. Failed or expired summons and party resets remove intentions; duplicate clones collapse to one character identity. `character-connections.ts` maintains the live SDK cache, starts requests at least 500 ms apart, permits at most two background setups concurrently, and backs off failed attempts for 30 seconds. Ready connections are retained for the actual party. The current/default conversation retains its existing idle behavior.

Client ownership transfers between cache and active conversation without recreating the SDK client. Active event listeners are removed before returning a client. Setup pauses during transfers to prevent duplicate creation during a temporary cache gap. Dismissal, game loss, disarming and save-timeline rollback retire unused connections. Late completion of cancelled HTTP setup is disconnected again. All connections use LiveKit with microphone/video off and MetaHuman 251 facial data at 60 fps.

## Reply preparation

The coordinator exposes stable remaining-speaker tokens. The authenticated group-context endpoint only supplies context for a remaining speaker in the current active room. Each preparation gets that character's own quest knowledge, observed environment, heard memories, the original player message and preceding finalized replies in order.

The browser starts the second request once the first has finalized its text and stopped thinking. It can start the third once the second finalizes, even before the first finishes speaking. Group selection remains limited to three distinct identities. Later replies therefore react to their predecessors rather than independently answering with no conversation context.

`prepared-reply.ts` captures captions, actions and timed facial frames without applying them to the game. Actions wait until local playback begins. Room/token/timeline changes, failed predecessors and cancellation dispose affected preparation. Unplayed generated replies are annotated as cancelled, and prompts distinguish the verified heard transcript from possibly unplayed session history. Confirmed heard memories still use completed-turn acknowledgements.

## Audio and lipsync

Muting and later unmuting a live track would lose audio already delivered. `reply-audio.ts` instead sends only the remote NPC track through a silent capture worklet. `public/reply-capture.js` contains separate capture and playback processors. Neither opens a microphone. Capture ignores leading silence while retaining the complete first audible block, and limits each prepared reply to 60 seconds. At most two future replies are buffered.

At handoff, 160 ms of available audio allows playback to start; completed shorter clips can also play. A half-second playback queue is replenished in bounded increments. The worklet counts samples actually consumed: underflow outputs silence without discarding future samples. Facial and caption selection follows that local playback clock. A capture-tail allowance retains the last decoded block.

The first speaker keeps live playback. Later handoffs wait for local buffered audio to drain as well as remote reply/facial completion. Early generation therefore cannot skip a speaker. Capture failure falls back to a fresh normal request, and failure of a predecessor invalidates dependent prepared content. The shared group-area fix from v0.27.5 stays in place.

Generation can still exceed available lead time, so zero delay is not guaranteed. Persistent connections consume normal provider connection resources, and a prepared request may be cancelled before it is heard. No character profiles, voices or models were changed.

## Verification and deployment

166 repository tests and TypeScript checking pass. The actual bundled-client test covers summon preparation, second and third requests starting during the first speaker, silent buffering, no request duplication at handoff, sequential audio, captions/facial output, private context, cancellation, deferred actions and clone reuse. Other tests cover connection transfer, late setup, duplicate/failed summons and exact PCM preservation across underflow.

`scripts/verify-buffered-audio.mjs` runs a separate muted headless Edge profile with a generated tone routed through a real MediaStream and both worklets. It uses no microphone, Convai calls or game browser profile. Its final run captured and replayed 1,877 ms with matching sample-derived durations. Real Convai stream timing and in-game lipsync remain a gameplay check.

Only bridge files change. Native helper v0.27.3 and Lua v0.27.5 stay installed. Deploy the bundle and restart the helper through the existing watchdog; companions remain loaded. Runtime diagnostics identify v0.27.6, cached connection counts and prepared/playback status. For buffered replies, handoff timing measures selection to local playback start; direct replies retain the earlier completion-to-audio metric.

## References

The implementation was checked against installed SDK 1.7.0 sources: ConvaiClient, EventEmitter, AudioRenderer and BlendshapeQueue. The [official Convai SDK documentation](https://docs.convai.com/api-docs/plugins-and-integrations/web-plugins/convai-web-sdk) describes custom audio and facial queue ownership. The buffering/cache implementation is local mod code; SDK package files are unchanged.
