# 0.5.9 release verification

- Schema 3 mod package; launcher integration requires 1.0.53 or newer.
- Stable update ZIP and companion metadata carry the same mod ID and version. No EveJS server version constraint.
- Packaging checks validate the shipping allowlist, source/tool hashes and retained third-party notices.
- Isolated provider tests cover installation, private profile preparation, update, removal and original-file restoration.
- Focused copied-client checks cover rendering, physical F6, two-client isolation, DLSS transitions and interrupted settling/retry.
- Test coverage is bounded: not every GPU, device failure or combination of mods was reproduced.
- RenoDX changes from 4.70 to the pinned 7.0.0-rc8 release. The original public client variant remains supported; the second known build 3396210 client variant is now included. Bundled ReShade and NVIDIA payloads remain unchanged from 0.5.8.
- The live EVE test on RTX 5090 and NVIDIA driver 617.14 used the included EveJS 0.12.9 client variant.
- Public delivery is verified by downloading and comparing the final release assets.

Retain older release packages and recovery backups. Never publish copied client archives, user state or downloaded third-party cache material.
