# Dawnwalker Convai file structure

The mod has two layouts: the development source tree and the self-contained installed mod. They contain related files, but they are not interchangeable.

## Installed layout

Every release archive starts at the game root. After installing **Complete**, or merging both **Scripts** and **Runtime**, the important folders are:

```text
Dawnwalker/
└─ Binaries/
   └─ Win64/
      └─ ue4ss/
         └─ Mods/
            └─ DawnwalkerConvai/
               ├─ enabled.txt
               ├─ config.ini
               ├─ keybindings.ini
               ├─ mod_settings.ini
               ├─ Scripts/
               │  ├─ main.lua
               │  ├─ live_reload.lua
               │  └─ runtime_path.lua
               └─ Payload/
                  ├─ bridge/
                  │  ├─ native/
                  │  ├─ public/
                  │  └─ fonts/
                  ├─ characters/
                  ├─ docs/
                  ├─ licenses/
                  ├─ mod/
                  │  └─ Scripts/
                  ├─ node/
                  ├─ runtime/
                  ├─ scripts/
                  └─ release.json
```

| Installed path | Purpose |
| --- | --- |
| `DawnwalkerConvai/Scripts/` | Small UE4SS entry point. `runtime_path.lua` points to the packaged payload beside it. |
| `DawnwalkerConvai/config.ini` | Companion damage, attack frequency, profile selection, camera, player conveniences, automatic reactions and Horde preferences. |
| `DawnwalkerConvai/keybindings.ini` | The six configurable shortcuts, including F4 for camera switching. |
| `DawnwalkerConvai/mod_settings.ini` | Metadata used by the game's Mod Settings interface. |
| `Payload/mod/Scripts/` | Gameplay Lua: conversations, UI, companions, combat, recovery and movement. |
| `Payload/bridge/` | Local service modules, browser client, fonts and helper support files. |
| `Payload/bridge/native/` | Compiled helper executable, WebView2 assemblies and native companion DLLs. |
| `Payload/characters/` | Packaged roster, lore, relationships and reviewed quest context. |
| `Payload/docs/` | Installed copy of the player installation and file-structure guides. |
| `Payload/node/` | Bundled local JavaScript runtime. |
| `Payload/runtime/` | Packaged conversation configuration plus generated session, status and diagnostic files. |
| `Payload/scripts/` | Helper startup script used by the packaged runtime. |
| `Payload/licenses/` | Third-party licenses and notices. |
| `Payload/release.json` | Machine-readable mod, game, prerequisite and native-helper versions. |

`Payload/runtime/support-report.txt` is generated when **F5 → Help → Copy logs** is used. It contains a sanitized support report rather than the complete unredacted logs.

The helper's browser profile lives in `%LOCALAPPDATA%\LLMNPCCompanions\WebView\`, in a separate folder for each installation. This keeps browser cache files out of Mod Settings' mod scan. On upgrade, the helper moves its previous `Payload/runtime/webview-profile` data there, preserving stored conversation identities and sessions.

## What each archive supplies

| Archive | Installed content |
| --- | --- |
| **Complete** | The entire `DawnwalkerConvai` tree shown above. |
| **Scripts** | Lua bootstrap and gameplay scripts only. |
| **Runtime** | All non-Lua files: configuration, data, browser client, executables, DLLs, documentation and licenses. |

The split archives deliberately overlap at the directory level. Extract both matching versions to the same game root so the final tree contains both sets of files. **Scripts alone and Runtime alone are incomplete.**

The release packages do not contain UE4SS or Dawnwalker Mod Menu and do not write `ue4ss/UE4SS-settings.ini`. Install those prerequisites separately. If desired, hide the local UE4SS console by setting `ConsoleEnabled = 0` and `GuiConsoleEnabled = 0` in the existing settings file while preserving every other loader option.

## Source layout

The repository remains a development workspace. Its top-level folders map into the installed payload during packaging:

| Source path | Contents and packaged destination |
| --- | --- |
| `mod/Scripts/` | UE4SS gameplay Lua; packaged under `Payload/mod/Scripts/`, with the stable entry files also placed under installed `Scripts/`. |
| `mod/config.ini` | Default installed `config.ini`. |
| `mod/keybindings.ini` | Default installed `keybindings.ini`. |
| `mod/mod_settings.ini` | Default installed Mod Settings metadata. |
| `bridge/` | TypeScript/JavaScript service, browser UI, all C# helper source, fonts and all C native-helper source. Selected built files are packaged under `Payload/bridge/`. |
| `bridge/native/` | Local build outputs. Only the explicit release allowlist is packaged. |
| `characters/` | Research and authored character data. Only the runtime roster, lore and quest files needed by players are packaged. |
| `runtime/` | Developer configuration, state, diagnostics and generated files. Packaging creates a minimal clean runtime and excludes local history. |
| `scripts/` | Developer build, install, test and maintenance tools. Only the packaged startup script is installed. |
| `tests/` | Automated regression tests; not installed. |
| `docs/` | Installation and engineering documentation; not required by the running mod. |
| `vendor/` | Locally supplied build/runtime dependencies and release notices; selected authorized runtime files are packaged. |
| `dist/` | Generated release folders and archives; not source. |

The development installer uses a small installed bootstrap that points back to the source workspace. Release packages are self-contained: their bootstrap resolves `Payload/runtime` inside the installed mod, so players do not need the repository, npm or a separate Node.js installation.

The public source contains no shared-service credential. Developers copy `examples/convai-config.example.json` into the ignored `runtime/` folder and provide their own account values locally. Authorized release builds can compile the shared configuration into the helper resource; the packaged runtime JSON does not expose it.

Do not create a release by archiving the whole repository. The release builder uses an explicit allowlist to avoid development state, local paths, browser profiles, test output and unrelated build inputs.


For 0.4, `characters/romance-config.json` contains public mappings for the relationship profile copies. `companion_appearance.lua` owns saved colours and material changes; `companion_romance.lua` reads current-save relationship evidence. Romance stays within conversation, with no scene playback. The bridge's `relationships.mjs` validates the snapshot and adds private relationship context. `characters/research/family.json` is the source for the additional family biographies. `TODO.local.md` is an ignored local work list and is never part of a release or source archive.
