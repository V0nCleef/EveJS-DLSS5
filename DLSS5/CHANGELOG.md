# 0.5.5 - release candidate, not published

- Install as an automatically detected launcher mod or with the standalone
  installer; verified uninstall restores original files and retains backups.
- Keep NR state and F6 control isolated per client, with automatic NR on when
  entering DLSS and off when leaving it. The accepted runtime is unchanged.
- Generate the supported client guard locally, avoiding bundled client archives
  and retained client method bodies; NVIDIA/RenoDX dependencies remain pinned
  install-time downloads.
- Add MIT licensing for original project contributions, explicit third-party
  exclusions and the Microsoft header notice; retain upstream BSD/MIT/SDK terms.
- Pair with the exact matching launcher 1.0.50. Final package/launcher artifacts
  still require fresh manual acceptance and separate approval before publication.

Upgrade safely: retain the old package and rollback state; restore the previous
installation before a fresh final-version install. Do not overlay enabled files
or edit receipt versions by hand. Shared client folders are affected for every
EveJS root using them. Local reconstruction and downloads are not legal clearance.

## Historical development records

The entries below describe their original development snapshots and tests.
They are not acceptance records for the final 0.5.5/1.0.50 artifacts.

# 0.5.5-dev - 2026-09-04 (not released)

- Reconstruct retained client-method statements from the user's pinned local
  bytecode instead of distributing the prior adapted method bodies.
- Keep the exact accepted V12 stage/final archives, native ReShade DLL and all
  downloaded runtime bytes; no renderer timing, NR/F6 policy or profile redesign.
- Authenticate both authored helpers and both source-only templates before
  helper execution, including cache hits and every generation stage. Load exact
  source bytes into private scopes; reject extra generator files and directories.
- Retain standalone entry points and install/rollback ownership semantics.
- Allow a packaging-version-only journal migration through the existing
  archived/atomic update and verification rollback path when all payload bytes
  already match; do not rewrite client files or replace original backups.
- Require the matching local v10 launcher trust update. This new installer and
  launcher need their own exact-artifact manual tests; a pass does not authorize
  publication. This is not legal clearance or a first-party license selection.

# 0.5.4-dev - historical accepted candidate, not released

The user subsequently confirmed the v9 launcher UI and additional in-game DLSS
checks passed. The earlier limited-scope record below is retained as history,
not a claim that a complete broader graphics matrix was repeated.

- Add native read-only NR state and toggle sequence scoped to the current
  process and the identified registered RenoDX module.
- Replace both Python guard copies' shared INI/log authority with the native
  API. Reject unknown state, stale/ambiguous acknowledgements and lifetime changes.
- Keep transition intent in process memory. No standalone saved character
  profiles, new Play.bat wrapper, server changes or extra managed client files.
- Preserve existing physical-F6 isolation, lifetime guard and renderer timings.
- Targeted standalone one-/two-client DLSS/Off/FSR/F6 and exit-order regression
  passed, including the previously failing second-client DLSS -> FSR switch.
  Install, verified rollback and post-uninstall stock-client login also passed.
- Matching local launcher v9 adds only this package's reviewed trust/payload
  hashes and retains older install/uninstall contracts. 874 offline launcher
  tests passed; two unrelated platform-limited tests were skipped.
- Further client/graphics testing was explicitly declined. Launcher acceptance
  is limited to UI/mod detection; its new client-launch route is not manually
  revalidated. Older launcher candidates do not gain trust from this ZIP alone.

# 0.5.3-dev - 2026-09-03

Experimental foreground-only physical F6 candidate. Exact-candidate two-client
GPU validation is pending; this is not a public release.

- Restrict physical F6 in the V10 ReShade bridge to the foreground EVE client.
  Preserve the separate process-local automatic NR injection path.
- Retain the exact V11 startup/transition generator and code.ccp contract,
  downloaded NVIDIA/RenoDX components, original executable, configuration and
  receipt/rollback model. This is not a new graphics-transition policy.
- Require a matching reviewed launcher candidate with the new manager/DLL pins
  and retained old-version trust, so installed 0.5.2 remains uninstallable.
- Uninstall 0.5.2 with its unchanged original package before installing 0.5.3.
  Keep backups, cache, receipt history and the recoverable old package; do not
  overlay enabled payloads or edit a receipt to adopt the new DLL.

No client archive, PYC, Python DLL or downloaded NVIDIA/RenoDX payload is bundled.

# 0.5.2-dev - 2026-09-03

Experimental shared-startup and transition-policy candidate. GPU validation is
pending; this is not a public release or a confirmed device-hang fix.

