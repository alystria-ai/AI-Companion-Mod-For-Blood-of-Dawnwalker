# Building from the public source

This source tree includes the Lua mod, TypeScript/browser client, JavaScript service, C# helper executable source, native C DLL source, tests and build scripts. Generated binaries, account credentials, local runtime state, build dependencies and Git history are not included. Normal players should use the prebuilt downloads instead.

## Tools

- Windows x64, with the .NET Framework 4.x compiler at `%WINDIR%/Microsoft.NET/Framework64/v4.0.30319/csc.exe`.
- Node.js and npm. The release uses Node.js 24.19.0. Dependencies are pinned in `package-lock.json`.
- Microsoft.Web.WebView2 SDK **1.0.4191.47**. Extract the NuGet package into `vendor/webview2/sdk/`; that folder must contain `lib/net462` and `runtimes/win-x64/native`.
- Zig **0.14.1** for Windows x64, extracted so the compiler is `vendor/zig/zig-x86_64-windows-0.14.1/zig.exe`.
- The game and its separately installed dependencies are required only for runtime testing: Dawnwalker **1.05**, game-specific UE4SS **1.2.1 RC6**, and Dawnwalker Mod Menu **1.0.7**.

Use the official [WebView2 SDK package](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4191.47) and [Zig downloads](https://ziglang.org/download/). External build dependencies are not downloaded or installed by the mod at runtime.

## Build

Run these commands from the source folder in PowerShell:

```powershell
npm ci
npm run check
npm test
npm run build
New-Item -ItemType Directory -Force runtime | Out-Null
Copy-Item examples/convai-config.example.json runtime/convai-config.json
Set-Content runtime/node-path.txt (Get-Command node).Source
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-WebView.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -AssetLoader
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -Protection
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -Simulation
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-CompanionNative.ps1 -Gaze
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-BackgroundLauncher.ps1
```

The example contains placeholders. Configure your own Convai account and character IDs in the ignored `runtime/convai-config.json` when developing conversations. Do not overwrite an existing configuration with the example or commit your runtime folder. The public source contains no shared-service credential.

`Build-WebView.ps1` compiles the C# files into `bridge/native/ConvaiHost.exe` and copies the three WebView2 SDK runtime libraries. The native builds produce `companion_native_v9.dll`, `companion_assets_v2.dll`, `companion_protection_v5.dll`, `companion_simulation_v1.dll`, `companion_gaze_v2.dll` and `background_launcher_v1.dll` in that same output directory. `npm run build` writes `bridge/public/client.js`.

## Distribution build

### GitHub Actions

Maintainers can open **Actions → Build release → Run workflow** on `main`. The workflow checks the source, downloads checksum-pinned Node.js, Zig and WebView2 dependencies, builds the helper and native DLLs, and produces Complete, Lua-only Scripts, Runtime and key-free Source ZIPs. It verifies that the two player packages reconstruct Complete, publishes checksums and build attestations, and creates a draft release by default.

The shared-service build reads the repository's `CONVAI_API_KEY` Actions secret. Public roster defaults are in `characters/release-config.json`; no developer runtime state is uploaded. The workflow runs manually on `main`, never on pull requests. Dependencies and workflow actions are pinned. Review the draft before publishing it. GitHub attestation verification is available with `gh attestation verify <archive.zip> --repo alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker`.

### Local packaging

Before packaging, populate `vendor/release-licenses/` with the licenses matching the exact dependencies you distribute:

- `NODE-LICENSE.txt`: the full license from the Node.js distribution you selected.
- `WEBVIEW2-LICENSE.txt` and `WEBVIEW2-NOTICE.txt`: the WebView2 SDK license/notices.
- `browser/`: license/notices for the Convai SDK and the dependencies included in the browser bundle.

The existing font license is retained alongside the font files. Third-party notices are required parts of the package; the release builder deliberately fails when required files are absent. A matching prebuilt Runtime package supplies the release's dependency notices under `Payload/licenses/`, if you are rebuilding with the same dependency versions.

Run `scripts/Build-Prebuilt.ps1` after all code and license files are prepared. It creates **Complete**, **Scripts** and **Runtime** ZIPs using the same game-root-relative layout. The ordinary source build expects users to configure their own account. A publisher who is authorized to distribute their service configuration can explicitly select `-BundleSharedKey`; that embeds the local shared defaults into the helper resource and excludes the local end-user identity. Never use a personal development configuration as a release credential by accident.

For gameplay testing, install the resulting Complete archive over a separately configured game loader. The old development installer under `scripts/Install.ps1` is intended for a fresh loader installation and is not the player release installer. It refuses to overwrite an existing loader. See README for the game adapter, data flow and porting methodology.
