# Audio quality — local test after v0.30.7

**Confirmed:** the player reports that the voices sound good. The fix is included in the 0.30.8 release.

The installed browser audio bundle uses equal-power positioning instead of HRTF filtering. Left/right direction and distance volume remain; the binaural front/back and elevation filtering is removed. Both live and buffered group replies use the same 48 kHz playback context. No voice profiles or release archives were changed.

1. Launch the game, stand facing a companion and use F6. Check whether speech sounds clear instead of hollow or drummy.
2. Move around the speaking companion. Left/right position and distance volume should still work without changing the voice's timbre.
3. Use F8 with multiple companions and compare later replies with the first. F7/F9 use the same output path, so this change applies to microphone conversations too.

All 282 automated tests pass. An isolated browser rendering check verifies direction and distance, with a centred multitone signal preserved to better than 100 dB signal/error. Buffered capture/playback also drains successfully. These checks do not establish subjective in-game quality; the listening test is still needed.

---

# v0.30.6 — queued-loading responsiveness

The changes are hot-loaded; no restart is needed. Summon two or three companions through F5 and keep browsing/selecting while they load. Check whether the pause on arrival is shorter and queued clicks still register. Loading remains concurrent, but setup work is spread across party ticks. The native helper now records lookup time separately; see [performance notes](docs/UPDATE-0306-LOADING.md).

282 automated tests and the paused-game native protection check passed. Fresh summons measured 91–119 ms attachment work, down from approximately 1.1–1.2 seconds for the same two measured characters. The user confirmed that queued-loading menu responsiveness is fixed.

---

# v0.30.5 — source protection and completed combat (historical)

Lua is hot-loaded in the current session; no restart is needed. Hot reload released any previous party.

1. Summon Bakir, Lacra and optionally Brencis. Try a short fight: companion area effects should no longer damage Coen, while normal enemy hits should still do so.
2. End the fight and stand nearby. Check that companions stop repeating entry lines, leave their combat posture and resume following. A short step or looking at a companion should not start combat again.
3. If a companion is hit by friendly fire, it should not retain Coen or another companion as an attack target. Report the character and attack if it still happens.

Native filter construction, application, non-stacking and removal passed in the paused game. All 281 automated tests pass; 25 production Lua files parse. Actual power coverage is awaiting gameplay verification. See [implementation notes](docs/UPDATE-0305-PARTY-PROTECTION.md).

---

# v0.30.4 — menu, damage and travel recovery (historical)

Launch the game after this update. The experimental filter probe that crashed UE4SS was removed and is not part of normal startup. Lua edits still release the active party when hot reloaded.

1. Open F5. Browse, repeat Summon clicks and change sliders. Controls should stay stable; enabled Summon and Dismiss stay highlighted. Match player level and the recovery toggle are removed.
2. Compare a companion's ordinary hits at 100% and 500% against the same enemy type. The owned AI-versus-AI baseline now uses normal physical strength instead of the old helper damage of 10. Special powers may still use their own formulas. Check enemy attacks separately: no enemy stats/shared definitions are tuned.
3. Summon two or more companions and use the player's fast run across a hill. Once out of sight, existing companions should catch up without creating new copies or repeatedly loading assets.
4. Fast travel and check that the party returns near the destination. Dismiss a companion and travel again: the dismissed copy must not return.
5. Repeat with a queued summon and with a defeated companion; travel must not revive defeated companions while combat is still active. Revival is automatic once combat ends.

Known unresolved issue: Bakir's area attacks can still hit Coen. The earlier health refund was removed because it also masked enemy damage. No global invulnerability or experimental immunity filter is active. Do not use standing in Bakir's attack as the first damage comparison.

All 277 automated tests pass; all 24 Lua files parse. The native menu and previous stat readbacks were checked live. The new damage-route and fast-travel changes have automated coverage but still need gameplay validation.

---

# v0.30.3 — select, summon and queue

Reopen F5; the live Lua update does not require a game restart.

