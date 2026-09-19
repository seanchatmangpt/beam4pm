---
id: b4p-p4-sa2a-admit-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: sa2a admit (§64 admission court) cross-validated vs beam4pm's DeviationAdmission on real candidate assertions"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p4 (branch parity/sa2a-admit). Read _CONTEXT.md.
1. `autofde sa2a admit --help`; admit real candidates for real: use beam4pm
   ontology.ttl facts (admitted bpm:RecordType facts) as positive controls
   and deliberately-forged facts as negative controls.
2. Run beam4pm's BeamPM.DeviationAdmission (see its test file for the real
   API) on equivalent candidates.
3. Cross-validation table: candidate | lab verdict | beam4pm verdict |
   class match? Attribute divergences (the two courts guard different laws:
   §64 semantic admission vs beam4pm deviation admission — the parity claim
   is CONSENT on accept/refuse boundaries for the shared cases, not
   identity).
4. Document (do not implement) what a BeamPM.Dfcm.sa2a_admit/2 wrapper
   would need; add it only if it is a pure one-shot CLI passthrough.
Gates: real runs both sides (command+exit); consent table; ledger row if
wrapper added.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | PARTIAL_ALIVE | parity/sa2a-admit @ 2b12eef | Consent table: admit/empty/contract-violation CONSENT (different typed mechanisms); error-evidence divergent-verdict-consenting-consequence; forged candidates ADMITTED by lab §64 (court is evidentiary-form only — semantic gate is graphlaw validate) pinned as tripwire. sa2a_admit/2 added (57 lines, bridge carried UNTRACKED on branch — integrator synthesizes); 12/0; dfcm 16/0. Remaining: native E2E leg (wasm absent in worktrees); ledger rows via upstream re-render | coordinator integration |
