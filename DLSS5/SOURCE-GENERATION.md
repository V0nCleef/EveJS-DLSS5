# Local source generation — 0.5.11 / V13 guard

Package and integration payload version are both **0.5.11**. The two known
build 3396210 archives still have reviewed reference outputs. A compatible
archive with unrelated mod changes now gets a locally derived output, whose
original and installed identities are recorded in the client's rollback journal.
The RenoDX 7.0.0-rc8, ReShade 6.8.0.10/EveJS V11 and NVIDIA binaries are
unchanged from 0.5.10.

The Python 2.7 builder checks the complete input hash at each stage and requires
the exact reviewed PYC in each of the two entries it changes. It checks the
derived replacement PYC hashes before writing an output. An archive with an
incompatible graphics or startup entry is rejected before any client write.
The narrow emitter derives local names, literals and control-flow fragments from
code objects as data. Unsupported code shapes are rejected.
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

The reference manifests pin both known original and output archives. For any
other compatible archive, the manager records its actual original bytes/hash,
derives a new output in two stages, and records that output's bytes/hash for
verification, update and exact restoration. The generated archive is never
distributed in the package. The generator authenticates all authored inputs
before evaluation and closes its file handles.

## Verification boundary

The isolated build used copies of the pinned original code.ccp and Python DLL.
A disposable archive with one extra unrelated entry retained all 12,528 entry
positions and bytes outside the two patch targets; the generated ZIP passed CRC
validation. This is not proof that every other mod's changes are compatible.
Template tests model state sequences, physical F6, renderer readiness, retries
and startup scheduling. Installer tests use disposable files and mocked process
or network results. These establish source/data and control-flow behavior;
**they do not establish live GPU rendering, client stability, or release
acceptance**. Complete `RELEASE-CHECKLIST.md` before publishing.

The package contains no generated code.ccp, client source/module dump or copied
Python DLL. The original-install backups remain mandatory for restoring replaced
shared binaries; ordinary private settings use the public contribution contract.