1. Click a character several times. Only its details should change; no companion should spawn.
2. Click Summon, then select another character and click Summon while the first is loading. Each click queues a distinct copy.
3. Check the loading bar, progress text and queueing hint beneath the right-hand controls. Esc/Back should remain clear.
4. Click Dismiss to remove the newest copy of the selected character; use Party for a specific copy.
5. The panel should close only after the full batch arrives and you stop browsing. Failed summons keep it open.

Native construction and repeated character-selection dispatch passed. Actual mouse hit testing and layout still need your visual check.

---

# v0.30.1 — menu and controls

The game and helper have reloaded the update; another game restart is not needed.

1. Press F5. Check the full-screen native background, readable text, gold selection and two-column layout.
2. Open Settings: drag a slider, or select its row and press Left/Right. Confirm the value saves.
3. Open Controls, select Single text chat and press an unused key. Escape cancels an unfinished assignment. The new shortcut should work once you close the menu.
4. Escape from Controls returns to Summon; another Escape closes. F5 closes directly unless you changed the menu binding.
5. Edit the installed mod's keybindings.ini with the menu closed. Keep all five entries and different keys. Changes should apply without a restart.

Actual game input and visuals still need this user check. Native construction, final font sizes, slider values and Escape command routing passed local runtime checks.

---

# v0.30.0 — native party UI and updated game

The game and new bootstrap have already been restarted for this update. Close the native pause menu and press F5. Check Characters and Creatures & combatants, queue two summons, and check that you can keep browsing while they load. The second category is combat-only and must never become the target of F6–F9. Check Party dismissal, Settings and Help, then Esc/F5 to close.

Current defaults: damage 250%, attack frequency 180%, health bars hidden, automatic revival after an eight-second peaceful delay. Test a familiar named companion and a wolf before trying a large creature. A fallen companion should return after the whole party leaves combat; new combat restarts the wait. Test Bakir's area attack separately: persistent faction friendship is applied, but area-effect protection is not yet confirmed.

A long F7 transcription should wrap through its last line. Positional audio still uses HRTF, with no added compression or pitch processing. Native UI construction succeeded for all pages in the running game; interaction, resolutions and new creature behavior remain gameplay checks.

[Implementation](docs/UPDATE-105-V0300.md) · [Prebuilt installation](docs/PREBUILT-INSTALL.md).

---

# Browser v0.28.3 / helper v0.27.5 / Lua v0.29.2 — portable voice input

Launch the game again after the crash. Press F7 once near a companion, wait for **Speak now**, speak and press F7 again to finish. Do not hold the key. The mod uses the Windows default microphone on each PC, with no device name or hardware ID configured. A green bar shows input level, and received transcription appears as **You: ...**. The preparation splash is removed. Try a second F7 turn too; F9 is the equivalent group key.

The fix prevents empty heartbeat reads from falsely cancelling capture and checks for a real published microphone track before reporting that it is listening. It also clears the selected actor before party cleanup to remove a stale name lookup matching the crash stack. OBS has not been established as the crash cause. Switching away still cancels capture; return and start another request.

27 focused offline checks, TypeScript, Lua parsing, the helper build and native keyboard/font checks passed. Voice/transcription previews were inspected. Actual microphone capture and gameplay remain for your test. If it fails, `runtime/microphone-status.json` now records the selected default device, input level, track state and whether transcription arrived, without raw audio or transcript text.

[Implementation and evidence](docs/VOICE-INPUT-V0283.md).

---

# Browser bridge v0.28.2 — researched profiles and shared player memory

No game restart or companion resummon is needed. The existing active API account remains configured. All 26 available profiles have enriched Core Descriptions, Convai Kokoro voices and enabled LTM. Pieter and Vladimir were not recreated. The bridge now passes one existing player end-user ID to every character and clone.

Try F6 with Anca and ask about Leonica, Lacra about Brencis and Isbrand, or Crake about his father. Those three questions already returned the researched information in fresh cloud test sessions without mod lore context. In your save, ask about a quest you actually completed; branch-specific facts should reflect your journal and only reach the relevant participant. F8 should still sequence the group normally. Microphone capture was not tested.

