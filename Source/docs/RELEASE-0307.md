# 0.30.7 Preview release notes

- Adds **Copy logs** to the left side of the native Help page. The helper collects bounded diagnostic tails off the game thread, excludes conversation/configuration files, removes credentials and local paths, copies the report to the clipboard and saves `Payload/runtime/support-report.txt`.
- Publishes matching **Complete**, **Scripts** and **Runtime** packages. Complete is the recommended download; Scripts and Runtime must be installed together. Every archive uses the same game-root-relative path.
- Updates installation, controls, feature, customization and file-structure documentation, plus `nexusmods.md` for the mod page and public-source build instructions.
- Preserves the 0.30.6 loading improvements and existing gameplay behavior. This release does not introduce new combat changes.

## Validation

282 JavaScript/Lua regression tests pass. All 25 production Lua files parse. TypeScript checking and browser/helper compilation pass. The dedicated C# diagnostic test verifies the file allowlist, credential/path/transcript redaction, bounded reads and missing-file handling without altering the clipboard. Complete and split archives have been checked for correct destinations, required components and matching installed-file hashes. The Scripts archive contains no EXE or DLL. The public source export excludes binaries, runtime data, credentials and Git history.

Actual Vortex deployment and the new button's in-game mouse/clipboard interaction have not been exercised. The helper update requires a game restart on the current development installation. The local loader console is disabled for the next launch; player packages preserve existing global loader settings and document the optional console settings.

This is a preview, with per-character combat/power coverage still limited. See the installation guide for the supported versions and gameplay limitations.
