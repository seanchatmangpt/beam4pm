---
id: b4p-p3-sa2a-card-validate-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: sa2a validate (Semantic Agent Card) run against beam4pm's REAL 1194-skill card; findings triaged; wrapper added"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p3 (branch parity/sa2a-card). Read _CONTEXT.md.
1. Boot beam4pm (alternate ports 4310/4311 to avoid collisions), fetch
   http://127.0.0.1:4311/a2a/.well-known/agent-card.json (1194 skills).
2. `autofde sa2a validate --help`; run it against the real card JSON.
   Record the verdict + every finding.
3. Triage findings: card-conformance gaps are either (a) fixed in the lab's
   validator if it mis-reads A2A v0.3 wire shapes (file upstream note in
   the lab worktree, don't fix), or (b) real beam4pm card gaps — document
   with file:line, propose the fix, do not hand-edit generated projections.
4. Add BeamPM.Dfcm.sa2a_validate_card/1 (card JSON path or map) wrapper.
Gates: real validation run (command+exit+verdict); findings triage table;
wrapper + test green; ledger row.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/sa2a-card @ d9dba35 | Real 1194-skill card (295KB, fixture committed) REFUSED by sa2a validate (UNSUPPORTED_PROFILE, exit 1); controls prove validator structural vacuity (cli.py:59-73; extension field A2A v0.3 cannot carry) — upstream note. Real beam4pm card gaps: B1 protocolVersion absent (json.ex:287), B2 supportedInterfaces 2.0-vs-0.3.0 (json.ex:253), B3 default name/version, B5 stale moduledoc — file:line + one-line fixes proposed, nothing hand-edited. sa2a_validate_card/1 added; 4/4 tripwire test; ggen sync GENUINELY rendered (22% rendered/78% hand, honest); gate PASS 50/43. INTEGRATION BLOCKER: qualification ceiling raise REQUIRED before bare sync (37>35) | ceiling raise at integration |
