# Group response cancellation — v0.27.5

## Observed failure

The September 14 UE4SS log shows Ambrus responding, then a group handoff at 02:23:20.289. Brencis's facial speech layer and conversation hold were successfully installed by 02:23:20.344. At 02:23:22.058 the Lua app logged `Conversation ended: walked away` and restored his face layer. The bridge subsequently recorded the round as cancelled/idle. This is a confirmed game-side cancellation, rather than evidence that the warmed Convai connection failed.

The automatic walk-away check used the current selected speaker's position, the player's camera direction, and the single-chat MaxDistance (450 cm). A later group member could be behind the camera and beyond that range even when the player had not moved. After the two-second debounce, Lua published inactive state; the browser then interrupted playback and cleared subtitles. A short next subtitle followed by disappearance is consistent with that sequence.

## Implementation

`mod/Scripts/app.lua` now routes the departure check through `conversationWalkedAway`. Single mode continues to call the original Targeting.walkedAway function, including its following exemption. In group mode, it captures a plain numeric copy of the player's position at the first check after selection. The radius is 1,200 cm, matching the coordinator's nearby-group candidate radius. Subsequent checks use player displacement from that fixed origin, without camera direction or selected-speaker position.

A quiet internal speaker handoff preserves this origin. Actual stop/closure, a new user conversation selection, unload/world change, or reload clears it. The next room captures a new origin. The existing two-second debounce still applies to leaving the area, and returning inside resets that debounce. Actor validity, world checks, the hard distance limit and stale-bridge release remain in effect. Group completion still releases the final speaker's movement hold once.

The v0.27.4 connection preparation, per-speaker context, audio rendering and lipsync queue handling remain unchanged. No model, voice, API credentials, profile or memory data was modified.

## Verification

The regression test executes the actual Lua departure function, stop logic and group handoff function. It starts beside the first actor, hands off to another actor behind the camera at roughly seven metres, and repeats stationary checks beyond the previous debounce window. The group stays active. It also verifies departure beyond twelve metres, stable origin across repeated handoffs, reset for a new conversation, and the original single-chat/follower behavior.

The complete staged Lua application parses successfully and all 161 offline tests pass, including browser group ordering and connection warming. This is not a live gameplay confirmation of all three spoken replies. The short user check is F5 to re-summon, then F8 beside several different companions while keeping the player in place.

Only the Lua application is deployed. The existing live loader releases and dismisses the old party when replacing the application; no game restart or helper restart is needed. The helper remains v0.27.3 and the browser bridge remains v0.27.4.
