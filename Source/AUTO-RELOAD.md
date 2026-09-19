# Automatic Lua reload

Installed: launch Dawnwalker once to load the stable bootstrap, then keep it open for ordinary Lua edits. No Ctrl+R, watcher terminal or external service is required. The game's previous process was already closed during installation.

The bootstrap watches the workspace's `mod/Scripts` through the configured runtime path. It checks about once per second and reloads after two matching snapshots, normally within 1–2 seconds of the final save. A paused game may defer the game-thread handover until it resumes. `runtime/reload-status.txt` and the UE4SS console report success or failure.

Watched modules: `app.lua`, `config.lua`, `targeting.lua`, `engagement.lua`, `face_inspector.lua`, `jali_probe.lua`, `jali_preview.lua`, `face_graph.lua`, `companions.lua`, `companion_config.lua`, `companion_native.lua`, `companion_orders.lua`, `ui_input.lua`, `companion_combat.lua`. Edit **app.lua** for gameplay changes; **main.lua is the stable bootstrap**. Helpers load directly from the workspace; copying each edit into the game directory is unnecessary.

Before handover, the old version restores the active test's JALI state, audio volume and NPC movement/AI settings. Key bindings remain registered once. Application timers are routed through one stable timer, and queued callbacks check that their originating version is still active. Syntax/initialization failures keep the previous version active and report the error. This protects Lua state transitions; it cannot catch a native engine access violation.

The UE4SS-wide hot reload setting remains off; this mechanism reloads only this mod. The companion update extended the shared watch list in the already-running loader and migrated the old RC5 native-module cache; both were verified without a game restart. Changes to the stable bootstrap or UE4SS DLL/configuration still require restarting. An active native companion DLL is locked: use a versioned filename for a new native build and update the Lua wrapper, after dismissing owned companions.

Companion reloads cancel graphs, release any conversation/position holds and stop the mod-owned population spawners. Party membership deliberately resets instead of retaining stale engine object handles. Saved plan graphs remain in `runtime/companion-plans.json`.

The router has offline coverage for invalid-edit recovery, callback invalidation, debounce and restoring a held NPC. The v0.22 update exposed an invalid pointer left by a retired async spawn action. The recorded old spawner was stopped, the obsolete v2 pointer registry was retired, and v3 hot-reloaded successfully at 13:42:25 on 12 September. The native DLL now retains owned object paths and re-resolves them before each call, including cleanup after action expiry. The old DLL stays mapped but is never invoked again; no unsafe unload was attempted. See the implementation notes for the one-time cached-module migration. Ordinary Lua changes still reload without restarting the game; the next spawn/dismiss cycle needs a visual check.

Version 0.23 uses companion_native_v5.dll: asynchronous class requests and a separately rooted population spawner. The party is dismissed before a native-version handover; inactive older DLLs remain mapped. Lua and helper updates were installed without restarting Dawnwalker.
