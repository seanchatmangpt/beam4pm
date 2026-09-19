# WAVE-RECEIPT — P10 graphlaw cross-hash parity (b4p-p10)

Date: 2026-09-18 | Agent: P10 | Ticket: docs/jira/v26.9.18/b4p-p10-graphlaw-cross-hash-parity.md
Worktree: /Users/sac/beam4pm-worktrees/wt-p10 | Branch: parity/graphlaw-triangle

## Standing

**ALIVE** — every claim below is witnessed by observed execution in this session (commands + exits recorded). Permanent test green twice; flip-trip falsified; baseline suite green.

## Base SHAs

| repo | sha |
|---|---|
| beam4pm (worktree base, = main checkout commit) | `36b0ed925ba42903f05e7f08a08639ca38efc15f` |
| autofde-lab | `fe81a5526c0e977f5705d02706d7be39574f4a39` |
| praxis (third corner) | `31f149dd8a6d6b4ff25f27ba24b53759c20954c9` |
| praxis-graphlaw-wasm artifact SHA-256 | `187688d9e7e33a575713d6911d75687adb38713ed37412e211af263dfcbe0c28` (3,249,361 bytes — shasum-verified byte-for-byte this session, matches lab `graphlaw_bridge.py` pin) |
| branch head after commit | see git log below |

## Commands + exits (session-observed)

| cmd | exit |
|---|---|
| `mix deps.get` (wt-p10) | 0 |
| `mix compile` (wt-p10) | 0 |
| corner A: lab CLI direct, 10 runs (5 hashes, 3 validates, 1 hooks, 1 ontology-path refusal) | 9×0, ontology path-form 1 (`OSError: [Errno 7] Argument list too long: '/usr/local/bin/node'`), ontology inline-form 127 (shell E2BIG) — log `/tmp/p10_corner_a.log` |
| corner B: `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab mix run --no-start /tmp/p10_corner_b.exs` (all seams via `BeamPM.Dfcm` + `priv/bin/autofde` trampoline) | 0 — log `/tmp/p10_corner_b.log` |
| `MIX_ENV=dev AUTOFDE_LAB_ROOT=… mix test --no-start test/beam4pm_graphlaw_parity_test.exs` | **7 tests, 0 failures** (twice: 25.6s / 26.6s) |
| `MIX_ENV=dev AUTOFDE_LAB_ROOT=… mix test --no-start test/beam4pm_dfcm_test.exs` (baseline) | **16 tests, 0 failures** |
| `shasum -a 256 …/praxis_graphlaw_wasm_bg.wasm` | matches pin exactly |

Run notes: `--no-start` required — the app's Bandit OcelIngest listener (port 4210, `lib/beam4pm_application.ex:29`) collides across concurrent fleet worktrees. Dispatch note about ports 4317/4318 does not apply to beam4pm: those ports appear nowhere in config/, lib/, or mix files.

## Digest + verdict parity table

Corner 1 = lab CLI direct (`~/autofde-lab/.venv/bin/python3 -m autofde_lab.cli sa2a graphlaw …`).
Corner 2 = `BeamPM.Dfcm.graphlaw_*` → `priv/bin/autofde` trampoline (with `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab`).

| corpus (test/fixtures/graphlaw_parity/) | bytes | corner 1 BLAKE3 | corner 2 BLAKE3 | parity | verdict parity |
|---|---|---|---|---|---|
| shacl_violation.ttl | 202 | `6ee21817…99056` | same | MATCH | conforms=false; SHACL REFUSED "Report: 1 violations"; replay ADMITTED — identical both corners |
| shacl_conforms.ttl (control) | 158 | `9ff19b2a…5dcf1` | same | MATCH | conforms=true; SHACL ADMITTED "Report: 0 violations" — identical |
| n3_denial.ttl | 283 | `c640e44e…e9782` | same | MATCH | conforms=false; N3_DENIAL REFUSED "Found 1 denial violations", triples_out=1 — identical |
| hooks_base.ttl | 317 | `78f5fb7a…8976c` | same | MATCH | hooks status ADMITTED, verdicts/schedule/receipts [] — identical |
| hooks_event.ttl | 131 | `280589c1…7df26` | same | MATCH | (hash only) |
| admitted-graph slice (ontology.ttl: bpm: prefix + bpm:ocel_event_rt block, 413B) | 413 | `e8f9df49…7b046` | same | MATCH | also identical via direct-path, direct-inline, and bridge forms |
| ontology.ttl (repo root, 1,586,529B) | — | REFUSED (E2BIG) | REFUSED (E2BIG) | parity-of-refusal | no digest obtainable through either corner — transport ceiling, see divergence table |

