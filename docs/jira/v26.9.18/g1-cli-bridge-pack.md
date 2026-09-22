---
id: g1-cli-bridge-pack
dcterms:title: "pack facts that render typed one-shot CLI bridge wrappers (retire BeamPM.Dfcm's 9 hand-written wrappers)"
standing: BLOCKED
---
Worktree: ~/ggen-marketplace-wt/g1 (branch pack/cli-bridge). Proof scratch:
/Users/sac/beam4pm-worktrees/wt-g1-proof (point ggen.toml pack path at your
worktree; uncommitted). Read _G-CONTEXT.md.
Author bpm:CliBridge/bpm:CliCommand vocabulary + closed arg/result-shape
vocabularies + Tera/EEx template + gate (.rq refusing a rendered command
not witnessed by consumer qualification). PROOF: render ocel_validate/1 +
sa2a_replay/1 from facts; semantic diff vs hand-written (document deltas);
render ONE new wrapper from facts only (fabric cache-stats) + run it green
in the proof worktree. Pack version bump + dated description.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-19T00:30:00Z | PARTIAL_ALIVE | marketplace pack/cli-bridge @ e6cec92af (base 800b8c6c5) | bpm:CliBridge/CliCommand/CliArg/CliWitness + closed vocabularies + beam4pm_cli_bridge.ex.tmpl + witnessing gates 100/110; pack 0.1.20 (EXTEND won over protocol-integration-pack REUSE — failed edge recorded). Proof: ggen sync emitted lib/beam4pm_cli_autofde.ex (208 lines GENERATED, 0 warnings) — fabric_cache_stats/ocel_validate/sa2a_replay green vs real lab CLI; typed timeout + unwitnessed_command + vacuous-witness falsifiers refused; render caught its own template defect (fixed fact-side). 比: 79 hand lines retirable now, ~26 at full cutover; remaining ~6 wrappers need optional-keyword-flags mode. Remaining: consumer cutover commit; ExUnit template; Erlang/Gleam legs | consumer cutover at integration |
