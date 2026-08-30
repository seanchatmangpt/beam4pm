# rust4pm WASM Engine in BEAM

Updated 2026-08-30. Hand-authored infrastructure reference (no ggen provenance header, same
class as `native/rf1-dfg-oracle/src/main.rs` and `native/rf2-conformance-oracle/src/main.rs`).

This document is the reference for beam4pm's embedded process-mining engine: the `process_mining`
crate (`=0.6.2`, "rust4pm") compiled to `wasm32-wasip1` and hosted inside the BEAM by
[wasmex](https://hex.pm/packages/wasmex) 0.15.1. It covers the architecture and why it is
WASM-only, the linear-memory JSON ABI (`r4pm_alloc`/`r4pm_call`/`r4pm_dealloc`), the memory
ownership contract, the Elixir/Erlang/Gleam facade matrix with each facade's honest testing
limitation, the differential-testing story against the rf1/rf2 native oracles, the three pm4py
example ports with their pinned semantics, and a Standing section separating what is proven by a
real run from what is design-specified. It is for anyone calling `BeamPM.Rust4PM`, extending the
op set, or auditing why a number the engine returns can be trusted.

## Quick Reference

| Thing | Where |
| --- | --- |
| WASM crate | `native/rust4pm-wasm/` (cdylib, `process_mining = "=0.6.2"`) |
| Build script | `scripts/rust4pm_wasm_build.sh` |
| Artifact | `native/rust4pm-wasm/target/wasm32-wasip1/release/rust4pm_wasm.wasm` |
| Elixir wrapper | `lib/beam4pm_rust4pm.ex` (`BeamPM.Rust4PM`) |
| Erlang facade | `src/beam4pm_rust4pm.erl` |
| Gleam facade | `gleam/src/beam4pm/rust4pm.gleam` |
| Engine + differential tests | `test/beam4pm_rust4pm_test.exs` |
| Facade parity tests | `test/beam4pm_rust4pm_facades_test.exs` |
| pm4py example runner | `scripts/pm4py_examples_wasm.exs` |
| pm4py fixtures | `qualification/fixtures/pm4py/` |

## 1. Architecture: One Engine, Three Facades

Binding user directive: **all process-mining computation comes from the rust4pm WASM engine**,
wrapped by BEAM. Elixir, Erlang, and Gleam are facades over the one engine — no discovery,
conformance, or statistics algorithm is reimplemented in any BEAM language. Facade code is
allowed exactly two jobs: shuttling JSON across the wasm boundary, and host-side conveniences
that carry no algorithmic content (reading a file, base64-encoding gzip bytes).

### 1.1 Why the existing wasm4pm wasm-bindgen artifact was not usable

wasm4pm already ships `wasm4pm_bg.wasm` (wasm-bindgen, built for JS hosts). Inspecting its
import section (`/Users/sac/wasm4pm/wasm4pm/pkg/wasm4pm_bg.wasm`) shows **64 imports, every one
from the `__wbindgen_placeholder__` module** — wasm-bindgen's JS glue. Those imports are
satisfied by generated JavaScript (`wasm4pm_bg.js`), not by any WASI implementation, so a
non-JS host such as wasmtime-under-wasmex cannot instantiate the module without reimplementing
the glue layer. That artifact is a browser/Node deliverable, not an embeddable engine.

### 1.2 What was built instead

The same underlying crate — `process_mining =0.6.2`, the exact version the rf1/rf2 native
oracles pin — compiled directly to `wasm32-wasip1` as a `cdylib` with
`default-features = false` (several default features do not compile for wasm32-wasip1; same
reason as `native/rf1-dfg-oracle/Cargo.toml`). The resulting module imports only
**6 `wasi_snapshot_preview1` functions** (`random_get`, `environ_get`, `environ_sizes_get`,
`fd_write`, `proc_exit`, `sched_yield`), all satisfied by wasmex's built-in WASI support with
default `%Wasmex.Wasi.WasiOptions{}` — no preopens, no glue, no JS.

Consequences of this design:

1. **Differential trust for free**: the engine and the rf1/rf2 oracles are the same crate
   version behind two compilation targets, so outputs compare exactly (see §7).
2. **No filesystem coupling**: XES and PNML content crosses the boundary by value (JSON
   string / base64), so the wasm sandbox needs no preopened directories.
3. **One process, many callers**: wasmex's store executor serializes wasm ops safely, so a
   single named engine process serves concurrent BEAM callers (see §4).

## 2. ABI Contract

Three exports, one dispatch entry point. Requests and responses are UTF-8 JSON in wasm linear
memory.

```text
r4pm_alloc(len: usize) -> ptr          allocate a boundary buffer
r4pm_call(ptr, len)    -> u64          dispatch; returns (out_ptr << 32) | out_len
r4pm_dealloc(ptr, len)                 free a boundary buffer (output buffers only -- see §3)
```

Every request carries `"op"`. Every failure returns a single-key `{"error": "<string>"}`;
per-variant alignment failures additionally embed the serde-serialized crate `AlignmentError`
(e.g. `{"SearchError":"LimitReached"}`) so the real engine error is on the wire verbatim,
never paraphrased.

### 2.1 Handles

Logs and Petri nets stay inside wasm memory behind `u64` handles from one shared monotonically
increasing counter (starting at 1). Logs and nets live in **separate maps**: a log handle
passed where a net handle is expected errors `unknown net handle N` — handles never alias
across kinds. Handles are engine-process-lifetime; see §4 for invalidation-on-restart.

### 2.2 Op table

| Op | Request (beyond `op`) | Response (success) |
| --- | --- | --- |
| `import_xes` | `content` (XES as UTF-8 string) | `{"handle": N}` |
| `import_xes_gz` | `content_b64` (base64 of `.xes.gz` bytes) | `{"handle": N}` |
| `log_stats` | `handle` | counts + sorted `activities` + top variant |
| `top_n_variants` | `handle`, `n` | `{"variants":[{activities,count,percentage}]}` |
| `discover_dfg` | `handle` | `{"edges":[{source,target,frequency}]}` |
| `discover_alphappp` | `handle`, optional `config` | `{"net_handle":N,"summary":{...}}` |
| `import_pnml` | `content` (PNML as UTF-8 string) | `{"net_handle":N,"summary":{...}}` |
| `align_variants` | `log_handle`, `net_handle`, optional `options` | per-variant alignments |
| `align_trace` | `net_handle`, `trace` (activity strings), optional `options` | moves/cost |
| `compute_fitness` | `log_handle`, `net_handle`, optional `options` | fitness aggregates |
| `activities_to_alphabet` | `handle` | `{"mapping":{...},"order":[...],"num_activities":N}` |
| `activity_position` | `handle`, `activity` | `{"positions":[[index,count]],"total":N}` |
| `free_log` | `handle` | `{"freed":true}` |
| `free_net` | `handle` | `{"freed":true}` |

Determinism pins that make outputs differentially comparable:

- `discover_dfg` edges sorted by `(source, target)` — the identical sort rf1's oracle uses,
  so decoded edge lists compare equal element-for-element including order.
- `log_stats.activities` sorted lexicographically (byte order) — matches rf1's wire.
- `top_n_variants` order = crate order (descending count); `percentage` is 0–100 scale.
- `compute_fitness` field names match the crate `FitnessResult` and rf2's wire exactly.

### 2.3 Config and options pass through serde verbatim

`discover_alphappp.config` deserializes directly into the crate `AlphaPPPConfig` (all 7 fields
required when the key is present; omit the key for `AlphaPPPConfig::default()`).
`align_*.options` deserializes into the crate `AlignmentOptions` (both `cost_fn` and
`max_states` required when present; `"max_states": null` = unbounded search). The op-level
default is `max_states: 5_000_000`, not the crate default of 100 000 — the crate default
genuinely triggers `SearchError(LimitReached)` at `receipt.xes` scale, a load-bearing quirk
inherited from `native/rf2-conformance-oracle/src/main.rs` (comment at lines 151–159).

### 2.4 Alignment move rendering (pm4py-style)

`align_variants` / `align_trace` render each crate `AlignmentMove` wasm-side as a 2-array
`[log_side, model_side]`:

| Crate move | Rendered |
| --- | --- |
| `SyncMove` at trace index i | `[activities[i], activities[i]]` |
| `LogMove` at trace index i | `[activities[i], ">>"]` |
| `ModelMove`, labeled transition | `[">>", "<label>"]` |
| `ModelMove`, silent transition | `[">>", null]` |

This is pm4py's rendering (silent model moves print as `('>>', None)`), so the alignment
example port's output is directly comparable to the pm4py example's.

### 2.5 UNSUPPORTED: discounted cost model

`process_mining 0.6.2` has exactly one cost knob: the per-move-kind `CostFunction`
(`model_move_cost` / `log_move_cost` / `sync_move_cost` / `silent_move_cost`). There is no
discounted/exponent-decay cost anywhere in the crate. pm4py's `VERSION_DISCOUNTED_A_STAR`
exponent parameter is therefore **UNSUPPORTED by the engine**. The ABI enforces this honestly:
an `options` object containing `"exponent"`, `"discount"`, or `"discount_exponent"` is
rejected with an `unsupported: discounted cost model ...` error — never silently ignored,
never approximated. The alignment example port ships standard optimal alignments and says so.

### 2.6 Known engine constraints (surfaced, not hidden)

- At most 255 tokens per place (`TokenCount = u8` in the crate's Petri-net type).
- Alignment requires the net to carry `initial_marking` and `final_markings`; a PNML without
  them imports fine but alignment fails with the crate's `NoInitialMarking`/`NoFinalMarking`,
  serialized verbatim. `import_pnml`'s `summary` reports `has_initial_marking` and
  `num_final_markings` so callers can check before aligning.
- `compute_fitness` propagates the **first** per-variant error (crate behavior): one variant
  hitting `LimitReached` fails the whole fitness op with that error on the wire.
- `alphappp_discover_petri_net` prints progress lines to fd 1 inside wasm. Under default
  WASI options these land on the host's stdout; the ABI is unaffected (responses travel
  through linear memory, not stdio). Attach a `Wasmex.Pipe` as stdout if the noise matters.

## 3. Memory Ownership Contract

One allocation discipline for every boundary buffer: raw `std::alloc::alloc/dealloc` with
`Layout::from_size_align(len, 1)`. This deliberately replaces the spike's
`Vec::with_capacity` + `mem::forget` pattern, whose capacity is not guaranteed to equal `len`
(freeing such a pointer with a mismatched layout is undefined behavior).

Ownership rules — who frees what:

1. Host calls `r4pm_alloc(len)` and writes the request bytes at the returned pointer.
2. `r4pm_call(ptr, len)` **consumes and frees the request buffer** at entry. The host must
   NOT dealloc the request buffer afterward (double-free). This fixes the spike's
   input-buffer leak.
3. The response buffer is **owned by the host**: read it, then call
   `r4pm_dealloc(out_ptr, out_len)` — exactly once.
4. `free_log`/`free_net` drop the Rust value; wasm linear memory itself never shrinks
   (returned pages stay with the wasm allocator for reuse). Long-lived engine processes are
   bounded by handle hygiene, not by memory shrinkage.

The packed `u64` return crosses wasmex as a **signed i64** (wasmtime reinterprets the bit
pattern; `native/wasmex/src/instance.rs:442`). The wrapper normalizes with
`Bitwise.band(packed, 0xFFFF_FFFF_FFFF_FFFF)` before shifting — exact under Elixir bignum
semantics, and only observable if wasm memory ever exceeds 2 GiB, but it is one line.

Full host-side sequence per call:

```elixir
{:ok, [ptr]} = Wasmex.call_function(pid, "r4pm_alloc", [len])
:ok = Wasmex.Memory.write_binary(store, memory, ptr, json)      # byte offset
{:ok, [packed]} = Wasmex.call_function(pid, "r4pm_call", [ptr, len], timeout)
packed = Bitwise.band(packed, 0xFFFF_FFFF_FFFF_FFFF)
out = Wasmex.Memory.read_binary(store, memory, bsr(packed, 32), band(packed, 0xFFFFFFFF))
{:ok, []} = Wasmex.call_function(pid, "r4pm_dealloc", [out_ptr, out_len])
```

This sequence is safe under concurrency: each caller holds distinct buffers, and every
individual op is atomic on wasmex's single store executor, which runs one command at a time
in submission order (`native/wasmex/src/store_executor.rs`).

## 4. Host Process Model

**One named Wasmex process** (`BeamPM.Rust4PM.Engine`), started by `BeamPM.Rust4PM.start/0`
or supervised via the module's `child_spec/1` shim. Not per-call instances: per-call would
recompile the module and re-import the log every time — the whole point of handles is
amortizing a 29 MB XES import across many ops. The Wasmex GenServer does not block during
wasm execution (the NIF replies to the caller directly), so one pid serves concurrent
callers; actual serialization happens on the store executor's queue.

**Handle invalidation on restart.** A supervisor restart or fresh `start/0` produces a fresh
wasm store: **all previously issued handles are invalid** and callers must re-import. There
is no handle persistence across engine restarts, by design — handles are cheap references
into one process's linear memory, not durable identifiers.

**Timeout policy.** `Wasmex.call_function`'s timeout drives both the `GenServer.call`
timeout and a real wasmtime epoch interrupt: on expiry the wasm call is trapped and **the
store remains usable** for subsequent calls. The wrapper therefore threads a large per-op
timeout (default 120 000 ms for import/discover/align/fitness, 30 000 ms for cheap ops) on
`r4pm_call` only, and never `:infinity` — a timed-out call cleanly frees the executor queue,
while `:infinity` would wedge it behind a runaway alignment. `r4pm_alloc`/`r4pm_dealloc`
stay at the wasmex default (5 000 ms). No `StoreLimits` cap is set (unbounded wasm memory),
matching the 29 MB-import workload.

## 5. Facade Matrix

| Language | File | Calls | Runtime-tested by |
| --- | --- | --- | --- |
| Elixir | `lib/beam4pm_rust4pm.ex` | wasmex directly | engine test (§7) |
| Erlang | `src/beam4pm_rust4pm.erl` | `'Elixir.BeamPM.Rust4PM'` | facades test; no eunit |
| Gleam | `gleam/src/beam4pm/rust4pm.gleam` | `@external` → Elixir | facades test; no `gleam test` |

Engine test = `test/beam4pm_rust4pm_test.exs`; facades test =
`test/beam4pm_rust4pm_facades_test.exs`. The two "no X" limitations are explained below.

All three surfaces return the same shapes: `{ok, Map} | {error, Reason}` with string-keyed
(binary-keyed) maps as decoded from the engine's JSON. Gleam's externals type this as
`Result(Dynamic, Dynamic)` — Elixir's `{:ok, _}/{:error, _}` tuples ARE Gleam's `Result`
runtime representation, so no conversion shim exists or is needed.

**Why there is no `beam4pm_rust4pm_tests.erl` (eunit).** The repo's Erlang tests run under
rebar3/eunit, which compiles without Mix dependencies — wasmex is not on rebar3's code path,
so an eunit test could not start the engine. The Erlang facade is exercised for real from the
Mix context instead (`test/beam4pm_rust4pm_facades_test.exs` calls `:beam4pm_rust4pm.*` and
asserts parity with the Elixir module's results). Documented, not faked.

**Why Gleam is not runtime-tested by `gleam test`.** Same shape: `gleam test`/gleeunit runs
without wasmex on its path, and `@external` references are not resolved at compile time
anyway. The Gleam facade is compile-checked by `gleam build` and runtime-exercised only from
the Mix context: the facades test appends `gleam/build/dev/erlang/beam4pm/ebin` to the code
path and calls `:beam4pm@rust4pm.*`. If the Gleam build output is absent, that describe block
is a **named skip** (with the exact `gleam build` remedy in the skip reason), never a silent
pass. This is the first project-owned `@external` in the Gleam tree; there was no in-repo
precedent to mirror.

**Missing-wasm behavior.** If `rust4pm_wasm.wasm` is not built, both test files carry a
module-level **named skip** whose reason is `BeamPM.Rust4PM.wasm_missing_reason/0` (naming
the build script and the repo-root requirement). This is a deliberate, documented divergence
from rf1's raise-on-missing-binary idiom; fixture absence still raises, rf1-style.

## 6. pm4py Example Ports

Three examples from the pm4py checkout (`/Users/sac/chatmangpt/pm4py/examples/`) are ported
onto the engine, runnable together via `mix run scripts/pm4py_examples_wasm.exs`. Fixtures
are byte-identical copies of pm4py's canonical `running-example.xes`/`running-example.pnml`
under `qualification/fixtures/pm4py/` (provenance in that directory's README).

### 6.1 `alignment_discounted_a_star.py` → `align_trace`

The workflow ports (import log + PNML, align one trace, print moves + cost); the discount
parameter does not. The engine computes **standard optimal alignments** with the per-move-kind
`CostFunction`; the example's exponent 1.1 is UNSUPPORTED per §2.5 and the runner prints that
statement next to the real alignment. The shown alignment is a true optimal alignment from
the real engine — the one thing it is not is discounted.

### 6.2 `activities_to_alphabet.py` → `activities_to_alphabet`

Pinned semantics from `pm4py/objects/log/util/activities_to_alphabet.py:76-88`: activities
ordered by descending total event count, then remapped to letters by bijective base-26
(`A..Z, AA, AB, ...`; index 26 = `"AA"`). One deliberate, documented pin: pandas
`value_counts` tie order is quicksort-unstable across versions, so **this port pins ties to
first-occurrence order in the log** (traces in file order, events in order). A determinism
pin, not a semantic change.

### 6.3 `activity_position.py` → `activity_position`

Pinned semantics from `pm4py/stats.py:1307-1363` (`get_activity_position_summary`): for every
occurrence of the activity, its 0-based index within its trace, as a full histogram — not
min/max/avg. The wire emits `[[index, count], ...]` sorted ascending by index. An unknown
activity returns an empty histogram (`total: 0`), matching pm4py's empty dict, not an error.
The runner mirrors the pm4py example's two queries against the repo's committed
`qualification/fixtures/receipt.xes`.

Per-event iteration for 6.2/6.3 happens wasm-side over rust4pm's own `EventLog` structures
(`trace.events` + `concept:name` attribute lookup). That is data plumbing over the engine's
types, not algorithm reimplementation in a BEAM language — the directive's line is drawn at
algorithmic content, and counting/indexing the engine's own structs inside the engine is on
the right side of it.

## 7. Differential Testing

The engine is qualified by comparing it against independently compiled consumers of the same
crate version, plus hand-computed ground truth:

- **T1 — vs the rf1 oracle** (native binary, same crate): `log_stats` + `discover_dfg` on
  the 29 MB `InternationalDeclarations.xes`, asserted as decoded-JSON **exact equality** —
  cases (6449), variants (753), sorted activities, top variant, and the full 196-edge DFG
  list including order.
- **T2 — vs the rf2 oracle** (native binary, same crate): alpha+++ discovery + fitness on
  shared fixtures; fitness floats within `1.0e-9` (rf2's own tolerance), `total_costs` and
  `num_variants_aligned` exact, place/transition counts exact.
- **T3–T6 — vs hand-computed pm4py semantics**: alignment of running-example case "3"
  (cost 0, 9 sync moves, silent moves rendered `[">>", null]`), the full hand-derived
  alphabet mapping, and per-activity position histograms for `running-example.xes`.
- **T7 — the ABI itself**: handle-kind separation, error wires, and a 200-cycle
  import/free leak smoke bounded by the §3 contract.

Same crate, two compilation targets: any divergence in T1/T2 indicates a defect in the ABI
layer (the only code that differs), which is exactly what a differential test should isolate.
No mocks anywhere — every test runs the real wasm engine, real oracle binaries, and real
fixtures; absence of a prerequisite surfaces as a named skip (wasm/Gleam build) or an
rf1-style raise (fixtures/oracles).

## 8. Standing

What is proven by a real run versus what is design-specified. Vocabulary per the
no-overclaiming discipline.

**ALIVE (proven end-to-end by the spike, `/Users/sac/.scratch-rust4pm-wasm-spike/`):**

- `process_mining =0.6.2` with `default-features = false` compiles to `wasm32-wasip1` as a
  cdylib and instantiates under wasmex 0.15.1 with default WASI options.
- The spike artifact's import section holds exactly 6 `wasi_snapshot_preview1` imports
  (`random_get`, `environ_get`, `environ_sizes_get`, `fd_write`, `proc_exit`,
  `sched_yield`); the wasm-bindgen `wasm4pm_bg.wasm` holds 64 imports, all from
  `__wbindgen_placeholder__` — both counts read from the real binaries' import sections.
- The linear-memory JSON ABI round-trips at scale: `import_xes` of the 29 MB
  `InternationalDeclarations.xes` → handle in 1190 ms; `log_stats` → 6449 cases / 753
  variants / 34 activities / top variant ×1369; `discover_dfg` → 196 edges.
- wasmex 0.15.1 host semantics, read from its vendored source: non-blocking GenServer with
  direct NIF reply; single store executor serializing ops; i64-signed return encoding;
  epoch-interrupt timeouts that leave the store usable.

**UNVERIFIED at the time this document was written (specified in the D1 design; qualified by
the tests in §7 once the integrator builds and runs them):**

- The full 14-op crate at `native/rust4pm-wasm/` (the spike proved 3 of the 14 ops; the
  alignment, PNML, alpha+++, alphabet, and position ops reuse crate APIs confirmed present
  and un-feature-gated in the crate source, but had not been executed through the ABI).
- The §3 raw-alloc memory contract as implemented (the spike ran the older
  `Vec`/`mem::forget` pattern; the leak fix is new code).
- Erlang and Gleam facade parity, and the pm4py runner's printed output.

The verification command for the whole surface, from the repo root:

```bash
scripts/rust4pm_wasm_build.sh \
  && (cd native/rf1-dfg-oracle && cargo build --release) \
  && (cd native/rf2-conformance-oracle && cargo build --release) \
  && (cd gleam && gleam build) \
  && mix deps.get \
  && mix test test/beam4pm_rust4pm_test.exs test/beam4pm_rust4pm_facades_test.exs
```

A green run of that command moves every UNVERIFIED item above to ALIVE; until then, treat
this document's §1–§6 as the binding contract the implementation is qualified against, not as
evidence the implementation already conforms.

## See Also

- `native/rf1-dfg-oracle/src/main.rs` — native DFG oracle, T1's differential anchor
- `native/rf2-conformance-oracle/src/main.rs` — native conformance oracle, T2's anchor
  (source of the `max_states: 5_000_000` quirk and the stdout-silencing precedent)
- `docs/reference/beam4pm_types_reference.md` — generated process-model record types
- Spike (external): `/Users/sac/.scratch-rust4pm-wasm-spike/src/lib.rs` and
  `beam_host/spike.exs` — the proven end-to-end ancestor of this design
- pm4py checkout (external): `/Users/sac/chatmangpt/pm4py/` — semantics sources for §6
  (AGPL-3.0 upstream; fixture provenance in `qualification/fixtures/pm4py/README.md`)