- Add one bounded, client-side startup worker shared by launcher and standalone
  routes. It inspects the actual renderer technique: Off/FSR disarms NR, while
  already-DLSS startup preserves the current manual NR/F6 state.
- Turn NR on after every actual transition into DLSS, regardless of the prior
  F6-off preference. Preset/shader/texture/FG changes while remaining in DLSS
  preserve the current manual choice. Leaving DLSS still disarms NR.
- Confirm NR remains off after the existing 5-second settle; unknown/on blocks
  renderer mutation. Coordinate startup and manual graphics applies with bounded
  waits and release ownership flags on failure.
- Generate the exact V11 client archive in two stages; pin and verify the
  intermediate archive, both changed PYC identities, and all five generator
  assets. Publish only the verified final archive and clean normal-failure stages.
- Add startup/tool/intermediate tampering, staged-generation cleanup, and
  disposable full-manager regression coverage. CPU-only tests do not establish
  GPU, real cooperative scheduling, multi-client or display-mode acceptance.
- Require MOD/launcher manual acceptance first, then a separate standalone
  installer/Play.bat pass. A matching reviewed launcher candidate is required.

Unchanged: native renderer and runner binaries, download URLs and artifact/signer
pins, third-party notices, installer receipt/rollback model and live game data.
No client archive, PYC, Python DLL or downloaded NVIDIA/RenoDX payload is bundled.
Restore the previous version with its original package before testing 0.5.2-dev.

# 0.5.1-dev - 2026-09-03

Experimental resource-transition guard candidate. GPU validation is pending;
this is not a public release or a confirmed device-hang fix.

- Extend NR-off protection to Shader Quality and Texture Quality changes.
- Drain queued graphics changes and their notification events before NR re-arm;
  recheck pending work after the existing 3-second settling delay.
- Preserve the user's NR preference across coalesced passes, including entry
  into DLSS from Off/FSR. Keep physical F6 and the process-local bridge unchanged.
- Bound renderer readiness to 400 polls at 25 ms; do not re-arm after timeout.
- Retain the existing 5-second NR-off and 0.5-second post-rearm delays.
- Pin the V9 candidate generator source and locally generated client archive;
  update helper, manifest and manager trust anchors for this package identity.
- Validate guard control flow with 16 CPU-only regression cases. This does not
  replace manual GPU, multi-client, display-mode or exact-launcher acceptance.

Unchanged: bundled ReShade/native runner binaries, NVIDIA/RenoDX download URLs,
artifact and signer pins, third-party notices, server/player data, and the
previous 0.5.0-dev source/artifacts. No client archive or downloaded runtime is
bundled. Uninstall the previous version with its original package before testing
a fresh 0.5.1-dev installation; no enabled in-place upgrade is claimed.

# 0.5.0-dev - 2026-09-03

Public packaging development; no live renderer deployment or GitHub release.

- Replaced the local ~1 GB lab payload tree with a five-file additive contract.
- Download exact RenoDX, DLSSNR and Streamline NR artifacts into external state;
  validate archive size/hash and full ZIP inventory before extraction.
- Enforce actual NVIDIA Authenticode and pinned signer identity rather than
  trusting a manifest's descriptive signature-status field.
- Bind the helper and manifest to the reviewed manager by SHA-256.
- Generate the accepted V8 code.ccp from the local original with a small native
  Python runner and patch builder. No CCP archive/PYC/Python DLL is bundled.
- Keep the accepted custom ReShade 6.8.0.8 binary and publish its source delta,
  exact upstream commit, toolchain record and BSD-3-Clause notice.
- Add standalone wrappers with explicit root overrides and safe config parsing;
  detect the EveJS root automatically when placed inside its mods directory.
- Share durable install state between standalone and launcher entry paths.
- Permit exact installed verification without payload cache or downloads.
- Restore originals without payload-cache dependence; keep audit/backups and
  preserve unrelated ReShade settings.
- Correct preserved-artifact receipt paths for external state directories.
- Validate cache destinations before removal/directory creation, reject reparse
  paths, and clean normal-failure staging files.
- Serialize client preparation with a physical-client-keyed, fail-fast mutex.
- Refuse differing legacy file-set receipts without automatic reinterpretation.

Not changed: native DLSS/Streamline binaries, accepted V8 transition delays,
V9 F6 bridge, live game data, active laboratory package or launcher binaries.

Known release gates: launcher first-download timeout and new trust pin,
exact-candidate manual testing, licensing of the compatibility source and
first-party code, forced-cancellation cleanup, future binary-version upgrades.
