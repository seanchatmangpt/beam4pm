# Gate Closure Report — M0–M6 (2026-08-29)

Continues [`15-manufacturing-slice-1-status.md`](15-manufacturing-slice-1-status.md)
(which left M3 partial, M4 `PARTIAL_ALIVE`, M5/M6 `UNKNOWN`). Everything below is a
claim about the exact heads named in the "Exact release subject" section, verified by
the commands shown — not a projection. Receipt:
`receipts/2026-08-29-gate-closure-m0-m6.json`.

## What was manufactured (all ggen output, zero hand-authored domain source)

Fifteen new Tera templates and five ggen_igniter EEx assets were added to
`beam4pm-process-model-pack` (ggen-marketplace `cc2c28ac5` + `f060a7941`), each
authored and Chicago-verified in an isolated scratch consumer before integration:

1. **Codecs** — `beam4pm_codec.{erl,ex}` + test suites: `to_map`/`from_map`/
   `encode`/`decode` per admitted record type over the OTP 27+ built-in `json`
   module and Elixir 1.18+ built-in `JSON`; unknown-record and missing-field
   refusal paths; unknown map keys dropped (atom-table safe).
2. **Discovery/conformance** — `beam4pm_discovery.{erl,ex}`:
   `traces_from_events/2` (case-attribute keying, ISO8601 time sort, event-id
   tie-break), `dfg_from_traces/1`, `conformance/2` (fitness as the fraction of a
   trace's directly-follows pairs present in the model; `precision` honestly left
   unset — not computed in this slice). All outputs constructed through the
   generated validating constructors.
3. **Gleam projection** — `generated/gleam/`: `gleam.toml`, types (disclosed
   divergences: `atom -> String`, `map -> Dict(String, String)`), the same
   discovery API, a `gleam run` demo, gleeunit tests.
4. **Roundtrip fixtures** — `beam4pm_roundtrip.{erl,ex}`: deterministic
   full/minimal samples per record; write/verify over JSON wire files.
5. **Ash projection via a second manufacturing engine** — `ggen_igniter` 26.8.30
   (hex.pm, Elixir-native ggen pipeline, oxigraph Rustler NIF engine) renders
   `generated/elixir/lib/beam4pm_ash.ex` (31 `Ash.Resource` modules on the ETS
   data layer + `BeamPM.Ash.Domain`) and 31 real Ash `create!`/`read!` CRUD
   tests from the same `ontology.ttl` through `scripts/igniter_sync.sh`.

## Gate standing (each verified by a real run on 2026-08-29)

### GATE M0 — canonical input admitted: `ALIVE`
Unchanged 31-record `bpm:RecordType` graph; both pack gates
(`010_required.rq`, `020_field_type_enum.rq`) pass under `ggen sync run`.

### GATE M1 — manufacture succeeds: `ALIVE`
`rm -f ggen.lock && ggen sync run` (ggen 26.8.18) renders all 26 Tera-template
outputs; `bash scripts/igniter_sync.sh` (ggen_igniter 26.8.30) renders the two
Ash outputs. Both exit 0.

### GATE M2 — deterministic reprojection: `ALIVE`
Two consecutive full deletions of `generated/{erlang,elixir,gleam,schema,docs}`
+ regeneration produced byte-identical output across all 27 generated files
(`shasum -a 256` double-pass diff: empty). Additionally, a **cross-engine**
identity probe: ggen_igniter/EEx renders `beam4pm_types_manifest.ex`
byte-identical to the Rust-ggen/Tera output, verified on both the oxigraph NIF
engine and the `sparql` fallback engine.

### GATE M3 — compile/type verification: `ALIVE` (Erlang, Elixir, Gleam, Ash)
- Erlang: `erlc -Werror` clean, OTP 28.3.1.
- Elixir: `mix compile --warnings-as-errors --force` clean, Elixir 1.19.5.
- Gleam: `gleam build` warning-free, gleam 1.18.1.
- Ash: the 31 manufactured `Ash.Resource` modules compile under
  `--warnings-as-errors` against real Ash 3.32.1.

### GATE M4 — executable examples: `ALIVE` (Erlang, Elixir, Gleam)
All three execute *actual process-mining behavior* — DFG discovery from a
deliberately shuffle-fed seeded log, then conformance against the discovered
model — with hard in-demo assertions (3 traces; deviant-trace fitness < 1.0):
- `escript examples/erlang/dfg_discovery_demo.erl <ebin>` → PASS
- `mix run examples/elixir/dfg_discovery_demo.exs` → PASS
- `cd generated/gleam && gleam run` → same edges/fitness printed

### GATE M5 — cross-language identity: `ALIVE`
`bash scripts/roundtrip_check.sh`: 31 records × full/minimal variants over the
JSON wire — Elixir verified all 62 Erlang-written fixtures (62 pass, 0 fail)
and Erlang verified all 62 Elixir-written fixtures (62 pass, 0 fail).
Identity asserted at the wire-semantic level (`to_map(decode(other)) ==
to_map(sample)`).

### GATE M6 — playground: `ALIVE`
From a genuine `git clone --recurse-submodules
https://github.com/seanchatmangpt/beam4pm` (not the working tree),
`bash playground/playground.sh` ran the entire fresh-user workflow — toolchain
check → submodules → `mix deps.get` → manufacture → 165/165 EUnit → 248/248
ExUnit → Gleam build/7-test/demo → both discovery demos → M5 roundtrip — and
exited 0. The first fresh-clone attempt surfaced a real defect (the script
predated mix.exs having hex deps and skipped `mix deps.get`); it was fixed
forward (`30ac658`) and the run repeated from a new fresh clone of the pushed
head.

## Crown

`BEAM4PM_GGEN_ONLY_ALIVE` — claimed **only** for the exact release subject in
the receipt (beam4pm head + ggen-marketplace `f060a7941` + ggen 26.8.18 +
ggen_igniter 26.8.30 + OTP 28.3.1 / Elixir 1.19.5 / gleam 1.18.1 on this
darwin host). A checkpoint is not a crown for any other head, and this crown
says nothing about the PI/air-gap/marketplace/RevOps gate families, which all
remain `UNKNOWN`/`BLOCKED` on external authorities.

## Known limitations carried forward (disclosed, not fixed)

All seven items from the 50-agent-swarm receipt stand (no runtime value-type
checking; unknown-key silent drop; `event_type`/`object_type` duplication;
`alignment_move` enum conflation; `ocel_attribute`/`object_attribute_change`
overlap; ok-only assertions in the older generated tests; manifest empty-list
ambiguity), plus new ones:

- `conformance/2` computes fitness only; `precision` is never set.
- Discovery treats `attributes` case-keying as the only trace notion — no
  object-centric (OCEL relationship-based) trace derivation yet.
- The Gleam projection diverges on `atom` and `map` field types (disclosed in
  generated comments); Gleam has no codec/roundtrip leg, so M5 covers
  Erlang↔Elixir only.
- The Ash projection adds a synthetic `uuid_primary_key :id` not present in
  the wire schema; Ash resources are not exercised by the roundtrip.
- Compiling `:ggen_igniter` requires a Rust/cargo toolchain (Rustler NIF) —
  a real contributor-environment constraint, fail-closed in the playground.

## See also

- [`15-manufacturing-slice-1-status.md`](15-manufacturing-slice-1-status.md) — the prior slice this closes out
- [`11-release-gates-receipts.md`](11-release-gates-receipts.md) — the gate definitions this report is scored against
- `receipts/2026-08-29-gate-closure-m0-m6.json` — the machine receipt with exact identities