Full digests (pinned in the permanent test): shacl_violation `6ee218170924e7e7d2f3ec50a471a329907a46ed6ca6be467effeb7a39499056`, shacl_conforms `9ff19b2a1e300cceb252ca51b75c1ee816657edb97bfab931be0e8758bc5dcf1`, n3_denial `c640e44ec580f156cfa000f6ccaec4a93b8892783273f2876b03ef22af1e9782`, hooks_base `78f5fb7a846c2a98cdeabc9d49604d4476ea314b8afe69e71471155c7d18976c`, hooks_event `280589c103300dd48373f290a845ed15fcdd49358ad170e6e744925fd167df26`, ontology slice `e8f9df49477b311447b75a7075c4eb30e115b8b10dbdfccb592ff4048cd7b046`.

**Result: the triangle is a DUO + engine pin, and the trampoline adds ZERO drift.** Every input both corners can carry produces identical digests AND identical verdict/stage codes. Expected divergence cause class (wasm version skew, P9/f5-05-style) did NOT occur: the artifact is content-pinned and byte-verified.

## Divergence / finding table (with attribution)

| # | finding | attribution class | evidence |
|---|---|---|---|
| 1 | No in-repo beam4pm graphlaw engine exists. Triangle resolves as DUO (lab CLI direct, BeamPM.Dfcm trampoline) + engine identity pin. The engine actually lives upstream: `/Users/sac/praxis` `crates/praxis-graphlaw-wasm/pkg/praxis_graphlaw_wasm_bg.wasm`, loaded by the lab's `sa2a/admission/graphlaw_bridge.py` under pinned SHA-256/size/import-set discipline. | architecture (upstream engine ownership) | grep of lib/, src/, vendor/, native/ at `36b0ed9` for graphlaw/praxis: zero hits |
| 2 | Transport ceiling A — E2BIG: graphlaw_bridge inlines TTL into a `node -e` script; >~1MiB content refuses at Node spawn. Repo-root ontology.ttl unhashable through BOTH corners. | lab seam (bridge transport), NOT wasm skew | corner A: `OSError: [Errno 7] Argument list too long: '/usr/local/bin/node'`, exit 1 (path form) / exit 127 (inline form, shell E2BIG); corner B: `{:cli_failed, 7}` inline / `{:cli_failed, 1}` path form |
| 3 | Transport ceiling B — stat heuristic: `sa2a/cli.py:311` `Path(content).exists()` raises ENAMETOOLONG (unignored by pathlib) for inline content with >255-char path component or >1024 total → CLI exit 1 BEFORE the engine. Bridge corner (always inline) therefore caps at ~1KB TTL; direct corner with a file path is unaffected. | lab seam (CLI content/path ambiguity), NOT wasm skew | size probe through bridge: 200/250 bytes → exit 0; 260/300/1000/31404 → exit 1 crash at cli.py:311 |
| 4 | Hooks honest verdict: WASM hook registry stays empty — `status=ADMITTED` with `verdicts=[] schedule=[] receipts=[]` is pinned as the truthful verdict (known upstream AFDE-2612 literal-decode gap), not claimed as a wiring success. | upstream praxis (`BLOCKED:UPSTREAM_PRAXIS_GRAPHLAW_LITERAL_DECODE`, pre-existing) | hooks run both corners, identical empty-registry result |
| 5 | Hash is canonical-GRAPH-based, not byte-based: a 21,641-byte slice (duplicate `@prefix bpm:` lines, which ontology.ttl re-declares hundreds of times) and the 413-byte minimal slice hash identically (`e8f9df49…`). | none (engine property, favorable) | both variants hashed via all three forms this session |

## Permanent test (flip ledger)

`BeamPM.GraphlawParityTest` — `test/beam4pm_graphlaw_parity_test.exs` (7 tests, f5-06-style flip ledger for GraphLaw):

1. hash parity + 5 digest pins (both corners live, structural equality with pins)
2. admitted-graph slice pin (deterministic runtime extraction from repo-root ontology.ttl)
3. SHACL violation + control verdict/stage-code pins (full result parity, `raw_response` dropped)
4. N3 denial verdict/stage-code pin
5. hooks full-result pin (honest empty-registry verdict)
6. third-corner artifact identity pin (SHA-256 + size of praxis wasm)
7. transport-ceiling pin (ontology.ttl yields no digest through either corner)

Run: `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab mix test --no-start test/beam4pm_graphlaw_parity_test.exs` (env var required in worktrees; main-checkout sibling default also works). Any praxis wasm rebuild, lab seam change, ontology edit, or trampoline drift trips a named FLIP assertion with re-derive-or-escalate instructions.

