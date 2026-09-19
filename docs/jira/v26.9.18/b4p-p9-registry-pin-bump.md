---
id: b4p-p9-registry-pin-bump
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "autofde-lab: bump the wasm registry pin 282fae4 -> reconciled e90928d and re-earn the receipts bound to it (the b4p-f5-05 scope-4 own-ticket)"
standing: BLOCKED
---
Worktree: ~/autofde-lab-wt/p9 (branch chore/registry-pin-e90928d, from
~/autofde-lab master @ fe81a552). Read beam4pm
docs/jira/v26.9.17/_CONTEXT.md + b4p-f5-05 scope 4.
1. Evidence the drift: src/autofde_lab/wasm/_registry.py:172
   revision="282fae46..." vs ferroplan origin/main (now e90928d after the
   b4p-f5-05 reconciliation; fetch ~/ferroplan). Record
   src/autofde_lab/_model.py:202's source_revision binding.
2. Bump the pin to e90928d; rebuild the wasm artifact the registry serves
   (discover the build path — likely wasm/ or Justfile recipe; the wasm
   build is `-p ferroplan-wasm --target wasm32-wasip1`).
3. Re-earn receipts: find the lab's own tests/receipts bound to the pin
   (grep tests/ for source_revision / registry) and run them green on the
   new pin. Any receipt that CANNOT re-earn is filed as a finding, never
   papered over.
4. Error-code parity check: the reconciliation renamed FP_HDDL_TIMEOUT ->
   FP_TIMEOUT and FP_HDDL_WORKER_PANIC -> FP_WORKER_PANICKED and added
   FP_HDDL_ROOT_MISMATCH (see beam4pm OP-DIFF.md on branch
   chore/engineop-ferroplan-prep). Grep the lab for the old names; update
   mappings; file any lab-side assertion of old names as a re-derived flip.
Gates: pin bump diff; rebuilt artifact digest; receipts re-earned green
(command+exit); old-code-name grep clean or re-derived; receipt. NO push.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T23:30:00Z | ALIVE | autofde-lab-wt/p9 `chore/registry-pin-e90928d @ 34cd4daee3bfe9f1aecd1a608a3ee7c7b662125f` (base master fe81a552) | PIN: _registry.py:172 282fae46... -> e90928d7b0687a959831553c4eacca3d75ca6c88 (drift: ancestor, 431 behind ferroplan origin/main). ARTIFACT: lab serves a C-template federation stub (build.py rebuild_verify), NOT the cargo module — rebuilt all 16 stubs with llvm@17 17.0.6 (only local wasm32-capable clang; Apple clang no wasm32 target, llvm@21 no wasm-ld), ferroplan.wasm sha256 c94569b5227e2674ab2b2db45f798627404b27431880a7c1b73a30b5db91aa16 size 5601, digests re-registered from rebuild-report.json, both zips repacked deterministically (base 14 incl wasm4pm-compat, interop 2), 16/16 zip==rebuild==registered. RECEIPTS: pytest tests/test_chatman_wasm.py 12 passed exit 0; rebuild_verify ALIVE 16/16 exit 0; node-executed ferroplan admit receipt subject.source_revision == e90928d (observed); forged old-pin receipt refused at _model.py:202 (negative falsifier). FINDINGS (pre-existing, repaired, full detail in worktree WAVE-RECEIPT.md): (1) chatman-ecosystem-wasm.zip committed TRUNCATED at creation 3672d3fc (10320 B, 4 LFH, 0 central dir, 0 EOCD; test file FAILED at source on old pin; 3/4 recoverable entries byte-matched registered digests); (2) legacy digests unreproducible locally (llvm@17 gives 5600 B vs 6131 registered old stub); (3) venv editable finder redirects `import autofde_lab` to ~/autofde-lab before PYTHONPATH — first rebuild silently embedded OLD pin, caught via old-stub digest match, redone with conftest redirect. NAME SWEEP: FP_HDDL_TIMEOUT/FP_HDDL_WORKER_PANIC/FP_HDDL_ROOT_MISMATCH/FP_TIMEOUT/FP_WORKER_PANICKED = 0 hits in src/ + tests/ — lab has no FP_* mapping, nothing to re-derive. 比 honest: 0/33 lines pack-rendered (all values receipt-echoed machine output, hand-transcribed; one 63-char digest typo caught by registry validation and corrected against receipt). NO push. | merge to autofde-lab master (tree owner); optional: record llvm@17 provenance in lab docs/chatman-ecosystem-wasm.md |
| 2026-09-18T22:30:00Z | ALIVE | autofde-lab-wt/p9 chore/registry-pin-e90928d @ 34cd4da (base master fe81a552; NO push) | Pin 282fae4 -> e90928d (old pin ancestor, 431 behind). 16 stubs rebuilt deterministically (llvm@17; ferroplan.wasm c94569b5); digests re-registered; receipts re-earned: pytest 12/0, rebuild_verify ALIVE 16/16; forged old-pin receipt REFUSED (negative falsifier). FINDINGS: chatman-ecosystem-wasm.zip committed truncated at creation 3672d3fc (digest registry still genuine — 3/4 byte-matched); legacy digests unreproducible -> full re-registration; venv editable-finder silently redirected imports to ~/autofde-lab (first rebuild embedded old pin — caught via digest, redone). Lab serves a C-template federation stub, not the cargo module — ticket's cargo assumption N/A. FP_* name sweep: 0 hits, nothing to re-derive. 比: 0/33 manufactured (receipt-echoed transcription, one typo caught by registry validation) | merge = tree owner's cut |
