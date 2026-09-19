# v0.30.6 — smoother queued loading

The runtime log recorded 1,025–1,201 ms attachment stalls for several different companions. Their recorded population factory/activation calls were below the timer resolution. The native menu was already updating existing widgets rather than rebuilding its layout on loading changes.

The native helpers had called UE4SS's `StaticFindObject_InternalSlow` directly, bypassing its public resolver. They now call the exported `UObjectGlobals::FindObject` overload, allowing the loader to choose its normal name-resolution path. All existing type, path, source-ASC and effect-handle checks remain. No raw object pointer cache was added. The population helper is version 9, the asset loader version 2, and the source-protection helper version 2; older loaded DLLs can finish their owned cleanup before hot reload adopts the replacements.

Every helper response now includes `lookupMs`, `lookupCalls` and `nativeMs`. The paused-game protection check completed with the new resolver: preparation took 219 ms, application 219 ms, removal 140 ms and release 94 ms. These operations validated the query and exact effect cleanup without crashing. These are helper-operation measurements, not full summon timings or a claim that every loading hitch has disappeared.

The party update also limits pending loading/attachment work to four steps or approximately four milliseconds per tick, checked between steps. It always admits one step to avoid starvation; one native call cannot be interrupted midway. Existing round-robin scheduling gives later queued characters their turn. Only one population activation can start per tick, while async asset loading remains concurrent and existing companions continue to update.

Quest and environment snapshots wait while the native menu is open unless an active conversation needs them. Their due timestamps remain intact, so updates resume when the menu closes. Native mouse/click processing continues before party/background work.

Validation: 282 automated tests pass; all 25 production Lua modules parse. The new helper passed live prepare/apply/non-stacking/remove/release checks. Fresh queued summons recorded attachment times of 91 ms for Lacra (previously 1,109 ms), 119 ms for Ambrus (previously 1,176 ms), and 94 ms for Crake. The user confirmed that browsing while queuing companions now feels fixed. These measurements cover attachment work rather than total asset streaming or rendered frame latency. Engine-side asset finalization can still cause a hitch, particularly for a character's first summon.

Build the three native helpers using `Build-CompanionNative.ps1`, `-AssetLoader` and `-Protection`, then use `Build-Prebuilt.ps1 -BundleSharedKey` for the distribution. All three replacement DLLs are in the package allowlist. Timing reports stay in the local runtime directory.
