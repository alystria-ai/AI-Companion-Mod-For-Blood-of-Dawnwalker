# Crash containment — 2026-09-09

**Update: v0.7 is now enabled in probe-only mode at the user's request to continue. See TEST-NEXT.md. The containment below describes the state before this bounded JALI probe was installed. Hot reload remains disabled.**

The Convai mod is disabled in both installed mod lists. Its `enabled.txt` marker was moved into the crash evidence backup. UE4SS hot reload is disabled. The loader and its original helper mods remain installed. The game process was already closed; no computer-use actions were taken.

The UE4SS log records v0.5 loading successfully at 00:42:54, followed by selection of Anca for inspection at 00:43:10. No successful inspection completion was logged. CrashContext reports `EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000000`, with VCRUNTIME140 followed by many UE4SS frames. This places the failure in native code reached during inspection. The exact getter/property is not identified: there are no matching native symbols or per-operation checkpoints in the available report. Hot reload happened earlier; these logs do not establish it as the direct cause.

v0.5 attempted generic runtime-property reads on the face mesh and NPC and traversed global animation instances. Lua `pcall` cannot contain a native access violation. The offline revision removes arbitrary runtime-property reads, post-process instance property reads, and global animation-instance traversal. It is not runtime-validated and remains disabled.

The crash report, minidump, UE4SS log, original configuration, diagnostic files and faulting scripts are preserved under `backups/crash-20260909-004355/`. The game executable and save files were not edited during containment.

## Native analysis and v0.6 correction

Offline analysis of the exact supplied DLL's exports, unwind ranges and call instructions narrows the failure to `push_softobjectproperty` -> unnamed copy routine -> `FSoftObjectPath::operator=` -> `FString::operator=` -> VCRUNTIME. See `runtime/native-crash-analysis.txt`, reproduced by `python scripts/analyze-crash.py`. The nearest exported symbol to frame 0x2bc184 is misleading: the frame belongs to a separate unnamed function, so this does not establish a sparse-delegate failure. The PDB path embedded in the DLL does not exist locally. The precise property and cause of its invalid path data remain unknown; this could include loader/build layout compatibility.

The [pinned UE4SS source](https://github.com/UE4SS-RE/RE-UE4SS/blob/97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1/UE4SS/src/LuaType/LuaUObject.cpp) shows soft-property reads construct a copied Lua soft-object wrapper. v0.5's generic `object[name]` reads could enter this native conversion before Lua had a value to validate. Adding another `pcall` would not fix that native access violation.

v0.6 separates F8 from morph discovery entirely. It enumerates only components returned by the selected actor and reads class/property/function metadata on the face's main animation instance. It does not read generic instance properties, animation-node structs, post-process fields or soft references. The global component fallback is removed. Each diagnostic native operation has a file checkpoint written and closed before invocation, with incremental metadata preserved in `runtime/face-api-checkpoints.txt`. These checkpoints aid diagnosis; they cannot make an incompatible native API safe.

Nine offline tests pass, including hostile runtime-property access, F8 avoiding asset/morph discovery and global animation/component scans, reversible morph preview/engagement, controller caching and bridge request validation. These are syntax and mocked behavior tests, not native game validation. The corrected scripts are staged in the disabled installed mod; both activation lists, the absent enabled marker and hot-reload-off setting are preserved.

Lip-sync is still unproven. Anca has a bone-driven face and a linked Face_Lipsync pose layer, but no verified writable speech-weight interface. [Epic's RigLogic documentation](https://dev.epicgames.com/documentation/metahuman/metahuman-dna-rig-definition-and-rig-operation) explains how facial control channels drive joint transformations; morph targets provide additional deformation. This supports investigating her animation graph inputs rather than repeatedly writing nonexistent mouth morphs. It does not prove Dawnwalker exposes those inputs to Lua. No further in-game test is requested by this revision, and no working-lipsync claim is made.
