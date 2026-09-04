# EveJS-DLSS5

Optional DLSS5 Neural Rendering integration for local EveJS, with both a
standalone installer/uninstaller and automatic EveJS launcher mod support.
This is an independent community project, not an official CCP, NVIDIA, RenoDX
or ReShade product, and is not intended for the official EVE Online service.

## Current package

The reviewed pair is **DLSS5 0.5.5** and **EveJS Launcher 1.0.50**, for Windows
x64, EveJS **0.12.6 / 0.12.7** and client build **3396210**. Runtime testing was
performed on an RTX 5090; this is not a general hardware compatibility promise.

Get the complete package from this repository's Releases page when published.
The same ZIP supports both installation methods:

- Launcher: put its complete `DLSS5` folder in `<EveJS>/mods`, refresh Mods, and
  leave the automatically detected mod enabled. Dependencies are prepared at
  client launch, not server startup. Use the matching launcher release.
- Standalone: run `Install-DLSS5.bat`, select the EveJS folder, then use the
  normal server/market scripts and `Play.bat`. The launcher is optional.

Close every client sharing the target client folder before installing or
uninstalling. Use the launcher Uninstall action or `Uninstall-DLSS5.bat` before
removing an installed package. Keep `_local/dlss5/install` and its backups.
Separate EveJS roots sharing one physical client are not isolated installations.

See the [complete instructions](DLSS5/README.md),
[graphics behavior](DLSS5/README.md#graphics-behavior),
[changelog](DLSS5/CHANGELOG.md) and [source generation](DLSS5/SOURCE-GENERATION.md).
Entering DLSS enables NR; leaving DLSS disables it. F6 may then toggle NR in
the foreground client without changing other clients.

## Source and package integrity

`DLSS5/` contains the exact reviewed package source and bundled components.
The client archive is generated locally from the supported original; NVIDIA
and RenoDX binaries are fetched separately from fixed, hash-verified sources.
They are not carried in this repository's package. The original client EXE is
not modified, and unknown inputs fail closed.

Run `Build-PublicCandidate.ps1` in Windows PowerShell 5.1 for a read-only package
inventory/hash check. ZIP creation is a separate explicit preparation action:
`-CreateZip -SourceStableGo`. A newly created ZIP is not automatically the
already accepted release artifact; maintainers retain and publish the exact
tested ZIP, with its hash stated in the release notes.

The immutable package documents retain their preparation-time candidate status.
Acceptance was subsequently recorded for the exact 0.5.5 / 1.0.50 test pair;
current release notes distinguish that from any broader testing claim.

## Licensing

Original project contributions use [MIT](LICENSE), with the limits and separate
terms in [LICENSING.md](DLSS5/LICENSING.md) and
[third-party notices](DLSS5/THIRD-PARTY-NOTICES.md). Existing BSD notices remain
in place. The separate launcher remains GPLv3. This MIT grant does not relicense
NVIDIA, RenoDX, ReShade, client code or other third-party material.

Local generation and install-time downloads do not establish legal clearance.
Exact mirrored-component terms and client modification rights remain separate,
unverified questions; no blanket permission or endorsement is claimed here.
