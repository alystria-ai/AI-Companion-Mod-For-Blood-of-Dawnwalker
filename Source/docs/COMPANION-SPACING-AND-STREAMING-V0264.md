# v0.26.4: horizontal following and population recovery

## Evidence and limits

The live v0.26.3 session detached Xanthe, Lacra, Ambrus, Drogos, Bakr-Erga, Ocha, Crake and Sara together at approximately 13:52:05 on September 13. The player later reported sprinting over a hill out of their sight. That is consistent with distance/visibility culling, but the log does not prove which predicate removed the pawns. Logs and before-state files are archived in `runtime/session-v0264`.

The captured performance report repeatedly records reconnect work taking 1,016–1,116 ms. v6's poll resolved the expired async-action path, its class, the rooted spawner path and its class through `StaticFindObject_InternalSlow`. The configured UE4SS build lacks the object hash table, so unsuccessful lookups scan the complete object array. This is direct evidence of expensive mod work, independent of whether rocks or visibility triggered detachment.

## Native lifetime and polling

v7 records `FWeakObjectPtr` handles for the action and actual population spawner at creation. It uses the exact constructor and zero-argument Get exports available in the installed UE4SS DLL. Offline disassembly verifies the eight-byte index/serial layout; resolution validates the serial and pending-garbage state. Paths remain authorization keys and diagnostics, not recurring lookup instructions. After a spawner is captured, polling never tries to find the expired action again. No raw UObject pointer survives a tick.

The spawner retains the root lease used by previous releases. Stop resolves handles, invokes native Stop once, revalidates after callbacks, releases only the root added by the mod and clears the registry. A pre-existing root is not removed. Old v6 cleanup closures still use their own DLL/registry during this upgrade. v7 is a separate file so Windows never has to replace a loaded native library.

The read-only `weak-benchmark.c` audit resolved an existing spawner once, constructed a weak handle, then performed 64 handle-resolution/map-export samples in the paused game. Mean core operation time was **0.001139 ms**, with an empty map. This excludes the initial lookup, Lua/file protocol overhead, populated-map cost, ordinary game simulation and FPS; it is not an end-to-end frame-time benchmark. It directly verifies the handle ABI and cheap empty-map polling that replaces the failing path.

Direct Lua iteration of `SpawnedPawns` was rejected: this RC5 build reports `Operation::GetParam is not supported` for weak map values. The temporary probe failed in Lua and was restored; no production code uses that route.

## Native persistence settings

The object dump and read-only live enum checks expose `ESpawnPriority::AlwaysSpawned=0`, `Default=2`, `ESpawnRange::Always=1`, and the 50/150 metre population near/far settings. Two inspected generated tables held Default priority. `CommunityBaseActivator.Mode=4` means `PopulationArea` in `ECommunityEntryOperation`; it is not a force-visible switch.

Those controls are **not enabled by this release**. The generated table may already have been copied into internal population entries before Lua receives the spawner. There is no verified reflected setter for a per-stub visibility lease. Rewriting the row after registration would not prove protection; broad visibility volumes or changing global spawn ranges would affect campaign actors too. Rooting an owner does not prevent its population system from unloading a pawn. Further work must identify the registration boundary or a native per-entry setter and verify the resulting live entry before promising persistence.

## Movement and terrain

Stable summon ordinals assign compact five-column rows: lateral offsets 0, −360, +360, −720, +720 cm, and successive rows 360 cm farther back. Larger collision capsules increase row/column pitch. Dismissal compacts slots without changing instance identity or clone conversation sharing.

A guarded AIController.MoveToLocation pre-hook redirects only existing movement requests near Coen, from controllers mapped to live owned summons in native follow/travel mode. Destinations come from cached player travel heading and position, not camera rotation. The hook does no object scans, navigation projection or new MoveTo calls. Both combat flags, conversations, Stop, scenes, suspended behavior, unbreakable actions, stale goals, distant non-follow destinations and obsolete controller identities bypass it. Earlier archived logs confirm this game's follower calls reach that UFunction. The new release still needs visible movement validation.

There is no recurring idle reposition request. If a distant traveller makes less than one metre of actual progress over 3.5 seconds, lateral redirection yields for twelve seconds to the native direct route. Stopping distances fit the rows instead of expanding a single trailing chain. Narrow navigation and native collision avoidance can compress the rows; this is not a guarantee of rigid formations.

Off-camera catch-up and spawn-marker navigation failures use exponential delays of 4/8/16/30 seconds after failed attempts, retaining the existing whole-party staggering. A successful relocation clears failure history. Native combat, grounded checks, camera checks, collision checks and unseen-arrival rules still gate catch-up. The spawn marker's native teleport can decline; the code now backs off rather than repeatedly projecting its location.

## Verification and references

Offline C mocks exercise expired actions, collected/reused spawner handles, failed Stop ownership retention, owned/pre-existing roots, 250 polls with zero name searches, dynamic registry growth and slot reuse. Fengari tests exercise row spacing, larger capsules, compaction, blocked progress, retry limits and callback pass-through for combat and unrelated actors. Lua syntax parsing and the existing regression suite run separately. No computer inputs, new game launches or microphone tests are used.

Primary API references: [UE4SS UDataTable](https://docs.ue4ss.com/dev/lua-api/classes/udatatable.html), [RegisterHook](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html). Game-specific enum values, native ABI and behavior come from the local object dump, live read-only probes and recorded traces, not generic Unreal assumptions.
