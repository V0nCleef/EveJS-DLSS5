# 0.5.11 release verification

- Schema 3 mod package; launcher integration requires 1.0.68 or newer.
- Adapter manager calls use the launcher's remaining operation budget instead of a fixed 110-second cutoff.
- The generated client archive accepts unrelated ZIP entry changes while requiring the exact two reviewed source PYCs. The original and derived archive identities are recorded for rollback and verification.
- Stable update ZIP and companion metadata carry the same mod ID and version. No EveJS server version constraint.
- Packaging checks validate the shipping allowlist, source/tool hashes and retained third-party notices.
- Isolated provider tests cover installation, private profile preparation, update, removal and original-file restoration.
- Focused copied-client checks cover rendering, physical F6, two-client isolation, DLSS transitions and interrupted settling/retry.
- Test coverage is bounded: not every GPU, device failure or combination of mods was reproduced.
- Both known build 3396210 variants remain supported. RenoDX 7.0.0-rc8, ReShade and NVIDIA payloads are unchanged from 0.5.10.
- The live EVE test on RTX 5090 and NVIDIA driver 617.14 used the included EveJS 0.12.9 client variant.
- Installation and rendering with Foxtrot32's modified archive are not yet verified.
- Public delivery is verified by downloading and comparing the final release assets.

Retain older release packages and recovery backups. Never publish copied client archives, user state or downloaded third-party cache material.