## Files (branch delta vs `36b0ed9`)

Authored this session (hand-written, product):
- `test/beam4pm_graphlaw_parity_test.exs` — permanent flip-ledger test
- `test/fixtures/graphlaw_parity/{shacl_violation,shacl_conforms,shacl_shapes,n3_denial,hooks_base,hooks_event}.ttl` — synthesized corpus (6 files)

Carried verbatim from main checkout's pre-existing untracked work (diff-proven byte-identical; authored + ledgered upstream in a prior session — `lib/beam4pm_dfcm.ex` is `native_engine_facade`, `test/beam4pm_dfcm_test.exs` is `hand_authored_qualification` in `schema/beam4pm_hand_authored_source.tsv`):
- `lib/beam4pm_dfcm.ex`, `priv/bin/autofde`, `test/beam4pm_dfcm_test.exs`, `qualification/fixtures/dfcm/{abcx-problem.pddl,dfcm-fond.pddl,dfcm.hddl}`
- `WAVE-RECEIPT.md` (this receipt)

lib/ was NOT modified by me: `diff` of `lib/beam4pm_dfcm.ex` and `priv/bin/autofde` against the main checkout's copies is empty. No new bridge functions. Per ticket "ledger row only if lib changed": no new lib ledger row.

## 比 (honest)

This session's product delta is 100% hand-written (0% pack-manufactured): no admitted pack or generator exists for parity-test/corpus manufacture. The pins and parity table are manufactured FROM observed engine execution (digests are engine outputs, never asserted). Ledger delta for integration: `hand_authored_qualification` pressure +1 (test/beam4pm_graphlaw_parity_test.exs; corpus fixtures are test-support data) — coordinator to fold into `schema/beam4pm_hand_authored_source.tsv` + `docs/reference/beam4pm_hand_authored_source.md` at merge (36→37 files against ceiling; no paydown plan offered by this ticket's scope).

## Environment repair (ledgered)

- `chmod 755 /Users/sac/.local/share/uv/python/cpython-3.13.9-macos-aarch64-none/bin/python3.13` — the uv-managed interpreter had lost its exec bit (mode `-rw-------`) during the fleet disk-full window (disk hit 120MiB free / 99% mid-wave), breaking `~/autofde-lab/.venv` for every consumer and making the trampoline silently fall back to Xcode python (`ModuleNotFoundError: autofde_lab`). Binary content verified intact (valid Mach-O arm64, 49,968 bytes) before repair; mode-only change; no bytes under `~/autofde-lab` written. Post-repair: venv python 3.13.9 executes, lab CLI green.
- No writes to `/Users/sac/beam4pm` or `~/autofde-lab` (both off-limits per ticket).

## Falsifiers attempted

1. Pin sensitivity: 1-byte corpus mutation (`ex:age 33`→`34`) moved digest `9ff19b2a…` → `85ede5c6…` — the flip ledger trips on real change.
2. Flakiness hunt: full suite run twice (25.6s, 26.6s) — 7/0 both; earlier intermittent failures root-caused to the uv-python exec-bit incident above, not test nondeterminism.
3. Trampoline drift: corner-2 outputs byte-compared to corner-1 on every carryable input — zero drift found (attempted falsification of "trampoline adds no drift" failed = claim holds).
4. Canonical-hash insensitivity: 21KB duplicate-prefix slice vs 413-byte minimal slice — identical digest.
5. Transport threshold: probed 200/250/260/300/1000/31404-byte inline content through the bridge — boundary located (≤250 ok, ≥260 crash at cli.py:311), confirming the finding is precise, not anecdotal.
6. "No in-repo engine" attempted falsification: greps across lib/, src/, vendor/, native/ (code, TOML, wasm dirs) for graphlaw/praxis — zero hits at `36b0ed9`; DUO conclusion stands.

## Remaining

1. autofde-lab upstream: fix `sa2a/cli.py` path-vs-content stat heuristic and stream TTL via file/stdin in `graphlaw_bridge` to lift both transport ceilings (finding recorded here; no write to the lab performed).
2. Coordinator, at integration: fold `hand_authored_qualification` row for `test/beam4pm_graphlaw_parity_test.exs` into the schema TSV + reference doc.
3. Full 1.5MB admitted-graph digest remains blocked on upstream transport fix; the runtime-extracted slice pin is the interim admitted-graph anchor and trips on any ontology edit.
4. praxis AFDE-2612 hook literal-decode gap remains upstream (hooks verdicts empty); revisit pin if praxis rebuild lands (f5-05 scope-4 style).
