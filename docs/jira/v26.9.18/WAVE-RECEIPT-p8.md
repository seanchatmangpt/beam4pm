# WAVE-RECEIPT — b4p-p8-beam-bridge (v26.9.18 autofde-lab parity wave)

- Date: 2026-09-18
- Agent: P8 (session b4p-p8), worktree `/Users/sac/beam4pm-worktrees/wt-p8`, branch `parity/beam-bridge`
- Base: `36b0ed9` (merge: bump native/ferroplan submodule to reconciled post-wave-6 pin e90928d)
- Ticket: `docs/jira/v26.9.18/b4p-p8-beam-bridge.md`
- Standing: **ALIVE** — every ticket gate observed executing in this session, in this worktree.

## SHAs

- Base tree: `36b0ed9`
- Admission digests (at admission, final bytes):
  - `lib/beam4pm_autofde_bridge.ex` sha256 `26104d7ff39850d3f2c3e9de8acd3bafe23f057ebe293ff2293af80df67454b7`
  - `test/beam4pm_autofde_bridge_test.exs` sha256 `e96351f9b34c77ccf3bfb3fa42e96e9c55c537384a80e1fec500998433c3ae88`
- Commit: see `git log -1 parity/beam-bridge` (this receipt committed with the change)

## Commands + exits (all run in this session)

| Command | Exit | Evidence |
| --- | --- | --- |
| `printf '{"op":"ping"}\n{...cmca_allocate...}' \| ~/autofde-lab/.venv/bin/python3 -m autofde_lab.beam.beam_port_bridge` | 0 | protocol witness: `{"ok": true, "pong": true}` + full plan line |
| `~/autofde-lab/.venv/bin/python3 -m autofde_lab.cli cmca allocate '[...same candidates...]' --plan-id p8_witness_plan ...` | 0 | same-result witness, 1.901s wall (one interpreter) |
| `mix deps.get` | 0 | deps fetched |
| `mix compile` | 0 | clean after warning fix |
| `mix test test/beam4pm_autofde_bridge_test.exs` | 0 | **8 tests, 0 failures** (3 witnessed runs) |
| `bash scripts/gate_authorship_check.sh` | 0 | PASS — 49 admitted (42 debt), 0 findings |
| `mix test test/beam4pm_authorship_gate_test.exs` | 0 | 19 tests, 0 failures (rendered counts match real tree) |

## Protocol contract (read from `src/autofde_lab/beam/beam_port_bridge.py` @ lab master fe81a552, verified live)

- Framing: newline-delimited single-line JSON objects over stdio; exactly one reply line per request line, **in request order**; blank lines ignored by the bridge.
- Ops: `ping` -> `{"ok":true,"pong":true}`; `cmca_allocate` (budget + candidates -> `{"ok":true,"plan":{...}}`); `calculate_salience` (branch -> `{"ok":true,"salience":float}`); unknown op -> `{"ok":false,"error":"unknown_op: <op>"}`.
- Error envelope: the bridge NEVER exits on a bad request — every exception becomes `{"ok":false,"error":str,"exception_type":str}`.
- **Failed edge (recorded)**: the lab bridge has NO `fabric` ops — `fabric solve|catalog|match` cannot traverse the persistent channel as-is. The bridge's one real solve op is `cmca_allocate` (certified multifractal cascade), so that is the parity solve proven here; the one-shot comparator is the lab CLI's `cmca allocate` (same engine, same payload shape; `consequence_risk_budget` hardcoded 0.5 CLI-side, matched bridge-side).

## Parity + latency (5 calls each path, 3 witnessed runs; microseconds)

| Run | bridge call 1 (interpreter boot) | bridge calls 2-5 avg (persistent) | one-shot CLI avg (fresh interpreter per call) |
| --- | --- | --- | --- |
| 1 | 494,517 | 7,468 [6995, 5922, 8819, 8139] | 939,323 [932948, 912899, 934593, 959175, 957004] |
| 2 | 1,578,407 | 8,070 [7416, 7280, 9255, 8331] | 1,246,404 [1245410, 958425, 1011132, 1199103, 1817953] |
| 3 (loaded machine) | 972,016 | 36,696 [16448, 52758, 44214, 33367] | 2,379,240 [1405773, 1236038, 6874295, 1258666, 1121430] |

- Same result proof: bridge plan == one-shot CLI plan, exact structural equality on decoded JSON (deterministic allocator; asserted in `test/beam4pm_autofde_bridge_test.exs` "same solve returns the exact same plan through both paths").
- Persistent channel wins after call 1 in every run (~100x on idle machine; ~65x loaded). The test asserts `steady_avg < one_shot_avg`.

## Kill-and-recover evidence

`System.cmd("kill", ["-9", os_pid])` mid-session, then:

