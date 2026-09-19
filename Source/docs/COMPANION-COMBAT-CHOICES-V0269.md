# v0.26.9 — independent targets and combat movement

The user confirmed v0.26.8 fixed Ambrus's T-pose and improved retreat for three of four companions. The next report was that companions appeared to fight better away from Coen, sometimes walked slowly toward enemies, and Brencis was left behind. The user explicitly requested that companions may fight any current enemy, rather than only Coen's selected enemy.

## Evidence and its limits

`runtime/session-v0269/` preserves the pre-update log, four histories, movement snapshots, native function disassembly and 30 read-only exports from the current party. All four sampled companions were in accepted native combat with follower locomotion disabled. Their opponent was generally a boar, not Coen. The records do not support blaming repeated follower MoveTo calls during these fights.

Xanthe remained in `RebelAI.CharacterState.Default` with `DA_NPC_Walker_MovementProfile` throughout the captured fight. That profile permits 140 cm/s. Her inspected definition points every Combat state to `DA_Xanthe_Combat_MovementProfile`; a paused asset lookup showed that profile was not loaded. After the new async loader requested it, a separate read confirmed priority 1 and maximum speed 425 cm/s, compared with the walker's priority 0 and 140 cm/s. The loading call returned in 0 ms according to the engine request timer; completion and lookup occurred later. This is not a whole-frame performance benchmark.

Brencis's profile changed from `DA_Combat_MovementProfile` to the authored `DA_Combat_Defense_MovementProfile` near Coen. After an AI detachment and reattachment, the capture again showed the ordinary combat profile. At the last pre-detachment snapshot he was about 35 metres from Coen while his recorded enemy was only seven metres from Coen. That proximity vetoed his individual retreat. The other three members recognized a sustained departure. His population owner remained registered; he eventually reattached and regrouped.

The `aggressive` field was false throughout the samples, and the game reports its aggression controller enabled. Those facts alone do not establish a faulty aggression algorithm or prove forcing aggression will improve combat. The native ForceAggression entry point also forces a target and modifies hostility; repeatedly applying it would conflict with the requested independent target choices. This update does not add an aggression loop. Shared attack-ticket capacities, cooldowns and deliberate defensive behavior remain native.

## Initial opponent selection

`companions.targetFor` first preserves an eligible native opponent and an already-assigned initial opponent. Otherwise it considers nearby active enemies, including enemies already fighting the player or another companion. Coen's aimed enemy is a candidate, not an overriding instruction.

`companion_combat.initialTarget` scores those candidates by distance from the companion, adds 650 cm for each other assigned companion, and subtracts small bonuses for an enemy attacking Coen (250 cm) or being aimed at (100 cm). This spreads initial assignments without sending somebody to a vastly farther threat just to distribute the party. Stable identity breaks exact ties. Idle bystanders are excluded unless they are already a valid hostile aimed target.

The score runs only when a new assignment is needed. Once native AI chooses an opponent, later changes to player aim do not replay combat entry or force a replacement. A still-engaged enemy can remain valid within 40 metres of the companion even when Coen crosses the initial targeting radius. Explicit retreat detection remains responsible for bringing that companion back. The 40-metre validation range is an opponent check, not a limit on how far a companion may follow Coen.

The active-combat target path now yields before changing pair attitudes when native AI already owns the selected opponent. Bootstrap hostility and forced-target leases are still used when needed to establish the first encounter between former allies. The mod clears its own temporary hint after native targeting takes over and preserves foreign/native hints.

## Travel-to-combat handoff

Previously `combatPose` could restore the pre-travel `Default` state during combat adoption, or during preparation before native entry. This is inappropriate when Default is a walking state. Native adoption now releases travel speed and Ambrus idle-selector leases and clears their bookkeeping without setting a character state or re-equipping. During explicit preparation, only an actual previously saved `RebelAI.CharacterState.Combat.*` state may be restored. Sword/claw initialization remains in the existing bounded preparation path.

Xanthe needs a further narrow repair because her weaponless combat path can leave the authored walking state in place. `ai_state.combatMovement` leases her own authored combat movement profile only when native combat is acknowledged, her state is None/Default/Running, and the current profile is exactly NPC_Walker or Follower_Walker. It does not overwrite a native combat state, defense profile, attack profile, scene or unbreakable action. A native profile change releases the lease. Retreat, travel, death, scene takeover, reattachment and dismissal also release it. A rejected priority has a retry cooldown; successful leases do not impose a cooldown after an action ends.