77 focused offline checks passed, covering profile routing, shared identity, sessions, group sequencing, listener memory and quest branches. TypeScript and the browser bundle build passed. The enriched policy has 54 grants across 27 quests and 17 researched named identities; unknown branches remain withheld. Cloud LTM can retain older-save facts even when local context resets.

[Detailed implementation and research](docs/CHARACTER-PROFILES-V0282.md) · [Pasteable profiles](characters/README.md) · [Quest coverage](characters/QUEST-KNOWLEDGE.md).

---

# UI helper v0.27.4 — microphone indicator

No game restart or companion resummon needed. With the game focused, press F7 near a character. The panel should show preparation, then **Speak now** and **Press F7 again when you’re finished**. Press again to close capture. F9 shows the corresponding group/F9 instructions; finalized group transcription can also close capture automatically. The voice panel appears without subtitles, and can share the overlay with a current subtitle. Microphone/selection failure should give visible feedback.

The Windows helper compiled; native input/font checks passed, and voice-only 720p/1080p, combined subtitle and error fixtures were rendered and inspected. Actual microphone capture remains for your test.

---

# v0.29.1 — sprint into battle with the party

No restart needed. Resummon with F5, sprint a stretch and enter a nearby fight. Companions behind the camera should recover sooner; those who arrive should join combat even while you circle the enemy. Streamed companions should resume their rear seat instead of parking where they reappeared. Existing fighters should leave a distant older encounter cleanly before catching up. No teleport is allowed during active combat or an unbreakable action.

195 offline checks and changed Lua syntax passed; the gameplay sequence remains for your test.

---

# v0.29.0 — replacement formation controller

No restart needed. Resummon your party with F5. Walk across open ground, run for a short stretch, then stop. Check whether they now reach separate rear-arc positions, instead of accepting movement and remaining in a cluster. Spawned companions keep their front positions until you depart. With ten standard bodies, the first arc is about 2.5 metres away and the next about 4.5 metres; closer gaps would crowd their bodies.

If movement works, approach one for a short chat and walk away again. Combat and chat should take control cleanly. The old formation MoveTo/separation controller is replaced. The native binding succeeded in a paused probe and 189 offline checks passed; live walking remains for your test. [Design and evidence](docs/FORMATION-REWRITE-V0290.md).

---

# v0.28.7 — nine-companion spacing and trailing distance

No restart needed. Resummon your party with F5 after the reload, walk/run across open ground, then stop for a few seconds. Check whether the companions spread behind you and catch up more closely instead of remaining in a distant cluster. Standard bodies use a first arc around 2.5 metres and a second around 4.5 metres; nine companions need both arcs to preserve body spacing. A temporarily blocked member now retries quietly without requiring you to approach it.

184 offline checks and changed Lua syntax passed. Native navigation was checked read-only in the paused game; movement appearance remains for your test.

---

# v0.28.6 — keep movement and separation from overriding the arc

No restart needed. After reload, summon three or four companions with F5. Walk about ten metres across open ground, then stop and give them a few seconds to settle into the rear semicircle. Approach one for a short F6 conversation, then walk away and check that following resumes. Larger parties use additional arcs; narrow terrain can still constrain paths. New formation diagnostics record actual and intended positions if the visible arrangement is still wrong.

181 offline tests and Lua syntax passed. Native gameplay behavior remains to be checked.

---

# v0.28.5 — follow in a rear semicircle

No restart needed. Summon again with F5 after reload. Walk across open ground, turn, then stop: companions should spread into the same kind of semicircle used at spawn, but behind you. Larger parties fill additional arcs. Check spacing while following and after settling; narrow terrain can temporarily force narrower paths.

---

# v0.28.4 — more space between companions

No restart needed. Summon your party again after reload, walk forward and turn, then stop. The nearest companions should remain close to you, with wider gaps between companions. Check the eight-character group for crowding while walking and after settling. Approaching one to chat should still leave that character in place. Crowding corrections are bounded; navigation can still require narrower paths on cramped terrain.

