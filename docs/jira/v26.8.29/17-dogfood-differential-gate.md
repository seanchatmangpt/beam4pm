# Dogfood Differential Gate: Erlang/Elixir/Oracle Agreement — v26.8.29

## Status

Gate script manufactured and exercised for real in a scratch consumer (2026-08-29): a full
green run (7/7 logs, all four implementations byte-identical after canonicalization), both
fail-closed `BLOCKED` paths, and one executed falsifier run (mutate → real `FAIL` → restore →
real `PASS`). Standing against the real repo head is `UNVERIFIED` until `scripts/oracle_check.sh`
is run from the actual beam4pm root with the real W1 oracle crate at
`qualification/rust4pm-oracle/` — the scratch runs below used a minimal wire-contract stand-in
crate at that same path, deliberately, so the harness plumbing is proven independently of W1.

## What this gate is

beam4pm has two ggen-manufactured discovery implementations of the same admitted semantics —
`src/beam4pm_discovery.erl` and `lib/beam4pm_discovery.ex`
(`BeamPM.Discovery`) — plus an external rust4pm oracle (native binary and wasm32-wasip1 module)
speaking a fixed stdin/stdout wire contract. Duplicate implementations silently diverging is the
standing risk this gate exists to catch: `scripts/oracle_check.sh` runs a seeded battery of
wire-contract logs through all FOUR implementations and asserts the resulting directly-follows
edge lists are exactly equal, per log, as canonicalized JSON bytes.

```text
seeded log (wire JSON) --+--> erlc-compiled  beam4pm_discovery  (escript)      --+
                         +--> elixirc-compiled BeamPM.Discovery (elixir -pa)   --+--> canonicalize
                         +--> rust4pm oracle, native binary     (stdin/stdout) --+    (strict shape,
                         +--> same oracle .wasm under wasmtime  (stdin/stdout) --+     sorted keys)
                                                                                  |
                                              all four byte-identical, per log <--+
```

The wire contract (fixed across streams): stdin is one JSON object
`{"case_attr_key": "<string>", "events": [<ocel_event to_map objects>]}`; stdout is
`{"edges": [{"source_activity": s, "target_activity": t, "frequency": n}, ...]}` sorted by
source then target, with nothing else on stdout; exit 0 on success, nonzero with a stderr
reason on malformed input.

## The seeded battery (deterministic, no randomness)

Seven logs, generated inline by the script (fixed literals; the large log uses a fixed-seed
LCG — pure integer arithmetic, reproducible byte-for-byte on every run):

1. `01-demo-3case` — the exact 8-event demo log from the generated discovery test courts:
   3 cases, deliberately unsorted input, one same-timestamp event-id tie, one event whose
   attributes lack the case key, one event with no attributes at all.
2. `02-single-event-traces` — four one-event cases; the empty edge list must survive all four
   serializers.
3. `03-self-loop` — duplicate adjacent activities (`a a a b a`): the `a->a` self-loop with
   frequency 2.
4. `04-interleaved` — 6 cases round-robin-interleaved in time, input order scrambled by a
   fixed permutation, plus an in-case same-timestamp tie broken by `event_id`.
5. `05-missing-case-attr` — the skip rule in all three shapes: attributes present but key
   absent, attributes `{}`, and attributes field absent entirely. All must be skipped.
6. `06-large-seeded` — 150 events, 12 cases, LCG seed `26082900`, injected timestamp ties and
   periodically dropped case keys; 25 distinct edges.
7. `07-unicode-escapes` — multibyte UTF-8, quotes, backslashes and tabs in activity names and
   case ids; exercises escaping and byte-order edge sorting in all four serializers.

Logs 01–05 additionally carry hand-derived expected edge lists; the gate anchors the oracle's
canonical output against them, so "all four agree on the wrong answer" is falsified for the
hand-checkable logs (see limits below for the other two).

## What the gate proves

- The generated Erlang and generated Elixir discovery implementations, and the oracle in both
  native and wasm form, compute identical `dfg_from_traces(traces_from_events(...))` edge
  multisets — same pairs, same frequencies — on every log in the battery, verified as
  byte-identical canonical JSON (real `cmp`, not structural hand-waving).
- Each implementation's raw output was already sorted by `(source_activity, target_activity)`
  — the canonicalizer rejects unsorted or duplicate-pair output rather than repairing it, so
  ordering divergence cannot hide behind the canonicalization step.
- The skip rule (no attributes / non-map attributes / key absent) and the
  `(event_time, event_id)` tie-break behave identically in all four implementations.
- The oracle honors the wire contract's "nothing else on stdout" clause: any stray stdout
  bytes fail JSON parsing in the canonicalizer.
- The gate itself can detect a real defect: the falsifier below was actually executed.

## What the gate deliberately does not prove

- **Correctness beyond the anchors.** For logs 06 and 07 only agreement is checked; if all
  four implementations shared one wrong idea (a common misreading of the semantics), the gate
  passes. The five hand-derived anchors bound, but do not eliminate, this risk.
- **Conformance/fitness parity.** Only `traces_from_events` + `dfg_from_traces` are gated;
  `conformance/2` has no oracle leg here.
- **Trace-level parity.** Edges aggregate across traces; two implementations could in theory
  order traces differently and still agree on edges. (Case order cannot affect edge counts,
  so this is out of scope by construction.)
- **Non-string case ids, duplicate event ids, non-ISO timestamps.** The battery uses string
  case ids and unique event ids; behavior outside that envelope is `UNSUPPORTED` by this gate.