```
20:39:18.669 [debug] BeamPM.AutofdeBridge port exited (status 137); restarting on demand
```

- status 137 = 128+9 (SIGKILL) received via the port's `:exit_status`; pending/queued waiters get `{:error, :bridge_down}`.
- GenServer process stays alive (`Process.alive?` asserted); `os_pid` returns nil after death.
- Next `ping` lazily boots a fresh interpreter; `os_pid` differs from the killed pid; round-trip succeeds (asserted). Also proven: explicit `restart/1` (fresh pid), and kill-race safety (`Port.command` rescue -> `{:error, :bridge_down}` -> lazy reopen).

## Files (all in this worktree)

- NEW hand-authored `lib/beam4pm_autofde_bridge.ex` — GenServer-wrapped BEAM Port: framed JSON-lines request/reply with per-request timeout, FIFO waiter queue with ordering-poison semantics, `{:error, :bridge_down}` on port death, lazy + forced (`restart/1`) interpreter restart; one-shot CLI comparator (`oneshot_cmca_allocate/4`) using BeamPM.Dfcm's exact CLI resolution chain.
- NEW `test/beam4pm_autofde_bridge_test.exs` — 8 Chicago tests against the REAL interpreter (named skip when the lab checkout is absent).
- Ledger (ggen render delta, hand-applied because the vendored pack render tooling is not initialized in parity worktrees — shapes mirror the main checkout's dfcm-session delta exactly):
  - `ontology.ttl` (+2 `bpm:HandAuthoredSource` individuals: `bap:hand_authored_lib_autofde_bridge` under `native_engine_facade` 5->6/6, `bap:hand_authored_test_autofde_bridge` under `hand_authored_qualification` 35->36, ceiling raised 35->36 per the documented precedent)
  - `schema/beam4pm_hand_authored_source.tsv` (+2 rows, sorted)
  - `docs/reference/beam4pm_hand_authored_source.md` (counts 47->49 / 40->42, kind table, headings, table rows, detail sections)
  - `test/beam4pm_authorship_gate_test.exs` (rendered counts 49/42 + 2 admitted paths)
- `WAVE-RECEIPT.md` (this file)

## 比 (honest)

Delivered 産面 lines this change: ~430 (lib) + ~180 (test) = ~610, all hand-authored. `ratio = 0/610 = 0%` manufactured. No pack template family exists for a GenServer stdio port-bridge client (failed edge recorded in both admission rows); paydown plan = the sunset plans: admit the beam-bridge op surface as ontology facts and render both files from them. Ledger grows monotonically with a named owner-pack intent, not silently.

## What the operator did NOT have to write

Everything in this change: bridge module, qualification, protocol discovery, admissions, gate deltas, receipt. Operator keystrokes: zero.

## Falsifiers attempted

1. "fabric solve through the persistent bridge" — FALSIFIED: bridge exposes no fabric ops (read the source, then proved by live round-trip what it does expose). Adapted to `cmca_allocate` + `cmca allocate`, disclosed above and in the admissions.
2. "BeamPM.Dfcm is available for the one-shot leg" — FALSIFIED on this branch base: `lib/beam4pm_dfcm.ex` is untracked in the main checkout, absent from `36b0ed9` and every parity branch. One-shot leg reimplements Dfcm's exact CLI path resolution (app env `:autofde_cli_path` -> `AUTOFDE_CLI_PATH` -> `priv/bin/autofde` trampoline) with a direct lab-python fallback (the path actually taken here); recorded.
3. Determinism of the allocator — tested by running both paths on identical inputs and asserting exact equality (survives 3 runs).
4. "Maybe the bridge dies on bad requests" — tested unknown-op: typed error envelope, interpreter survives.
5. Kill race (request in flight when the interpreter dies) — handled + rescue-tested path (`Port.command` ArgumentError -> `:bridge_down`).
6. Disk-full mid-compile — freed MY worktree's redundant `_build/dev` only; no other tree touched.

## Remaining

- `lib/beam4pm_dfcm.ex` + `priv/bin/autofde` trampoline remain uncommitted in the main checkout (another session's in-flight work — not mine to commit). Integration must reconcile the two independent 47->49 ledger moves (dfcm rows + my rows; true integrated count 51, 45 debt).
- Persistent-channel fabric parity requires the LAB to extend `beam_port_bridge.py` with fabric ops (read-only law for me: `~/autofde-lab` untouched).
- `BeamPM.AutofdeBridge` is supervision-ready (`start_link/1`, lazy port open) but deliberately not inserted into `BeamPM.Application`'s tree — that shared file is hot across the parity fleet; one-line follow-up at integration.
- Full `mix test` suite not run (fleet time cost); gates run: affected file's suite + authorship gate + its rendered test.