179 offline checks and Lua syntax passed. [Current spacing and correction policy](docs/COMPANION-SPACING-V0283.md).

---

# v0.28.3 — closer spawning and following

No restart needed. After the reload, summon two or three companions with F5: they should appear in a closer front arc. Run a short distance and stop; they should settle closer beside/behind you. Approach one to chat and check that the rest stay put. If trying a larger party, check for overlap and excessive rearranging. Larger bodies still require wider spacing. [Changes and validation](docs/COMPANION-SPACING-V0283.md).

---

# v0.28.2 — following after conversation

No restart needed. Summon Anca again with F5 after the reload; send an F6 message, wait for her reply, then walk away. Her native turning is unchanged. The movement override now uses the native reset function, because the ordinary setter clamps its disabled value to zero. Repeat a second chat and walk away again. The old summon is dismissed by reload, so its already-latched zero override cannot affect this check.

---

# v0.28.1 — release movement after speech; native turning

No game restart needed. Summon Anca again with F5 after the Lua reload. Send a short F6 message; once she finishes, walk away and check that she follows instead of running in place. Then stop nearby and walk around her: attention now uses native look/turn modes, with walking physics enabled so turn animations can place her feet. Check whether her head/body and feet actually turn naturally; the available animation varies by character. Repeat F6 once, and check F8 still advances all group replies.

178 offline tests passed, including actual browser completion/drain checks, actual Lua frame/hold integration, and attention ownership cleanup. TypeScript, full Lua syntax and browser build passed. Native turning appearance remains for gameplay validation. [Implementation](docs/CONVERSATION-MOVEMENT-V0281.md).

---

# v0.28.0 — reopen chat and nearest companion selection

No restart needed. The Lua reload dismisses summons; summon again with F5. Send a message with F6, wait for the response, turn away, then press F6 again: the composer should reopen. F6–F9 prefer a visible character you face, otherwise the nearest spawned companion, without the old selection distance cap. With two companions behind you, the nearer one should be chosen, even if the previous chat was with the other one. Combat/cinematic action ownership still applies.

Validation: 175 offline tests passed, including executing the real Lua selection and UI command functions for repeated single/group text/voice commands, camera rotation, distance, visibility, world validity and failed selection preservation. Full Lua syntax passed. Gameplay confirmation remains with the user.

---

# v0.27.9 — live spatial-position fix

The game camera returns lowercase pitch. The previous build silently failed to export positions and used centred playback. This is fixed and verified against the running game's own direction vectors.

The Lua reload dismissed summons: use F5 to summon again, then F6/F8 and rotate while they speak. No game restart required. Spatial failures now appear in runtime/spatial-status.txt rather than disappearing silently.

---

# v0.27.8 — spatial voices

No game restart is needed. This Lua update dismisses existing summons: summon them again with F5. Send a message with F6 or F8, then rotate the camera and move sideways/back while a character speaks. Their voice should follow their direction and get quieter with distance, while subtitles/lipsync continue. Stereo headphones give the clearest directional cues.

Direct and prepared group speech use the same spatial output. No wall occlusion or room echoes yet. [Details and checks](docs/SPATIAL-AUDIO-V0278.md).

---

# v0.27.7 — tested audio-buffer repair

Keep the game and your companions loaded. The helper reloads automatically; no game restart is needed.

Use **F6** to send a single message, then **F8** beside two or three distinct companions for a group question. The first reply still needs generation; the two real short-prompt tests measured 2.59 and 3.12 seconds. Later replies were ready at handoff (40–41 ms in the browser test). Check normal audio, subtitles and lipsync for each speaker, without overlapping voices.

Three alternative LLMs were tested and the existing model retained. Details and measured limits: [v0.27.7 report](docs/CONVAI-LATENCY-V0277.md). If a first reply remains much slower, timing information is now recorded for single chat too, so the next diagnosis can separate connection, text and speech delay.

---