- **Gleam parity.** The generated Gleam discovery module is not a leg of this gate (yet).
- **Anything about the real W1 oracle's internals.** The gate holds whatever crate sits at
  `qualification/rust4pm-oracle/` to the wire contract; it does not certify that crate's own
  test standing.

## How to run

From the beam4pm repo root:

```bash
bash scripts/oracle_check.sh
```

Parameters (env): `BEAM4PM_ROOT` (default `pwd`), `ORACLE_DIR` (default
`$BEAM4PM_ROOT/qualification/rust4pm-oracle`), `ORACLE_BIN_NAME` (default: parsed from the
crate's `Cargo.toml`), `CASE_ATTR_KEY` (default `case_id`), `ORACLE_CHECK_WORKDIR` (default:
fresh `mktemp -d`; all logs, raw outputs and canonical outputs are left there for inspection).

The script builds the oracle native + wasm32-wasip1 with real `cargo` only if the artifacts are
absent, compiles the three discovery-relevant generated Erlang modules with real `erlc` and the
three generated Elixir modules with real `elixirc` (directly, not via `mix run -e`, so the gate
has no dependency on a hex/deps fetch for the unrelated Ash dependency of `beam4pm_ash.ex`),
then runs and compares all four legs per log.

Green output shape (real output from the scratch-consumer run, 2026-08-29):

```text
PASS: 01-demo-3case (erlang == elixir == oracle-native == oracle-wasm, 2 edges)
PASS: 02-single-event-traces (erlang == elixir == oracle-native == oracle-wasm, 0 edges)
PASS: 03-self-loop (erlang == elixir == oracle-native == oracle-wasm, 3 edges)
PASS: 04-interleaved (erlang == elixir == oracle-native == oracle-wasm, 4 edges)
PASS: 05-missing-case-attr (erlang == elixir == oracle-native == oracle-wasm, 2 edges)
PASS: 06-large-seeded (erlang == elixir == oracle-native == oracle-wasm, 25 edges)
PASS: 07-unicode-escapes (erlang == elixir == oracle-native == oracle-wasm, 6 edges)
== oracle_check: 7 passed, 0 failed (workdir: ...) ==
ORACLE_CHECK: PASS
```

On the 150-event log all four canonical outputs hashed to the same SHA-256
(`30862c37dd2b...4d0c35`) in that run.

## Fail-closed BLOCKED behavior (exit 2)

Mirroring `ggen-ecosystem`'s `tests/test_container_smoke.sh`: when a required real
collaborator is absent the gate reports `BLOCKED` and exits 2 — it never skips silently and
never fakes a pass. Blocked conditions: missing `cargo`, `erlc`/`escript`, `elixirc`/`elixir`,
`wasmtime` or `python3`; missing `wasm32-wasip1` std in the rustc sysroot; missing generated
source dirs; and, centrally, no crate at `qualification/rust4pm-oracle/` (or `$ORACLE_DIR`).
Both paths were actually exercised (real output, 2026-08-29):

```text
BLOCKED: rust4pm oracle crate absent at .../qualification/rust4pm-oracle (expected
Cargo.toml; provide qualification/rust4pm-oracle or set ORACLE_DIR). Fail-closed: the
gate never fakes an oracle.
EXIT=2
```

```text
BLOCKED: wasmtime is not installed / not on PATH -- cannot run any real assertion.
EXIT=2
```

Divergence and build failures are exit 1 (`FAIL`), distinct from environmental `BLOCKED` —
the same typed-failure vocabulary as the rest of the ecosystem.

## Falsifier — executed, not hypothetical

A gate that cannot fail proves nothing, so the failure mode was manufactured for real in the
scratch consumer: one line of the generated Erlang counting logic was mutated —
`count_adjacent`'s first-occurrence seed changed from `1` to `2`:

```erlang
%% original
count_adjacent([B | Rest], maps:update_with({A, B}, fun(N) -> N + 1 end, 1, Acc));
%% mutated (falsifier)
count_adjacent([B | Rest], maps:update_with({A, B}, fun(N) -> N + 1 end, 2, Acc));
```

Real gate output against the mutant (trimmed; exit code was 1, with 6 of 7 logs failing —
only the zero-edge log 02 cannot distinguish the mutant):

```text
  DIVERGENCE on 01-demo-3case: erlang != native
< {"edges":[{"frequency":2,"source_activity":"a","target_activity":"b"},
   {"frequency":1,"source_activity":"b","target_activity":"c"}]}
> {"edges":[{"frequency":3,"source_activity":"a","target_activity":"b"},
   {"frequency":2,"source_activity":"b","target_activity":"c"}]}
FAIL: 01-demo-3case (see divergence above)
PASS: 02-single-event-traces (erlang == elixir == oracle-native == oracle-wasm, 0 edges)
FAIL: 03-self-loop (see divergence above)
FAIL: 04-interleaved (see divergence above)
FAIL: 05-missing-case-attr (see divergence above)
FAIL: 06-large-seeded (see divergence above)
FAIL: 07-unicode-escapes (see divergence above)
== oracle_check: 1 passed, 6 failed (workdir: ...) ==
ORACLE_CHECK: FAIL
```

The mutated file was then restored and verified byte-identical to the repo source (`cmp`
clean), and the gate rerun green: 7/7 `PASS`, exit 0. Mutate → fail → restore → pass is the
gate's own qualification receipt.

## See Also

- `11-release-gates-receipts.md` — the gate/receipt vocabulary this differential gate slots
  into
- `14-rust4pm-reference-boundary.md` — why rust4pm is an external oracle, never a source to
  port
- `16-gate-closure-m0-m6.md` — milestone gate closure this check feeds
- `src/beam4pm_discovery.erl`, `lib/beam4pm_discovery.ex` —
  the implementations under differential test
