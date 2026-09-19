# v0.26.5 native spawn regression

## Evidence

The two crashes at 14:16 and 14:18 on September 13 share the same stack: native bridge v7 +0x376a → UE4SS FWeakObjectPtr constructor +0x3c5cc3 → pointer assignment +0x46694f → FUObjectArray::AllocateSerialNumber +0x42a011 → Unreal wrapper/string-copy frames → null read in VCRUNTIME140. The last fixed request is `spawn` for Anca; the party snapshot contains only Anca, still marked Loading reactions. The code is synchronous, so the second UI click is not needed for this crash. Original dumps, runtime XML and the UE4SS log are preserved in `runtime/session-v0265`.

Offline disassembly of the installed UE4SS DLL shows the allocator returns immediately when FUObjectItem.SerialNumber is nonzero. The zero branch takes the path seen in both crashes. The precise inner wrapper failure is not established; no claim of a missing native signature is needed for the fix.

The previous read-only benchmark used an old spawner whose serial was 202152. It validated the existing-object Get path, but did not exercise allocation of a serial for a fresh async action. The earlier native mocks also omitted that constructor boundary. Those were inadequate checks for first creation.

## Change

v8 removes every weak-pointer constructor/assignment call from the bridge. `captureWeak` reads the object's index, retrieves its FUObjectItem through UE4SS, and reads the engine-owned serial using exported accessors. A zero/negative serial returns unavailable without calling Weak.Get, writing engine memory or trying to allocate a serial. A positive serial is copied to an eight-byte local handle and accepted only if Get resolves it to the same object.

The async action is activated before borrowing its identity. The population spawner is captured and rooted as before. If a serial is absent, polling may resolve a typed recorded path at most once per five seconds, then try to borrow the identity again. As soon as an engine-assigned serial exists, polling returns to constant-time handles. Captured-but-expired serials cannot fall back to a replacement object at the same path. Once the durable spawner path is captured, normal polls do not look up a retired action. Stop may use a one-time typed fallback for serial-less owners and preserves ownership if native Stop is unavailable.

The fallback can still cost a scan; it is a compatibility path, not a zero-cost guarantee for all builds. No global serial counter, actor memory, population priority or executable instructions are patched. Parallel UI queueing is unchanged because evidence identifies first-object construction rather than a queue race.

Stage markers for population-factory, activate-population and borrow-existing-identities are flushed before native calls. An access violation can no longer leave the entire reply empty simply because stdio had buffered its last stage.

## Validation

Native offline tests cover serial zero (no allocator and no Weak.Get), valid engine serial, mismatched serial, invalid index, throttled fallback, transition to a borrowed serial, 250 scan-free polls, expired owners, root ownership, retained registry on Stop failure, dynamic growth and freed-slot reuse. The existing 100 Node/Fengari behavior tests and Lua parsing are also run. Actual first-spawn and overlapping-summon gameplay remain unverified until the next user test.
