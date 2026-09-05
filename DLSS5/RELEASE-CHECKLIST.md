# Release gates: DLSS5 0.5.7 + launcher 1.0.52

Status: published hotfix pair, manually accepted on 2026-09-05. Prior
0.5.6/1.0.51 results remain historical evidence rather than acceptance of this
pair.

## Exact source and artifact checks

- [x] Select MIT for original DLSS5 project contributions with explicit
  third-party exclusions; preserve existing file-level BSD markers.
- [x] Add project LICENSE/LICENSING.md and the Microsoft header notice without
  changing bundled binaries or historical native source/provenance records.
- [x] Retain the complete 0.5.6 payload and receipt contract while changing only
  read-only validation of the user-controlled `NeuralUplift` Boolean.
- [x] Store schema-5 mutable state at `<tq parent>\_evejs\dlss5\install`, reject
  reparse-point state paths and leave schema-4 root-local receipts explicit.
- [x] Fixture-test failed and successful sibling handoffs, terminal-receipt
  transition, read-only Ensure and complete rollback without live client writes.
- [x] Independently review final manifest -> manager -> descriptor trust pins
  and the matching launcher allowlist/version map.
- [x] Run focused final-version metadata/installer regressions and confirm
  original-byte rollback, retained history and same-runtime version migration.
- [x] Verify the exact 38-file shipping inventory and complete ZIP member hashes.
  No tests, private paths, receipts, caches, original/reconstructed client source,
  PYC, client runtime DLL or downloaded NVIDIA/RenoDX payloads may ship.
- [x] Build the complete matching launcher onedir ZIP and independently verify
  source scope, retained old trust/uninstall support and non-DLSS behavior.
- [x] Record the exact final package/launcher hashes before manual handoff.

## Manual acceptance

- [x] User tests the exact final 0.5.7 package and matching launcher 1.0.52.
- [x] Record the actual settings/routes tested; do not infer an unperformed
  graphics matrix, hardware matrix or longer-session pass.
- [x] Retain standalone installation/uninstallation coverage as well as
  launcher-mod detection, enabled state and its uninstall workflow.
- [x] Any later package or launcher change requires testing its new exact
  artifact again, even if the emitted runtime bytes are identical.

Accepted route: existing 0.5.6 client-scoped installation, package-only update
to 0.5.7 under EveJS v0.12.7.1, Launcher 1.0.52, persisted
`NeuralUplift=0`, and a successful repeat character launch after restarting the
server stack. No broader graphics or hardware matrix is claimed.

Accepted artifacts:

- `EveJS-DLSS5-0.5.7.zip` — SHA-256
  `B85DDAE6A32004BBD4B3A75C341314A19FAEE4C5381A5E17C3E80548187A3BE1`
- `EveJS-Launcher-V1.zip` — SHA-256
  `67D2D8FBC79F6FAA27851C57460CF6994B983289B8E9DBBB7D4546C303280473`

The user controls all game/launcher UI. Agree test scope with the user; no
automatic full matrix or screen control is authorized. Preserve accepted
packages, rollback state and real playthrough data throughout.

## Known coverage and safety limits

Historical targeted runtime checks cover DLSS/Off/FSR transitions, F6 state,
two-client isolation, exit ordering, standalone rollback/stock-client login
and additional user-directed launcher/in-game checks. The native/V12 runtime
is unchanged here. Broader graphics combinations and other hardware remain
unperformed or unclaimed; the NVIDIA overlay FPS counter was not reliable
evidence of per-client frame rate during earlier multi-client runs.

- [ ] Document/evaluate forced helper termination, abandoned mutex, stale
  partial-file recovery and launcher cancellation separately from ordinary
  exceptions and mock interrupted downloads.
- [ ] Retain the short-path limitation. Deep Windows process-launch paths are
  not accepted; do not claim that extended file paths solve every launch limit.
- [ ] Account for first preparation's three bounded downloads and two bounded
  generation stages within the launcher's operation timeout.
- [ ] Verify source/rights uncertainties and component notice mapping remain
  accurately disclosed; MIT for own contributions is not blanket legal clearance.

Historical build-time statements in source/reshade are preserved as originally
recorded. They must not be mistaken for a current final-artifact acceptance log.

## Publication authorization

- [x] Freeze final docs, versions, trust pins and artifact hashes.
- [x] Record user acceptance of the exact final artifacts.
- [x] Obtain separate explicit approval before commit, tag, upload, publish
  or release. A passing test alone does not authorize any of these actions.
