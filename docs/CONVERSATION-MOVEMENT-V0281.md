# Conversation movement and native attention — v0.28.1

## v0.28.2 correction: clear the native input override

Gameplay confirmed that native turning works, but Anca still could not follow. The new inspection showed follower mode enabled, AI unsuspended, walking physics enabled, and input override still zero after reply completion.

Read-only disassembly of the installed executable explains why: `GetOverrideInputSize` reads the stored float; `SetOverrideInputSize` clamps its argument; `ResetOverrideInputSize` writes `0xbf800000` (float -1). Restoring the disabled sentinel through `SetOverrideInputSize(-1)` therefore writes zero, leaving locomotion blocked. Cleanup now uses `ResetOverrideInputSize()` when the captured value is negative, and the setter for an existing nonnegative override. A value subsequently changed by native AI is preserved. Native look/turn controls are unchanged.

The test double now models the setter's clamping instead of accepting arbitrary values. Regression coverage checks restoring the disabled sentinel, preserving an existing positive override, not overwriting another action's value, reply completion, reopening chat, and unload cleanup. Read-only evidence is retained locally in `runtime/session-v0282/input-native.txt`.

The live Anca inspection showed `suspended=true`, `movementMode=0`, `moving=true`, and zero velocity after a completed single reply. The browser reported final text, completed audio, no thinking/speaking and an empty face queue. Single chat never ran the reply completion gate used by group chat, so it left its conversation hold active.

Single replies now use `ReplyTracker.complete`: final response evidence, no thinking or speech, and drained animation/audio queues are required. The existing delayed-TTS and quiet-tail guards still apply. The browser repeats a bounded completion token in its frames. `encodeFrame` puts `REPLY-END` in the same timestamped, generation-stamped file as facial weights. Lua checks freshness and generation before releasing movement exactly once per token. Selection, facial binding and the warm connection remain available. A newer composer, group turn, or explicitly following world NPC is not released by this path. Companion follow restoration keeps its existing one-time path reset.

The previous facing implementation repeatedly called `K2_SetActorRotation`, rotating the capsule without asking animation to turn the feet. That call has been removed from conversation facing. The installed object dump exposes `RebelCharacterMovement.PushLookAtMode/PopLookAtMode`, `PushRotationMode/PopRotationMode`, `GetOverrideInputSize/SetOverrideInputSize`, and these enum values:

| Enum | Value | Use |
| --- | --- | --- |
| ERebelLookAtMode.KeepInFOV | 4 | Let the native look/turn system keep the player in view. |
| ERebelRotationMode.FaceDirection | 2 | Supply direction through native locomotion. |
| ERebelRotationSyncMode.AnimDriven | 0 | Existing native capability; its setting is preserved. |

Attention leases controller focus plus look/rotation modes at priority 50. Each push is paired with its returned handle; cleanup pops only those handles and restores the previous focus only if our focus still owns the controller. Direct controller/capsule yaw rotation flags are temporarily disabled so they cannot compete with native turning. Errors release partial leases and retry at most every five seconds.

The active conversation still suspends the native travel goal and stops its actions once. It now sets the native movement input override to zero instead of disabling walking physics. This allows native turn/stop root motion to place the feet. Cleanup restores the captured input override only while the mod still owns its value. After a reply, nearby stationary characters can retain attention without suspending AI or blocking movement; attention yields when they move, enter combat/cinematics, or exceed 4.5 metres. There is no scripted capsule-spin fallback.

The mechanism is supported by reflected APIs; the quality and availability of each character's turn animations still need in-game confirmation. Diagnostics now include movement input override, look/rotation mode and the animation instance's turn-in-place flag.

References: installed UE4SS object dump, existing RebelLocomotion adapters, [Epic's controller focus documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/AIModule/AAIController/K2_SetFocus?application_version=5.5), and [UE4SS enum API documentation](https://docs.ue4ss.com/lua-api/classes/uenum.html). Epic documents focus targeting; the game-specific locomotion modes come from the local dump, not a general Unreal guarantee.
