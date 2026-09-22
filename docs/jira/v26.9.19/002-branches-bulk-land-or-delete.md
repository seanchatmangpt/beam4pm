# beam4pm: triage 11 PR-less unmerged remote branches

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: origin branches not merged into `main` with no open PR
- Evidence: `git branch -r --no-merged origin/main`: automation/post-llm-governed-runtime docs/v26.8.30-pro-product-gap-closure feat/frontier-release-process-contract feat/htn-fond-dispatch feat/ocel-evidence-architecture feat/planning-closure-validator-projections fix/ferroplan-submodule-url plan/v26.9.1-jira release/v26.9.10 review/ws2-docs-types-cleanup-20260917 verify/frontier-evidence-v1

## Work to complete
- Triage each branch: land (open a PR) or delete (`git push origin --delete <branch>`). Work in batches; record decisions in History.

## Acceptance
- `git branch -r --no-merged origin/main` is empty after `git fetch --prune`.

## History
- 2026-09-19 | OPEN | survey found 11 PR-less branches | full list above | triage pending