This restores the intended movement configuration rather than multiplying speed globally or forcing attack montages. Brencis's intentionally selected defense profile is left alone. The other characters' combat movement is not assigned Xanthe's profile.

## Asynchronous movement-asset preparation

`companion_native.requestAsset` dispatches through a separate `companion_assets_v1.dll`. The population-owner DLL remains the unchanged v8 binary. The new DLL accepts only `loadassetasync`, cannot dispatch spawn/stop/poll operations, and shares the existing validated reflected parameter-buffer implementation. It uses `MakeSoftObjectPath`, `Conv_SoftObjPathToSoftObjRef`, then the latent `LoadAsset` API. Soft references stay in engine-sized native buffers; Lua does not fabricate UE4SS soft-pointer wrappers or reflected arrays.

The input world context is a live player pawn, the completion delegate is unbound, linkage is INDEX_NONE, and the asset-loader UUID namespace differs from the class loader. The engine owns asynchronous loading. Lua polls the known asset path and waits for initialization, serialization and post-load flags to clear before using it. A data asset is not treated as a UClass and receives no GetCDO call.

Xanthe's summon preparation requests this small asset after her class dependencies, using the existing loading UI and timeout. Queued summons remain independent. If the soft asset is collected between summoning and combat, the repair can request it again asynchronously with bounded retries; it never switches to a blocking loader. No new pawn roots or population ownership are introduced.

Build the helper with `scripts/Build-CompanionNative.ps1 -AssetLoader`. Its versioned DLL name is separate from the population DLL, allowing this update to load in the already-running game. Later changes to a loaded helper must use a new versioned filename.

Epic's primary API documentation describes the [soft-path to soft-reference conversion](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/Kismet/UKismetSystemLibrary/Conv_SoftObjPathToSoftObjRef?application_version=5.5) and [Kismet loading APIs](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UKismetSystemLibrary). The exact reflected parameter sizes, movement profiles and character behavior above come from this game's dump and live inspection, not assumptions about stock Unreal AI.

## Coordinated departure

Two companions independently detecting a sustained run within five game seconds provide a party-departure signal. A fighting straggler uses that signal only when Coen is running at least 4 m/s, moving substantially away from that companion, and separated by more than max(18 metres, its following radius + 10 metres). This handles the recorded case where an old pursuer stays beside Coen and defeats the straggler's enemy-distance check.

This is a shared departure cue, not a combat state graph. A single far companion, short/local repositioning, ordinary following or unrelated distant combat does not supply it. Native exit and unbreakable-action protections remain. The signal expires, while an already-confirmed return persists until reunion so a late member is not abandoned midway back.

## Verification and next check

All 19 Lua files parse as Lua 5.3, and the full installed-source suite passes 139 tests. Focused behavioral tests cover initial threat distribution and actual adapter selection, native-opponent preservation past Coen's initial range, combat pose ownership, profile priority/lifetime/retries, readiness of asynchronously loaded data assets and shared departure guards. A summon integration test also verifies that Xanthe waits for her movement asset before native spawning while another queued character can finish. The asset helper compiled and its actual LoadAsset request succeeded while the game remained paused and responsive. The loaded profile's values were verified separately. There were no movement, combat or input commands during that check.

Deployment completed on 14 September 2026 at 00:14:57 local time. UE4SS confirmed v0.26.9 and successful hot reload, released all four previous companions, and continued publishing the paused empty-party state. The game remained responsive. All seven changed Lua files match between staging, workspace and the installed fallback. The population v8 DLL remains unchanged. The manifest, full test output and post-reload log are in `runtime/session-v0269/`; the development command file is empty and the original inspection entry point is restored.

The gameplay test remains necessary: summon fresh Xanthe, Brencis, Ambrus and Crake; fight several enemies while aiming at one; then run steadily away. Confirm that initial opponent choices spread out, Xanthe closes distance without her default walk restriction, and the last companion leaves with the group. Player proximity may still affect the game's authored defense and ticket decisions; these changes do not prove all perceived combat-quality issues are solved. Bakir's separate area-damage friendly-fire issue remains unresolved.
