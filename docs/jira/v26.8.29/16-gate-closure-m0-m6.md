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
3. **Gleam projection** — `gleam/`: `gleam.toml`, types (disclosed
   divergences: `atom -> String`, `map -> Dict(String, String)`), the same
   discovery API, a `gleam run` demo, gleeunit tests.
4. **Roundtrip fixtures** — `beam4pm_roundtrip.{erl,ex}`: deterministic
   full/minimal samples per record; write/verify over JSON wire files.
5. **Ash projection via a second manufacturing engine** — `ggen_igniter` 26.8.30
   (hex.pm, Elixir-native ggen pipeline, oxigraph Rustler NIF engine) renders
   `lib/beam4pm_ash.ex` (31 `Ash.Resource` modules on the ETS
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
- `cd gleam && gleam run` → same edges/fitness printed

### GATE M5 — cross-language identity: `ALIVE` (Erlang, Elixir, Ash)
As scored 2026-08-29: `bash scripts/roundtrip_check.sh` over 31 records ×
full/minimal variants over the JSON wire — Elixir verified all 62
Erlang-written fixtures (62 pass, 0 fail) and Erlang verified all 62
Elixir-written fixtures (62 pass, 0 fail). Identity asserted at the
wire-semantic level (`to_map(decode(other)) == to_map(sample)`).

Updated 2026-09-05 — Ash joins the proof. Counts below are re-measured on
the tree, not carried forward from the paragraph above (which was already
stale: the admitted set has been 289 record types since well before this
change).

- **Before** (`e69d9e3`): 289 admitted record types × 2 variants = 578
  fixtures per direction; `elixir-verifies-erlang: 578 pass, 0 fail`,
  `erlang-verifies-elixir: 578 pass, 0 fail`, gate line `PASS (both
  directions)`. Ash was absent from the script: its identity with the other
  legs was asserted only per resource by the generated ExUnit tests
  (`test/beam4pm_ash/resources/*_test.exs`), which render one *full* params
  map straight from `bpm:sampleElixir` — never the minimal variant (19 of the
  289 records have a minimal fixture that differs from the full one) and never
  through the codec. Section-23 (Polyglot BEAM) standing: `PARTIAL_ALIVE`.
- **After**: a third direction, `ash-verifies-wire: 578 pass, 0 fail`, and
  the gate line reads `PASS (all three directions)`; a failure in any of the
  three exits non-zero, so M5 `PASS` now requires the fourth projection. The
  manufactured `BeamPM.AshRoundtrip` (`lib/beam4pm_ash_roundtrip.ex`,
  rendered by `ggen_igniter` from the pack's `beam4pm_ash_roundtrip.ex.eex`,
  pack 0.1.15, step 1c of `scripts/igniter_sync.sh`) takes the *same*
  Erlang-written `<record>.<variant>.erl.json` fixtures step 1 of the script
  writes, decodes each through `BeamPM.Codec.decode/2` (the cross-engine
  path), creates the generated `Ash.Resource` on the real `Ash.DataLayer.Ets`,
  reads it back by primary key (never read-all — both variants of a record
  share one table per VM) and compares field by field against
  `BeamPM.Roundtrip.sample/2`, the independent construction the other two
  legs compare against. The relation is stated per field class because
  `to_map/1` does not apply to an Ash struct (`to_known_map` stringifies
  atoms; Ash reads atoms back): attributes whose `bpm:ashTypeExpr` is in the
  `:utc_datetime` family via `DateTime.compare(ash_read,
  DateTime.from_iso8601(wire)) == :eq` (`nil == nil` for an optional datetime
  absent from the minimal wire); every other attribute via `==` against both
  the sample and the decoded struct; the synthetic `uuid_primary_key :id`
  disclosed as the *only* Ash-only public attribute and asserted so per
  record. Measured coverage on this tree: 77 of 289 resources carry 79
  `:utc_datetime_usec` attributes → 157 `DateTime.compare/2` comparisons plus
  1 `nil == nil` optional-datetime identity per sweep (full + minimal);
  Ash-only attributes beyond `:id`: none. `test/beam4pm_ash_roundtrip_test.exs`
  (manufactured, step 2c) is the same-language sweep over Elixir-written
  fixtures plus two falsifiers run for real: a fixture with one datetime
  rewritten to the no-fraction form and one with a string mutated are each
  refused naming record, variant and field. Section-23 standing after: still
  `PARTIAL_ALIVE` — Ash is now *in* the M5 wire proof, but the field-type set
  stays closed at 8, `:id` remains Ash-only, and Gleam still has no codec leg.

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
  Erlang↔Elixir plus the Ash direction — Gleam is still outside it.
- The Ash projection adds a synthetic `uuid_primary_key :id` not present in
  the wire schema — disclosed as the *only* Ash-only public attribute and
  asserted so per record by `BeamPM.AshRoundtrip`. Updated 2026-09-05 (later
  the same day): Ash *is* now exercised by the roundtrip as its third
  direction (`ash-verifies-wire`, see GATE M5 above), on top of the
  per-resource ExUnit tests against the *same* `bpm:sampleElixir` fixture the
  codec/roundtrip tests render. Ash attribute types are the vocabulary's
  `bpm:ashTypeExpr` (`datetime` → `:utc_datetime_usec`; the
  former in-template `:utc_datetime` truncated microseconds — measured
  `12:00:00.123456Z` → `~U[… 12:00:00Z]`, `DateTime.compare` `:lt`). Because
  Ash normalizes the wire string into a UTC `%DateTime{}` with microsecond
  `{n, 6}`, the Ash identity relation for datetime fields is
  `DateTime.compare(ash_read, DateTime.from_iso8601(wire)) == :eq` —
  explicitly **not** byte or struct identity (a no-fraction wire value parses
  `{0, 0}` but reads back `{0, 6}`). The shared fixture carries six
  microsecond digits so a truncating attribute type fails with `:lt`.
- Scope of the Ash leg's identity claim: the fixture class only. Ash's
  `:string` type defaults to `trim?: true` / `allow_empty?: false`
  (`deps/ash/lib/ash/type/string.ex`), so a whitespace-padded or empty string
  would **not** round-trip identically through Ash. No fixture on any leg
  (`"sample_<field>"`) exercises that class, so M5 proves identity for the
  fixture class in all three directions — the same scope the Erlang↔Elixir
  directions have always had, now stated rather than implied.
- Compiling `:ggen_igniter` requires a Rust/cargo toolchain (Rustler NIF) —
  a real contributor-environment constraint, fail-closed in the playground.

## See also

- [`15-manufacturing-slice-1-status.md`](15-manufacturing-slice-1-status.md) — the prior slice this closes out
- [`11-release-gates-receipts.md`](11-release-gates-receipts.md) — the gate definitions this report is scored against
- `receipts/2026-08-29-gate-closure-m0-m6.json` — the machine receipt with exact identities
