# DLSS 5 Neural Rendering + ReShade 0.5.16

In EVE 24.02 build 3724492, use EVE's graphics menu to choose the upscaler, quality
preset and Frame Generation. Press Home for the ReShade overlay or F6 to toggle
DLSS 5 Neural Rendering. This candidate uses EVE's installed DLSS libraries.

The two supported build 3396210 variants retain their reviewed archive outputs.
Build 3724492 preserves EVE's original Upscaling dropdown and uses its graphics
apply and device-startup guards to manage renderer transitions. When you return to
DLSS, the guard can restore the last known Neural Rendering choice for that session.

The installer selects a manifest using the build number together with the exact
executable hash, because an executable identity is shared between known builds.
Unknown build/executable pairs and changed patch-target entries are rejected.

## Qualification limits

Offline archive generation, entry preservation, helper/transition/recovery tests
and package integrity checks are required. The actual 3724492 runtime and renderer
identities have been inspected. Its Python PE sections/imports/exports match the
old runtime; its valid Fenris signature is pinned separately by hash, size, subject
and certificate. Build 3396210 retains its original exact CCP contract. Require
an isolated install/verify/restore pass before live DX12/DLSS/NR acceptance.

The known synthetic F6 acknowledgement and automatic NR re-arm limitation remains.
Passing source fixtures does not establish successful live neural rendering.

## Platforms and backends

This is a Windows x64 client package requiring Windows PowerShell 5.1 and the
reviewed NVIDIA/RenoDX stack. DX12 is the DLSS5 route. Native and Docker server
backends are declared; Docker runtime acceptance is unverified here. Server-side
Linux support does not qualify the client mod. Linux native, Wine/Proton and Steam
Deck installation/rendering remain unqualified.

Keep the original client backups and install journal. Do not apply this local
candidate to a live/shared client while qualification is incomplete. Installation,
verification and removal remain owned by the mod's existing launcher helper and
standalone manager. Generated client archives and copied runtime DLLs are private
build-local files and are excluded from the package.
