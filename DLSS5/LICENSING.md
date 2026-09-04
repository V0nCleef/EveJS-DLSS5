# Licensing scope

The project owner selected the MIT licence for original EveJS-DLSS5 project
contributions on 2026-09-04. See [LICENSE](LICENSE). The grant covers only rights
held by the respective contributors. It does not assert ownership of underlying
game code or relicense any third-party component.

## Project contributions

Original installer scripts, bootstrap and reconstruction helpers, runner source,
authored guard logic, tests and documentation are offered under MIT to the extent
they are original project contributions. A matching compiled project-owned tool
has the same first-party grant, without changing terms for any incorporated
third-party material. Existing third-party notices and separately licensed code
take precedence for that material.

This is not a claim that a mixed source file, generated client method, patch,
native DLL or complete installed client is entirely MIT licensed.

## Separate components and exclusions

- Modified ReShade retains the upstream BSD-3-Clause notice and its dependency
  notices. Existing file-level licences, including the F6 helper's BSD-3-Clause
  marker, remain in place and take precedence. MIT covers original project
  contributions not separately licensed, not upstream/context code. The complete
  derivative must retain the applicable notices; consult
  [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
- DirectX-Headers and D3D9/11-on-12 header inputs retain Microsoft's MIT notice
  in [Microsoft-DirectX-Headers-MIT.txt](THIRD-PARTY-NOTICES/Microsoft-DirectX-Headers-MIT.txt).
  This notice does not cover other Microsoft SDKs or runtime components.
- RenoDX, NVIDIA DLSSNR and NVIDIA Streamline components retain their respective
  terms. A framework licence is not proof of the licence governing every
  downloaded feature binary. They are not relicensed under this project's MIT
  grant, whether downloaded by the installer or supplied by the user.
- The user's original client, Python runtime and locally reconstructed client
  implementation are excluded from this project's MIT grant. Local generation
  does not confer client modification or redistribution rights.
- The separately maintained EveJS launcher remains GPLv3. No launcher code is
  relicensed by this document. Any code incorporated from a GPL or other
  third-party project retains its applicable obligations; its presence must be
  reviewed rather than treated as automatically covered by MIT.
- Third-party licence texts themselves retain their original attribution.

The package's third-party notices include full texts and provenance references.
ReShade also embeds eleven upstream dependency notice resources accessible
through its About UI. Do not remove those resources or replace their notices
with the project MIT licence.

## No blanket release clearance

The MIT choice resolves the project's own licence decision only. It is not a
grant from NVIDIA, RenoDX, Microsoft, ReShade or a client rights holder, not an
endorsement by them, and not a guarantee against legal claims. Exact mirrored
component terms and compatibility/modification rights remain separate issues.
An install-time download does not, by itself, establish that every applicable
term has been satisfied.

Reference: the [standard MIT text](https://opensource.org/license/mit).
