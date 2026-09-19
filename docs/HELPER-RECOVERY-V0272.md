# v0.27.2 — helper recovery after silent microphone use

## Evidence

Windows recorded ConvaiHost process 2776 terminating with an access violation at 01:32:49–01:32:50 on 14 September 2026, followed by a callback exception report. The minidump has an execution fault at address zero. Its register arguments include the key-release message 0x101, and captured stack addresses pass through CLR and User32. The available small dump omits the relevant JIT memory, so it does not conclusively identify the managed callback or prove delegate collection. The keyboard callback lifecycle is a concrete suspect, not an established complete root cause.

The old host's Node process 3016 survived, with parent 2776 already gone. Subsequent helpers logged EADDRINUSE for local port 32123 and exited. This establishes why replacement subtitle/composer windows could not recover. A saved group diagnostic had already reached speaker 3/3 before the UI failure; this incident was not simply the earlier one-speaker ranking problem.

## Changes

- ComposerKeys uses one static, process-lifetime native callback delegate. Individual editor sessions can be disposed without freeing that thunk. A queued input delivery checks that its editor is still the current session and its control still exists. Exceptions from ordinary managed input handlers are logged without crossing the native hook boundary.
- Microsoft documents that [hook callbacks can still be executing after unhook returns](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unhookwindowshookex), and that [calling a collected managed delegate through a native pointer can cause access violations](https://learn.microsoft.com/en-us/dotnet/framework/debug-trace-profile/callbackoncollecteddelegate-mda). The permanent delegate removes this lifecycle hazard without retaining every closed editor.
- HostServerJob assigns the helper's Node child to a Windows job with KILL_ON_JOB_CLOSE. The host is the sole handle owner. Normal shutdown closes it, and Windows closes it when the host process dies. This keeps a failed helper from leaving its server port occupied. Startup rejects an unprotected child if assignment fails.
- Start-Background checks the exact configured executable and entry script before stopping an old local server. It handles orphaned servers during automatic recovery as well as explicit restart requests, preserves the running healthy host, and accepts an abandoned launcher mutex. It does not terminate unrelated Node applications or the game.
- WinForms UI exceptions are recorded in private runtime/helper-errors.log, input/voice leases are released, and the helper exits for the existing watchdog to restart. Native access violations are not treated as recoverable managed exceptions. Job cleanup and the external watchdog handle process death.
- Microphone.stop clears its active-device reference and on-state before awaiting disableAudio. A rejected disable cannot leave a stale device attached to the next text or voice conversation. An explicit new key press can retry. No timeout-generated text or empty group question is sent when the player says nothing.
- Closing input panels uses nonthrowing mailbox cleanup, and stderr logging cannot itself throw out of a process callback. Microphone status now names both F7 and F9 correctly.

## Verification

All 156 JavaScript/Lua regression tests pass, along with TypeScript checking and both client/WinForms builds. The actual browser-client test now starts a silent single-voice session, stops it without fabricating a message, then completes three sequential group text replies. Device-removal tests verify that failed microphone shutdown clears ownership and a new explicit request can recover.

A separate hidden native harness verified that closing the job ends its child process, and that the callback pointer survives 32 editor creation/disposal/garbage-collection cycles. Hook eligibility was always false; the harness generated no input and opened no microphone. The existing native composer check passed typing, selection, deletion, Enter and Escape without game input or foreground activation. These checks do not reproduce every WebView/driver failure or prove the original native crash can never recur.

## Player check

Keep the game open. Once the helper reports v0.27.2 ready, press F7 beside a companion, say nothing, and press F7 again to stop. Then use F6 or F8 to send a typed message and verify that the composer and subtitles still appear. No companion re-summoning is required for this helper-only update. If another exception appears, leave the game open; the new helper log and Windows dump provide the next evidence.
