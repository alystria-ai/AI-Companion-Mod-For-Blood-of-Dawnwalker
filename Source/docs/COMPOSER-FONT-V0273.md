# F8 composer font repair — v0.27.3

## Confirmed failure

The 01:53:15 local log recorded matching compose-group and ready messages from Lua. The host then threw System.ArgumentException at Font.ToLogFont / Font.ToHfont while creating the TextBox HWND. Subsequent errors tried to create the window again after helper shutdown had disposed it. Thus F8 registration and character selection had succeeded; native text-box creation failed.

A separate hidden reproduction loaded the real bundled Afacad font. At scale 16/15 (for example 2048x1152 relative to the 1920x1080 baseline), the requested 15-point scaled input font equals its initial 16-point font. WinForms ignores an equal Font assignment and keeps the existing instance. The old resizing code then unconditionally disposed that existing instance. Calling ToHfont reproduced the same ArgumentException as the user log.

## Repair

GameControlFonts.Replace detects value equality, disposes the unused replacement, and preserves the font retained by the control. For an actual change, it checks which object the control retained before disposing the replaced font. Both DialogueOverlay and CompanionPanel use this operation for their owned control fonts. The helper does not change the game-style typeface or the layout to work around the failure.

DialogueOverlay tracks shutdown explicitly. Pending composer/voice selection and send continuations stop when the form closes; they do not recreate its handle, write a false Composer ready status, or access disposed controls. The existing helper/server restart protection remains installed. Lua companion code is unchanged and no party reload is needed.

## Verification

The new --verify-fonts helper check uses the actual bundled Afacad font, verifies the equality case, forces real native textbox and button HWND creation, and draws through nine scales. It also checks native companion-panel control creation across six scales and confirms that calls after composer disposal cannot reopen it. The existing typing, selection, delete, Enter and Escape check passes as well. Checks run without foreground activation, generated game input or microphone capture.

The earlier --verify-input test created its runtime under a temporary directory, so its relative font path did not exist and it silently tested Georgia. The new check explicitly fails if the bundled font is missing. This closes that verification gap instead of treating the earlier result as proof that the real composer could open.

## Player check

Keep the game open and press F8 while facing a nearby character. It should show the group composer. Enter a short message and confirm the subtitle appears afterward. F6 uses the same repaired text controls. No companion re-summoning or game restart is needed.
