---
id: b4p-f5-08-release-boundary-for-xaas
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "beam4pm: cut a real release boundary (Hex publish) so ~/xaas can lawfully consume beam4pm beyond the OCEL HTTP forwarder"
standing: BLOCKED
branch: release/v26.9.17
worktree: (beam4pm main checkout)
created: 2026-09-17T21:40:00Z
source: ~/xaas docs/claude/diataxis/explanation/beam4pm-ex4pm-dependency-decision.md ("beam4pm is not hex-published and has no package() metadata... no release boundary") + beam4pm ace23e5 (Hex package metadata staged, version 26.9.12, "ahead of a future Hex publish")
depends: b4p-f5-04, b4p-f5-05, b4p-f5-06, b4p-f5-07
---

Read `_CONTEXT.md` first. xaas's own decision doc names the exact blocker:
beam4pm has had no release boundary, so the **sole** legal integration
surface today is OCEL-over-HTTP. Hex package metadata was staged in
`ace23e5`; no release has been cut. For Fortune 5 in xaas, the deployment
must be able to name the exact beam4pm artifact it runs — versioned,
signed, and rebuildable.

## Scope

1. Resolve the release-blocking hygiene items from this milestone's
   `cleanup-merge-plan.md` open list that touch provenance: decide the fate
   of `review/ws2-docs-types-cleanup-20260917` (268 deletions incl. 16
   `lib/*.ex` + 17 `test/*.exs`) — a release cannot ship with an
   undetermined mass-deletion branch hanging over the codebase's identity;
   and confirm the `beam4pm_ws2` vendor submodule mass-deletion is disposed
   of per that plan.
2. Version cut: bump from `26.9.12` to the v26.9.17 line **only after** the
   reconciled ferroplan pin (b4p-f5-05) is in — the released artifact must
   not embed the pre-wave-6 engine.
3. Audit `mix.exs` package includes/excludes against the repo's real
   runtime payload: the externally-built Rust oracle binaries referenced by
   absolute path and the `~/wasm4pm`-bound fixtures called out in xaas's
   decision doc must either be packaged lawfully (prebuilt, digested) or
   excluded from the package with the HTTP/deploy boundary documented — a
   Hex package that compiles only on this machine is a fabricated release
   boundary.
4. Publish to Hex (or, if publication is refused by policy, produce the
   documented OCI/tar release artifact + SHA256 manifest that xaas can pin)
   and update xaas's dependency-decision doc with the real boundary — that
   doc, not a conversation, is where xaas's consumption law lives.

## Gates

- `mix hex.publish` exit 0 (or artifact + digest manifest committed and the
  xaas decision doc updated to point at it).
- A fresh-machine install (clean `mix deps.get` + compile + `mix test`
  smoke) succeeds without absolute paths into `~/` siblings — record where
  it ran.
- Released version contains the reconciled submodule pin; `git tag` exists;
  pushed.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
