# EveJS DLSS5 0.5.5

Release candidate for local EveJS, paired with launcher **1.0.50**. These final
artifacts have not yet received manual acceptance and have not been published.
Use the exact package and launcher supplied for testing; older development
builds can display the same launcher version without trusting this package.

This is not an official CCP, NVIDIA, RenoDX or ReShade product and is not
intended for the official EVE Online service.

## What you get

- DLSS5 neural rendering alongside the client's existing DLSS/Streamline runtime.
- Automatic EveJS launcher mod detection, plus standalone install, verify and
  uninstall entry points for users who do not use that launcher.
- Per-process NR state and foreground-only physical F6: one client's manual
  toggle must not change another client.
- Guarded graphics transitions and verified rollback, preserving original files,
  backups, unrelated settings, characters and server/market data.
- A small package: NVIDIA/RenoDX dependencies are downloaded from pinned sources;
  the supported client archive is reconstructed locally, not bundled.

Requires Windows x64, Windows PowerShell 5.1, EveJS 0.12.6 or 0.12.7 and the exact
supported client build **3396210**. EveJS version and client-build compatibility
are separate checks. Runtime evidence is from an RTX 5090, not a guarantee for
other hardware. Follow the applicable NVIDIA/RenoDX component requirements.

## Launcher mod workflow

Once the exact candidate has been approved for testing:

1. Use the matching launcher 1.0.50 package.
2. Extract the download so its folder is `<EveJS>/mods/DLSS5`, then refresh Mods.
3. Confirm EveJS DLSS5 is detected and enabled automatically; no extra opt-in.
4. With all clients using the target client folder closed, launch a character.
   Client preparation downloads, verifies and installs the required files.

Installation occurs during client preparation, not when starting the game
server. Clients without this mod keep the normal launch path. The launcher's
Uninstall action restores verified originals and retains a recoverable package
and rollback records; do not remove the folder first.

For any update, keep the original package and its rollback state until the
old installation is restored. Do not overlay an enabled development package
or manually relabel its receipt. The candidate handoff will specify the exact
manual test scope; these instructions do not request an automatic broad matrix.

## Standalone install and uninstall

The EveJS launcher is optional. With all target clients closed:

- Run `Install-DLSS5.bat`. A package under `<EveJS>/mods` detects that root;
  elsewhere it asks for the EveJS folder.
- Start your normal EveJS server/market and use the existing `Play.bat`.
  No new standalone character profiles or Play.bat wrapper are introduced.
- Run `Verify-DLSS5.bat` to verify an installation without downloading.
- Run `Uninstall-DLSS5.bat` to restore originals before deleting the package.

The installer reads the configured client path as data; it does not execute
the configuration file to discover paths. It prints the selected targets.
For explicit noninteractive paths:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EveJS-Integration\Invoke-Standalone.ps1 -Action Ensure -EveJSRootPath 'D:\Games\EveJS' -ClientRoot 'D:\Games\Client\tq' -NonInteractive
```

Both entry paths use `<EveJS>/_local/dlss5/install` for the journal, backups,
history and cache. Keep this state. Uninstall works without download caches
or the network, but requires the original manager package, receipt and verified
backups. Never delete that state directory as a substitute for uninstalling.

If multiple EveJS roots share one physical client, uninstall changes that
shared client for every root; only the selected root's configuration is restored.
Do not share one receipt between different physical clients or edit old receipt
paths after moving a client. Legacy fourteen-file laboratory receipts must be
restored with their original package before a fresh five-file installation.

## Graphics behavior

Every actual transition from Off, FSR or another upscaler into DLSS enables NR.
Afterward, physical F6 can toggle NR manually in the foreground client only.
Remaining on DLSS while changing presets, shaders, textures or Frame Generation
preserves the current manual choice. Leaving DLSS disarms NR.

At startup, Off/FSR disarms NR; an already-DLSS startup preserves its existing
NR/F6 state. There is no continuous watcher overriding manual F6.
The guard uses process-local native state and fresh toggle acknowledgements,
never shared INI/log files as live authority.

Graphics changes can take several seconds: the unchanged conservative guard
waits five seconds after confirming NR off, then three seconds after the final
apply pass before rearming, plus a short settling delay. Unknown NR state,
ambiguous acknowledgement or readiness timeout blocks a guarded mutation.
Readiness flags and fixed delays do not prove that all GPU work has finished.

Earlier standalone one-/two-client DLSS/Off/FSR/F6 and exit-order tests,
uninstall/stock-client checks and additional user-directed launcher tests passed.
These are historical evidence for the unchanged native/V12 runtime, not manual
acceptance of this final 0.5.5/1.0.50 pair or a full hardware/graphics matrix.

## Integrity and scope

Exactly five client files are managed:

| File | Source |
| --- | --- |
| `bin64/nvngx_dlssnr.dll` | Pinned DLSSNR 310.8.0 download |
| `bin64/sl.dlss_nr.dll` | Pinned Streamline 2.13.0.0 archive member |
| `bin64/renodx-dlss5.addon64` | Pinned RenoDX DLSS5 4.70 download |
| `bin64/dxgi.dll` | Bundled modified ReShade 6.8.0.10 |
| `code.ccp` | Locally generated exact V12 archive |

The original executable is untouched. Owned ReShade settings and the client
path/DX12 configuration markers are journaled too. Unknown originals, drift,
ambiguous paths and unsupported builds fail closed. Server code, character
data, market databases and shared resources are not installation targets.

The three pinned downloads total 112,619,848 bytes (about 107.4 MiB).
Archive/member hashes, complete ZIP inventories, sizes and signer identities
are checked; no “latest” lookup or downloaded installer is executed. NVIDIA
payloads require the pinned valid Authenticode identity.

Trust flows from launcher allowlist to exact manager, helper, raw manifest,
runner, builder, templates and source helpers. Generator inputs are checked on
cache hits and before each stage. Verified helper bytes are loaded into private
scopes without adjacent-module imports or cached Python bytecode. This is a
hash-pinned chain, **not a digitally signed manifest**.

Use a reasonably short installation path. Deep Windows process-launch paths
remain unsupported/unaccepted. Forced termination and cancellation limits remain
in [the release checklist](RELEASE-CHECKLIST.md), separately from ordinary
exception/rollback checks. Matching second-client preparation stays read-only.

## Source and licensing

Original project contributions are MIT licensed; see [LICENSE](LICENSE) and
[LICENSING.md](LICENSING.md) for the exact scope and exclusions. Modified
ReShade remains subject to BSD-3-Clause and its dependency notices, including
existing file-level BSD markers. NVIDIA, RenoDX, Microsoft headers, client
material and the separately GPLv3-licensed launcher are not relicensed by this
project's MIT grant.

The package derives retained client implementation from the user's pinned
local archive. It ships no original/patched client archive, extracted PYC,
client Python DLL, private evidence or downloaded NVIDIA/RenoDX binaries.
See [SOURCE-GENERATION.md](SOURCE-GENERATION.md) and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Local reconstruction and install-time downloads reduce material carried in
the package; neither grants modification/redistribution rights nor establishes
legal clearance. Source/rights uncertainty remains documented. Every changed
artifact requires fresh user manual testing before publication, and a passing
test is not authorization to commit, tag, upload or release.
