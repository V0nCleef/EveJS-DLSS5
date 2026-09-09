# EveJS DLSS5 + ReShade 0.5.8

The combined package includes ReShade, RenoDX integration and the DLSS5 client guard. Do not install a second ReShade proxy over it. Launcher integration requires **EveJS Launcher 1.0.53 or later**.

DLSS5 owns its installation, profile preparation and rendering behavior through the public mod interface. It is not tied to a particular EveJS server version; the physical EVE client build requirement below still applies.

## Requirements

- A working local EveJS installation and physical EVE client build **3396210**.
- 64-bit Windows with Windows PowerShell 5.1.
- Hardware compatible with the retained DLSS5/RenoDX payload. Focused rendering and two-client checks were performed on the test setup; other hardware combinations are not all verified.
- Internet for missing first-install archives. Valid materialized cache files
  can be used without downloading their source archives again.

## Launcher installation

1. Keep the complete `DLSS5` folder together in your EveJS `mods` folder, or
   import the release ZIP through Launcher 1.0.53.
2. Select the correct EveJS and physical `tq` client in the launcher.
3. Close clients using that physical installation, then install/enable the mod.
4. Use the mod's **Configure** form to choose the Neural Rendering preference
   for a launcher profile. Restart that profile's client after changing it.
5. Launch normally. The helper prepares private ReShade settings through the
   launcher's public contribution interface.

The manifest is `evejs-launcher.mod.json`. This package omits the
old automatic `evejs-launcher.client-mod.json` contract, which cannot express its
minimum launcher version or contribution ownership.

Installation, disable and removal are **global to the physical client**. Multiple
profiles use the same binaries and keep their own NR preferences. Removing one
profile does not uninstall those shared DLLs. Distinct physical clients remain
independent; positively identified clients from another installation do not
block changes here. A client whose executable path cannot be read is reported
separately before shared binaries are changed.

The private INI retains existing settings, including F6-persisted OFF. Older
`<profile>/DLSS5` settings and presets are imported as key contributions without
changing the originals. Shader/texture paths keep their original locations.
A shared `[INSTALL] BasePath` override needs to be resolved first because it
would override profile isolation.

## Updating from 0.5.7

1. Update the launcher to **1.0.53** first. Keeping DLSS5 0.5.7 installed is supported; a launcher update does not upgrade the mod automatically.
2. Close EVE clients before changing the mod. Keep your existing package and recovery backups.
3. Remove the old DLSS5 package through the launcher, retaining private profile data. Complete its cleanup before importing the new ZIP; do not overwrite an active mod folder.
4. Import **EveJS-DLSS5-0.5.8.zip**, then enable the new DLSS5 package. Confirm the configured physical client path and your profile's Configure settings before launching.

Version 0.5.7 has no update metadata, so this first upgrade is manual. Once 0.5.8 is installed, later compatible releases can appear under **Mods** with a gold update badge and **Update** button. The update window shows release notes, download progress and installation stages. The companion `.update.json` asset is read automatically; users do not import it separately.

## Standalone use

Keep the extracted package, close clients using the selected installation and
run `Install-DLSS5.bat`. Supply the EveJS folder when requested; it reads the client
location from that setup. `Verify-DLSS5.bat` checks installation files.
`Uninstall-DLSS5.bat` restores the owned original files and settings.

## In-game behavior

- Select DLSS in the game's graphics settings. NR is the additional neural
  rendering effect; Frame Generation is a separate setting.
- Physical F6 affects the foreground client. Synthetic toggles target the
  process-owned window through the retained native bridge.
- Moving from another upscaler into DLSS requests NR ON. Saved DLSS startup keeps
  the persisted preference, including OFF.
- Changes while staying on DLSS preserve the latest manual NR choice.
- If F6 or the add-on lifetime changes during the OFF settling period, the
  graphics mutation stops for a retry. A quick ON-then-OFF is detected too.
- A failed graphics apply remembers the wanted preference for a later ready
  retry. Startup synchronization allows at most three relevant device-creation
  attempts during one process lifetime.

Do not infer successful neural rendering from the ReShade banner alone. Check
NR evidence and the actual image in the selected client. For a launcher profile,
`EveJS-Integration/Verify-Runtime.bat <PID> "<private mod data directory>"` reads
that profile's `ReShade.log`; omitting the second argument checks the shared log.

## Removal and recovery

Use the launcher's mod removal or the standalone uninstaller for the selected
server. Keep the package until removal finishes. When multiple servers share
the same physical client and DLSS5 payload, each has its own launch-settings
attachment. Removing one restores that server's settings; the payload remains
until the last server detaches. Private profile preferences remain separate.
Shared original-file backups and the binary
journal remain beside the physical client at
`<tq parent>/_evejs/dlss5/install`. The public reference receipt inside
`tq/_local/mod-receipts/dlss5/<server-key>.json` survives a missing server/mod
folder. Each server gets its own reference receipt, so another server cannot
overwrite its launcher identity. Older `dlss5.json` receipts remain untouched.

The manager's `-Action VerifyClient` checks the retained physical installation
without requiring the original server folder. Supply the recorded
`-EveJSRootPath`, its parent `-WorkspaceRoot`, and the physical `-ClientRoot`.
This is a read-only client check; normal `Verify` also checks server launch wiring.

`Ensure` attaches another explicitly selected server to an already installed,
matching payload without rewriting its DLLs or client archive. A different
payload or global control profile is a shared-file conflict: detach the server
attachments before changing that physical installation. An interrupted attachment
is retained in the journal; `Recover` restores its server settings before retrying.
It does not uninstall a payload still used by another attached server.

Profile changes and payload upgrades have separate operation snapshots. A failed
operation restores its own preimages; it does not overwrite the original-install
backups. Recovery refuses to overwrite a file changed outside the transaction.
If the former server is gone, client restoration does not recreate that server.

Only the integration's batch assignments and recorded ReShade keys are restored.
Unrelated settings, custom preset data and logs remain. An originally absent INI
is removed when no meaningful values remain. Repeating removal never acquires
ownership of files created later. Proxy DLL conflicts remain explicit binary
conflicts; they cannot be merged as INI contributions.

## Licensing and source

See the files under `DLSS5/`: `LICENSING.md`, `THIRD-PARTY-NOTICES.md`, `SOURCE-GENERATION.md` and the retained
ReShade source/provenance files. Generated client archives and the copied client
Python runtime are build-local data and are not shipped in the public ZIP.
