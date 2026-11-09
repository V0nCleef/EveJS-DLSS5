# EveJS DLSS5 + ReShade 0.5.13 — local candidate

This unpublished candidate fixes RenoDX 7.0.0-rc8 startup NR state detection. ReShade now accepts the current authenticated intensity= report alongside the legacy upscaling= report. Private profiles normalize the RenoDX NR binding to F6 (117), including profiles inheriting NUM PLUS (107). Shared settings remain untouched.

Requires EVE client build 3396210 and EveJS Launcher 1.0.76 or newer. Close clients using the physical installation before updating. Use the journal's recorded owner context for the normal payload update, then verify from the selected server through the existing owner fallback. Preserve original-install backups and one previous payload. Never edit or rebind an installation journal.

Validated on EveJS 261108.1 with a private DX12 client: DLSS Quality, native NR ON, 600 successful feature-18 evaluations, an inspected rendered scene, and user-confirmed physical F6 OFF→ON corroborated by actual log acknowledgements and native toggle sequence 2. Guarded install/update/rollback, source/native checks, exact-version contracts and normal profile binding checks passed. NVIDIA, RenoDX and generated client-code payload bytes are unchanged; ReShade is 6.8.0.11.

Known limitation: a bounded process-local synthetic F6 probe accepted press/release but received no acknowledgement within 2.5 seconds. Automatic NR synchronization uses that export, so a graphics transition requiring an automatic NR change may refuse safely. That path remains unqualified; physical F6 and saved-DLSS startup passed. No acknowledgement or state guard was weakened.

This is a local test candidate, with no published download or FPS/image-quality/universal GPU claim. See RELEASE-CHECKLIST.md and source/reshade/BUILDING.md.
