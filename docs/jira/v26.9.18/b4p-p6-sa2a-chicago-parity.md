---
id: b4p-p6-sa2a-chicago-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: sa2a chicago (Canonical Chicago DoD Court) cross-walked against ash_a2a's RFC-SA2A-002 B1-B10 benchmark categories"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p6 (branch parity/sa2a-chicago). Read _CONTEXT.md.
1. `autofde sa2a chicago --help`; run the lab's Canonical Chicago DoD Court
   for real (its own fixtures/case studies under ~/autofde-lab case_studies/
   or benchmarks/ — discover).
2. Cross-walk: lab chicago categories vs ash_a2a's RFC-SA2A-002 B1-B10
   (all 10 now wired; `mix ash_a2a.chicago.bench` in ~/ash_a2a runs them).
   Table: category | lab name | ash_a2a name | measured-metric parity?
3. Run ONE shared category end-to-end on both sides (e.g. the OCEL-overhead
   class: lab's ocel evidence vs ash_a2a B9OcelOverhead) and record both
   numbers with commands+exits.
4. Do NOT modify ash_a2a (read-only) or the lab (file findings in your
   worktree notes only).
Gates: real chicago run (command+exit+verdict); cross-walk table; one
shared-category double-run with numbers; receipt.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/sa2a-chicago @ 6130d8a | Cross-walk 1:1 (same RFC-SA2A-002 B1-B10 taxonomy; 8/10 metric parity). FINDING: lab Chicago DoD Court BUILD_BROKEN — sa2a chicago exit 1 deterministic 3/3 (get_prepared None, Gate09/10 identity-binding drift past v26.9.16 tag where crown receipt shows 12/12) — upstream lab scope. Shared B9 double-run: lab 9.41 µs/event 60,886 evt/s vs ash_a2a baa135d measured with honest overhead carriers (p50 delta flagged n=10 noise). Remaining: lab court fix; B1-B8/B10 double-runs; Dfcm chicago bridge (future ticket) | lab upstream |
