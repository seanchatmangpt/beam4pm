# beam4pm: triage 21 local-only branches

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: local branches with commits not on `origin/main` and no upstream
- Evidence: `git rev-list --count origin/main..<branch>` > 0 for each: chore/a2a-capability-sweep-v26917:2 chore/engineop-ferroplan-prep:1 chore/ferroplan-pin-audit:2 chore/ferroplan-verdict-flip-audit:1 chore/ggen-consumption-max:1 feat/gall-swf-v26.9.18:3 feat/ocel-evidence-architecture:10 integration/htn-fond-hddl:3 parity/beam-bridge:1 parity/cmca-allocator:2 parity/fabric-solve:1 parity/graphlaw-triangle:1 parity/integration:25 parity/ocel-validate:3 parity/sa2a-admit:1 parity/sa2a-card:1 parity/sa2a-chicago:1 parity/sa2a-replay:1 release/v26.9.10:18 scratch/g4-proof:25 scratch/gint:1

## Work to complete
- Triage each branch: push (`git push -u origin <branch>`) or delete after confirming the commits are obsolete/recoverable. Batch the work; record decisions in History.

## Acceptance
- Every listed branch is pushed or deleted; no local-only branch with unique commits remains.

## History
- 2026-09-19 | OPEN | survey found 21 local-only branches | full list above | triage pending
