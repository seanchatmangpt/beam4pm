# beam4pm migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/beam4pm
- Remote: https://github.com/seanchatmangpt/beam4pm.git (origin/main)
- Branch: main@674a316b; last commit 2026-11-08; commits: 1807; size: 6477 MB
- Languages/build: Elixir (mix.exs, mix.lock), Gleam (gleam/), Rust NIF (native/),
  rebar.config, Justfile, Makefile, ggen.toml/ggen.lock, ontology.ttl. CLAUDE.md present.
- Nested repos (submodules, see below): native/ferroplan, vendor/ggen-marketplace,
  vendor/rust4pm-powl

## Observed state
- Dirty: 19 modified tracked files — config/config.exs, mix.exs, mix.lock, ontology.ttl,
  lib/beam4pm_{a2a_agent,a2a_router,application,ocel_log_ingest,powl_model}.ex,
  docs/reference/beam4pm_hand_authored_source.md, native/ferroplan (submodule pointer),
  qualification/{fixtures/a2a/agent-card.json,gym_bridge/*.json,sa2a_e2e_qualification.exs}
- Untracked: 13 — docs/jira/v26.11.12/, lib/beam4pm_{digest,repop,repop_ocel_verifier}.ex,
  priv/repop/, test/beam4pm_{a2a_router_http,digest,repop,repop_ocel_verifier}_test.exs,
  test/fixtures/repop_ocel/ (a whole "repop" feature in flight)
- Ahead 10 / behind 0 of origin/main. Stash count: 1046 (census). Unpushed local branches: 57
  (admit-tests, automation/ws2-*, chore/ferroplan-pin-*, chore/engineop-ferroplan-prep, ...)
- Large dirs: vendor/ 3.1G (submodules), .git/ 3.0G, receipts/ 129M, native/ 37M,
  erl_crash.dump 15M, tmp/ 14M. No _build/ or deps/ present at top level.
- Submodules: native/ferroplan @e90928d (v0.28.0-15), vendor/ggen-marketplace @fa79d66b
  (v26.10.1-58), vendor/rust4pm-powl @2803959 (v0.6.1-9)

## What it is
A BEAM-first process-mining substrate whose application source is manufactured by ggen from
ontology.ttl plus a vendored ggen-marketplace pack; manufactured code lives beside
hand-authored code with per-file GENERATED headers. Includes billing/entitlement
reconciliation modules for a planned beam4pm_pro layer.

## Classification
ACTIVE (census agrees: commits within the last 8 days, in-flight feature, 10 unpushed).

## Migration risk
- Uncommitted: 19 modified + 13 untracked = an unfinished "repop/digest" feature and
  qualification fixture changes. 10 unpushed commits on main. 57 unpushed local branches.
- 1046 stashes — almost certainly contain unrecoverable fragments if the .git dir is lost.
- Submodule pointers are modified (native/ferroplan) — must be committed consistently.
- Local-only data: receipts/ (129M), tmp/, erl_crash.dump; no .env found at top level.
- Rating: HIGH

## Recommended action
COMMIT-PUSH

1. `cd /Users/sac/beam4pm && git status --porcelain && git log origin/main..main --oneline`
2. DECISION: is the repop/digest feature commit-ready? Commit it on main or a branch
   `git add lib/beam4pm_digest.ex lib/beam4pm_repop*.ex priv/repop test/beam4pm_*repop* \
    test/beam4pm_digest_test.exs test/beam4pm_a2a_router_http_test.exs test/fixtures/repop_ocel`
   plus the 19 modified paths explicitly (never `git add -A`; receipts/tmp stay out).
3. `git push origin main` then `git ls-remote origin | grep $(git rev-parse HEAD)`.
4. Push every local branch: `git push --all origin` (57 branches) and verify with
   `git branch -vv | grep -v '\[origin'` returning empty.
5. DECISION on 1046 stashes: do NOT drop. Preserve via the .git copy OR
   `git bundle create /Volumes/archive/beam4pm-full.bundle --all` — stashes are not in
   bundles, so if they matter keep the whole .git dir (3.0G) in the rsync.
6. `git submodule status` — record the three pins; new machine uses `--recurse-submodules`.
7. Before copying: `rm -rf _build deps tmp erl_crash.dump` (none of _build/deps present now;
   erl_crash.dump 15M and tmp/ 14M are safe to drop). Keep receipts/ (129M, evidence).
8. If a verbatim copy is chosen (because of stashes), exclude vendor/ (3.1G, re-cloned via
   submodules) from rsync.

## First commands on the new machine
`git clone --recurse-submodules https://github.com/seanchatmangpt/beam4pm.git && cd beam4pm`
`mix deps.get && mix compile --warnings-as-errors && mix test` ; `just check` if defined.

## See Also
- ../v26.11.12/ (previous jira dir)
- /Users/sac/docs/jira/v26.11.16/README.md (master index)
