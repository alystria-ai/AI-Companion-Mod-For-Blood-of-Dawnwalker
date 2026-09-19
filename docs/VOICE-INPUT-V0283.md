# Portable microphone input and conversation cleanup

14 September 2026. Browser bridge v0.28.3, Windows helper v0.27.5, Lua application v0.29.2.

## Using voice chat

Launch the game again after the reported crash. With a companion available and the game focused, press F7 once, wait for **Speak now**, speak, then press F7 again to finish. F9 uses group voice chat. These are toggle keys; do not hold them down.

The mod uses the microphone selected by Windows as its default input. It does not choose a device by name, store a hardware ID, change Windows settings or require a particular headset. On another PC, the same code uses that PC's default input. If several inputs are available, Windows' default needs to be the one you are speaking into.

The green bar shows the level of the actual audio track sent to Convai. A steady dot means capture is open. Received transcription appears as **You: ...**, while the heading keeps the key to finish visible. After six seconds without a detected signal, the panel suggests checking the Windows default microphone. The bar measures input; it does not by itself prove that the remote service transcribed it.

The preparation splash has been removed. Existing connection prewarming remains enabled, but microphone capture starts only for an explicit F7/F9 request. The indicator says **Speak now** only after the SDK has a live, enabled, unmuted published track. Hardware opening and permission prompts can still take time. Switching away from the game closes capture; return to the game and press F7/F9 again for a new request.

## What changed and why

The native helper writes a focus heartbeat every 100 ms. A truncate-and-write operation can briefly expose an empty file to the Node reader. Previously, converting that empty string to a number produced zero and could falsely cancel capture as if the user had switched away. The game heartbeat had the same reader issue. `bridge/heartbeat.mjs` now retains the last valid sample on empty/invalid reads, while explicit zero and expired timestamps still close capture. The focus writer now uses milliseconds, with older second-based samples still supported. This defect is confirmed in code; the old logs cannot establish whether it caused this particular failed recording.

`bridge/voice-input.ts` wraps the SDK's audio controls without specifying an input device. It checks the actual microphone publication after opening, enables STT, and removes a stopped publication when closing. Convai 1.7.0 mutes through LiveKit and then stops the underlying track; LiveKit can restart it, but explicitly unpublishing avoids retaining an ended capture between turns. Controls have stable identity per Convai client so the capture lifecycle does not reopen hardware every frame.

An optional Web Audio analyser reads the already-published microphone track. It requests no second capture and connects to no audio output. The browser forwards its level and the SDK's transcription event to the native overlay. `runtime/microphone-status.json` records bounded diagnostic metadata: current device label, signal level, track state, requested/on state, status and whether transcription arrived. It stores neither raw audio nor transcript text. The normal overlay can contain transient transcription, and existing conversation history can contain dialogue as before. Focus/selection cancellation reasons go to the bridge log.

## Crash investigation

The 14:02 crash stack enters UE4SS `UObject::GetFullName` and `FName::ToString`, then reads address 0x18 in game code. Immediately before it, the log shows the party being dismissed for a reload/world change. The application could publish the selected actor's live name after that cleanup had destroyed the actor.

The Lua application now caches names when selecting a valid actor and publishes those strings without dereferencing the actor. Party cleanup first clears the conversation's selected actor, face/controller references and input lease. The invalid-player/target path drops stale references without attempting to restore animation on an unloading object. This removes a matching stale-object path; it does not establish that every possible crash has been eliminated. OBS or Alt-Tab has not been established as the cause of this crash.

## Verification and remaining test

27 focused offline checks passed, including partial heartbeat reads, repeated microphone turns, missing/dead publications, microphone failure/cancellation, group handoff, client lifecycle and execution of Lua cleanup with objects that reject access. TypeScript checking, Lua parsing and the Windows helper build passed. Native keyboard and bundled-font checks passed. Voice-only previews at 720p/1080p and a combined subtitle/transcription preview were rendered and inspected.

No hardware microphone capture or live gameplay was exercised for this fix. For the next test, a single F7 turn is enough: check the green bar, transcription and response, then try a second turn. If it fails, the new diagnostic distinguishes a silent input from a live signal that never received transcription. The crash cleanup requires observation across the next normal world transition.
