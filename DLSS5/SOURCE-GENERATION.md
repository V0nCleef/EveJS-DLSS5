# Local source generation — 0.5.9 / V13 guard

Package and integration payload version are both **0.5.9**. The original public
client guard and archive pins are unchanged from 0.5.8. An additional reviewed
manifest covers the second known build 3396210 client variant.
The pinned RenoDX add-on changes to 7.0.0-rc8. The bundled ReShade
6.8.0.10/EveJS V11 DLL and NVIDIA inputs are unchanged. No native DLL was
rebuilt or manually patched for this release.

Only an exact supported client archive is accepted. The narrow Python 2.7
emitter derives local names, literals and control-flow fragments from code
objects as data. Unsupported code shapes and input hashes are rejected.
Original or reconstructed client modules are never imported or executed during
this build. The existing pinned Python runtime compiles the authenticated
source templates into replacement code objects.

`native_nr_bridge.py.in` is now the single authored copy of the common bridge,
state-query, acknowledgement and toggle helpers. The builder authenticates it
alongside both templates and expands it in memory. The process-owned HWND,
foreground physical F6, synthetic local F6, epoch and destruction guards remain.
Block markers are unique and their reserved source-slot counts are checked;
author changes no longer require duplicated absolute template line numbers.

## Generated identity

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| Original archive | 30,757,025 | `89696509EFDC1B081F7371B40CA3D459059DB0E43B5DB328FE373C0F2A9B1A86` |
| Graphics stage | 30,760,790 | `26E9DD79F78A5CC25C08FFE37EC2689FE646F4745D16C212E8023D51A85A115F` |
| Complete V13 candidate | 30,763,842 | `0DACCC88471E23A068E08B6191126C27B303470D9BE77AD6DFEF1BB6EDD28275` |

All 12,527 archive entry names/order were retained; exactly the graphics and
startup entries changed. The manifest records both new PYC identities and all
eight generator asset hashes. The generator authenticates all authored inputs
before evaluation, reuses computed digests and closes its file handles.

## Verification boundary

The isolated build used copies of the pinned original code.ccp and Python DLL.
Template tests model state sequences, physical F6, renderer readiness, retries
and startup scheduling. Installer tests use disposable files and mocked process
or network results. These establish source/data and control-flow behavior;
**they do not establish live GPU rendering, client stability, or release
acceptance**. Complete `RELEASE-CHECKLIST.md` before publishing.

The package contains no generated code.ccp, client source/module dump or copied
Python DLL. The original-install backups remain mandatory for restoring replaced
shared binaries; ordinary private settings use the public contribution contract.
