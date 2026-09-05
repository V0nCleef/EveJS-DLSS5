# Release gates: DLSS5 0.5.6 + launcher 1.0.51

Status: unpublished final-version source candidate. Neither final artifact is
manually accepted. Prior 0.5.4, 0.5.5-dev and 0.5.5 results are historical evidence,
not automatic acceptance of this pair.

## Exact source and artifact checks

- [x] Select MIT for original DLSS5 project contributions with explicit
  third-party exclusions; preserve existing file-level BSD markers.
- [x] Add project LICENSE/LICENSING.md and the Microsoft header notice without
  changing bundled binaries or historical native source/provenance records.
- [x] Retain native, downloaded-component, generated-archive and tool/template
  bytes while changing only installer ownership/state handling for 0.5.6.
- [x] Store schema-5 mutable state at `<tq parent>\_evejs\dlss5\install`, reject
  reparse-point state paths and leave schema-4 root-local receipts explicit.
- [x] Fixture-test failed and successful sibling handoffs, terminal-receipt
  transition, read-only Ensure and complete rollback without live client writes.
- [ ] Independently review final manifest -> manager -> descriptor trust pins
  and the matching launcher allowlist/version map.
- [ ] Run focused final-version metadata/installer regressions and confirm
  original-byte rollback, retained history and same-runtime version migration.
- [ ] Verify the exact 38-file shipping inventory and complete ZIP member hashes.
  No tests, private paths, receipts, caches, original/reconstructed client source,
  PYC, client runtime DLL or downloaded NVIDIA/RenoDX payloads may ship.
- [ ] Build the complete matching launcher onedir ZIP and independently verify
  source scope, retained old trust/uninstall support and non-DLSS behavior.
- [ ] Record the exact final package/launcher hashes before manual handoff.

## Manual acceptance

- [ ] User tests the exact final 0.5.6 package and matching launcher 1.0.51.
- [ ] Record the actual settings/routes tested; do not infer an unperformed
  graphics matrix, hardware matrix or longer-session pass.
- [ ] Retain standalone installation/uninstallation coverage as well as
  launcher-mod detection, enabled state and its uninstall workflow.
- [ ] Any later package or launcher change requires testing its new exact
  artifact again, even if the emitted runtime bytes are identical.

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

- [ ] Freeze final docs, versions, trust pins and artifact hashes.
- [ ] Record user acceptance of the exact final artifacts.
- [ ] Obtain separate explicit approval before commit, tag, upload, publish
  or release. A passing test alone does not authorize any of these actions.
