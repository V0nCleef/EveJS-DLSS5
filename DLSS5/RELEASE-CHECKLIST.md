# 0.5.8 release verification

- Schema 3 mod package; launcher integration requires 1.0.53 or newer.
- Stable update ZIP and companion metadata carry the same mod ID and version. No EveJS server version constraint.
- Packaging checks validate the shipping allowlist, source/tool hashes and retained third-party notices.
- Isolated provider tests cover installation, private profile preparation, update, removal and original-file restoration.
- Focused copied-client checks cover rendering, physical F6, two-client isolation, DLSS transitions and interrupted settling/retry.
- Test coverage is bounded: not every GPU, device failure or combination of mods was reproduced.
- The rendered payload is unchanged from the accepted 0.5.8-rc.4 candidate; stable packaging changes version metadata, update declaration and documentation.
- Public delivery is verified by downloading and comparing the final release assets.

Retain older release packages and recovery backups. Never publish copied client archives, user state or downloaded third-party cache material.