# v0.27.6 — prepared group speech

Keep the game and your companions loaded. After the helper update, use **F8** beside two or three different companions. Check that later replies begin sooner, play from their beginning, and keep subtitles and lipsync aligned without overlapping voices.

New **F5** summons now initialize their connections in the background. Copies share the same connection. F9 uses the same preparation pipeline after transcription; no microphone was opened by the automated checks.

[Implementation and verification](docs/GROUP-PIPELINE-V0276.md)

---

# v0.27.5 — group replies stay active

The Lua update hot-reloads without restarting the game, but dismisses the previous summoned party.

1. Use **F5** to summon two or three different companions again.
2. Press **F8**, send a short group question, and keep standing where you started. You can keep looking at the first character while the others reply.
3. Confirm the second and third speakers finish with audio, subtitles and lipsync. Walking more than twelve metres from the starting point for two seconds should end the conversation normally.

The faster connection preparation remains enabled. [Cause, fix and checks](docs/GROUP-AREA-V0275.md)

---

# v0.27.4 — group handoff check

Keep the game and current companions loaded. The helper restarts automatically for this bridge update.

1. Stand beside two or three different companions and send a short group question with **F8**.
2. Listen for the pause before the second and third speakers. Confirm that subtitles/lipsync follow the correct speaker and the final words are not cut off.

F9 uses the same optimization after voice transcription. Network/Convai response generation still takes time; the change overlaps connection setup with the preceding speaker. Timing diagnostics are captured automatically if another adjustment is needed.

[Implementation and checks](docs/GROUP-LATENCY-V0274.md)

---

# v0.27.3 — F8 composer check

The helper-only font repair is installed. Keep the game and your current party open.

1. Face a nearby companion and press **F8**. The group text box should open.
2. Enter a short message and confirm that the reply subtitles appear.

F6 uses the same repaired textbox. No game restart or companion re-summoning is needed. The real-font/native-window check passed; please report if the in-game composer still fails.

[Exact cause and verification](docs/COMPOSER-FONT-V0273.md)

---

# v0.27.2 — helper recovery check

The repaired helper is installed. Keep the game open; your party was not dismissed by this update.

1. Beside a companion, press **F7**, stay silent briefly, then press **F7** again to stop capture.
2. Press **F6** and send a text message. Confirm the composer and reply subtitle appear.
3. Press **F8** and send a group message with different nearby characters. Confirm the composer stays usable after the replies.

If another exception appears, leave the game open. Private helper logs and Windows dumps can be checked without restarting it. No live microphone capture was used by automated verification; voice/device tests used mocks.

Details: [helper crash evidence and repairs](docs/HELPER-RECOVERY-V0272.md).

---

# v0.27.1 — group conversation and companion spacing

The Lua and Convai helper can reload while the game stays open. The previous party is released on reload; unpause and summon fresh companions with F5.

1. Summon three **different** characters, including Brencis if convenient. They should arrive in a close arc in front of you, facing you. Copies of one character intentionally share a Convai identity and do not count as separate group speakers.
2. Press **F8**, send a group message and let all three replies finish. The addressed character should speak first, then the other two in sequence, with audio, subtitles and lipsync. **F9** remains group voice. After the last reply, walk away and check that the speaker resumes following without running in place.
3. Walk, stop, turn the camera, then approach one companion. They should settle closer beside/behind you, and your short approach should not make the entire group reposition.
4. For the larger-party check, summon up to twenty if you want to use that many. Observe an open area and a narrow path: companions should share the available space, yield to held companions and avoid repeatedly pushing toward one occupied point. The narrower fallback and per-party path budget are coded and tested offline; native navigation and frame-time behavior need this visual check.

If group chat stops after one reply again, leave the game open and tell me; the bridge now records the speaker list/stage and the SDK completion/queue flags. If someone runs in place, pause with Esc while it happens and name the companion. No restart is needed to capture either issue.

Details: [implementation and evidence](docs/COMPANION-GROUP-AND-SPACING-V0271.md).
