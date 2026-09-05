# Component provenance and third-party notices

Release-candidate inventory: 2026-09-04. This inventory is not a legal opinion
or a third-party grant of rights. Original project contributions are MIT
licensed under LICENSE, subject to LICENSING.md's scope and exclusions.
No blanket MIT license is applied to third-party material. No permission
requests have been sent to any author. The final artifacts are not yet
manually accepted or approved for publication.

## Modified ReShade - bundled

Upstream: [crosire/reshade](https://github.com/crosire/reshade), commit
`18deaa52de0c425a78b329e9cb3c497281cd00ec` (v6.8.0).
The complete upstream BSD-3-Clause notice is retained verbatim in
`THIRD-PARTY-NOTICES/ReShade-BSD-3-Clause.txt`. It permits modified binary
redistribution subject to its notice, disclaimer and no-endorsement conditions.
This project distributes a modified derivative, not an official ReShade build.

Modifications: D3D12 destruction-callback lifetime guards, foreground-isolated
physical F6, a PID-scoped F6 bridge, and the read-only process-local NR state and
acknowledgement API. The 6.8.0.10 candidate is documented in
`source/reshade/provenance.json`; its complete derivative source patch is
`source/reshade/reshade-6.8.0-evejs-v11.patch`, with the pinned version header at
`source/reshade/version-6.8.0.10.h`. This binary is unsigned and unchanged from
the previously user-tested native/V12 runtime. Those historical passes are not
manual acceptance of the final package/launcher. A byte-identical clean rebuild
has not been demonstrated; see `source/reshade/BUILDING.md`.

The original build records and patches are preserved verbatim, including any
build-time acceptance status. Existing file-level licences take precedence for
their material: the F6 helper's BSD-3-Clause marker remains unchanged. The
project MIT grant does not replace the upstream BSD terms or embedded dependency
notices. Eleven upstream dependency notice resources remain embedded in the
ReShade binary and accessible through its About UI.

### Microsoft header inputs

DirectX-Headers and D3D9/11-on-12 header inputs retain the full Microsoft MIT
notice at `THIRD-PARTY-NOTICES/Microsoft-DirectX-Headers-MIT.txt`. This notice
does not cover unrelated Microsoft SDKs or runtime components. No binary or
native source patch was rebuilt or altered to add this notice.

## RenoDX DLSS5 4.70 - downloaded, not bundled

The exact add-on is obtained from the pinned RankFTW/rhi-repo release archive.
Its publisher mirror does not establish a separate blanket license for every
asset. The RenoDX framework is MIT; the unmodified notice from
[clshortfuse/renodx](https://github.com/clshortfuse/renodx/blob/main/LICENSE)
is included as `THIRD-PARTY-NOTICES/RenoDX-MIT.txt` for attribution and reference.
The binary is unsigned and pinned by archive and member SHA-256.
Do not interpret the framework license as permission for unrelated NVIDIA
components or as independently proven source equivalence for this release.

## NVIDIA DLSSNR and Streamline NR plugin - downloaded, not bundled

DLSSNR 310.8.0 and `sl.dlss_nr.dll` from the Streamline 2.13.0.0 archive are
downloaded from exact RankFTW/rhi-repo release URLs. Both must pass real NVIDIA
Authenticode checks and exact byte hashes. A mirror URL is provenance of the
download, not a claim that NVIDIA officially published that mirror.

Reference notices retrieved from upstream on 2026-09-03:

- `THIRD-PARTY-NOTICES/NVIDIA-RTX-SDK.txt`, from
  [NVIDIA/DLSS LICENSE.txt](https://github.com/NVIDIA/DLSS/blob/main/LICENSE.txt).
- `THIRD-PARTY-NOTICES/Streamline-MIT.txt`, from
  [NVIDIA-RTX/Streamline license.txt](https://github.com/NVIDIA-RTX/Streamline/blob/main/license.txt).

The current upstream RTX license snapshot differs byte-for-byte from the
RTX license retained with the historical Swapper payload. It is a reference
snapshot, not proof of the exact agreement attached to every mirrored binary.
RTX SDK and feature-specific terms may apply in addition to Streamline's MIT
framework license. Source notices do not relicense proprietary SDK components.
Users remain responsible for applicable component terms when downloading/using
them. This project's small-download design does not waive those terms.

## Local client compatibility guard - generated

No client executable, Python runtime DLL, original/patched `code.ccp`, extracted
PYC or full client distribution is included. The local client must already be
obtained and usable by the user. The generator verifies the exact original
archive and the client's Python DLL before replacing the graphics-apply and
device-startup methods in two stages, then verifies the exact accepted archive
hash. Only those two archive entries change; every other entry stays byte-identical.

The 0.5.6 source-only templates replace retained client implementation blocks
and mixed expressions with local-data placeholders. Authored reconstruction
helpers derive those statements from the user's pinned original code objects.
Startup template lines 170 and 181 remain authored startup policy using matching
device API expressions; they are documented integration glue, not a claim that
every expression matching the client has vanished. See SOURCE-GENERATION.md.

This reduces distributed client implementation; it does not grant permission
for client modification, local derivation or derivative distribution, and does
not relicense any third-party material. No blanket first-party MIT claim or
legal clearance is made. The relevant rights review remains a release gate.

## Not included

DLSS5 Swapper and RHI executables/source are not dependencies and are not
redistributed. No RHI GPL implementation was copied into the bootstrap. Their
own source licenses do not authorize redistribution of all associated payloads.

The project owner selected MIT for original EveJS-DLSS5 contributions. See
LICENSE and LICENSING.md for the grant, separately licensed code and exclusions.
The separate EveJS launcher remains GPLv3. No client, SDK, framework or mixed
derivative is converted wholesale to MIT by that choice. Source/rights
uncertainties remain; this candidate is not a completed legal-clearance review.
Fresh exact-artifact manual testing and separate publication approval are still
required before any release.
