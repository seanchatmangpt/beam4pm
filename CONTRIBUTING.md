# Contributing to beam4pm

beam4pm's application source is manufactured, not written. Everything under `generated/`
is the output of `ggen sync run` acting on two real inputs: this repo's `ontology.ttl`
and the templates in the vendored `beam4pm-process-model-pack`
(`vendor/ggen-marketplace/packs/beam4pm-process-model-pack`, a git submodule). There is
no third way to change what ships. See
[`docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`](docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md)
for the full doctrine (`A = μ(O*)`); this document is the operational how-to.

## 1. Never edit anything under `generated/`

`generated/erlang/` and `generated/elixir/` are ggen output, checked in for reviewability
but not for hand-editing. A PR that touches a file under `generated/` directly, instead of
through regeneration, will be rejected — this holds for humans and LLMs alike; see
`generated/README.md` for the same rule stated at the point of temptation.

There are exactly two legitimate ways to change generated code:

1. **Edit `ontology.ttl`** to add or change an admitted `bpm:RecordType` — the normal
   path for adding a new process-mining record, adding/renaming/retyping a field, or
   changing a field's required-ness or doc string. This is a change to *this* repo.
2. **Propose a change to the pack's templates** — the 26 Tera templates under
   `templates/` (types/tests/codec/discovery/roundtrip/manifest for Erlang and Elixir,
   the five Gleam templates, JSON Schema, Markdown reference, test helper) or the
   ggen_igniter EEx assets under `igniter/` (the Ash projection and its CRUD test
   suite, rendered by `scripts/igniter_sync.sh` via `mix ggen_igniter.sync` instead of
   the Rust ggen binary) — the path for anything that isn't expressible as instance
   data under the existing `bpm:` vocabulary: a new generated function shape, a
   different constructor error format, additional test cases, a new target language.
   `vendor/ggen-marketplace` is a separate repository
   (`seanchatmangpt/ggen-marketplace`) vendored as a git submodule, so this kind of
   change is a PR against *that* repo, then a submodule bump
   (`git -C vendor/ggen-marketplace pull && git add vendor/ggen-marketplace`) here to
   pick it up.

If you're not sure which of the two a change needs: if it's a fact about a record (its
name, its fields, a field's type/doc/required-ness), it's (1). If it's a fact about *how*
records in general become Erlang/Elixir code, it's (2).

## 2. The record-type Turtle shape

The `bpm:` vocabulary (declared once, in the pack's own `ontology.ttl`, not repeated
here) has exactly two classes and eight properties between them:

| Class            | Property           | Range         | Meaning                                                              |
|------------------|---------------------|---------------|-----------------------------------------------------------------------|
| `bpm:RecordType` | `bpm:recordName`    | `xsd:string`  | snake_case record/module name, e.g. `"ocel_event"`                    |
| `bpm:RecordType` | `bpm:recordDoc`     | `xsd:string`  | one-line doc comment for the generated record/struct                  |
| `bpm:RecordType` | `bpm:hasField`      | `bpm:Field`   | one or more ordered fields belonging to this record type               |
| `bpm:Field`      | `bpm:fieldName`     | `xsd:string`  | snake_case field name, e.g. `"event_id"`                               |
| `bpm:Field`      | `bpm:fieldType`     | `xsd:string`  | one of the closed 8-value enum below                                   |
| `bpm:Field`      | `bpm:fieldDoc`      | `xsd:string`  | one-line doc comment for the generated field                           |
| `bpm:Field`      | `bpm:fieldRequired` | `xsd:string`  | the literal `"true"` or `"false"` — a validating constructor's contract |
| `bpm:Field`      | `bpm:fieldOrder`    | `xsd:integer` | 1-based stable ordering of the field within its record type            |

All eight are required. `gates/010_required.rq` in the pack refuses (returns rows for)
any `bpm:RecordType` missing `recordName`/`recordDoc`/`hasField`, or any `bpm:Field`
missing `fieldName`/`fieldType`/`fieldDoc`/`fieldRequired`/`fieldOrder`.

`bpm:fieldType` is a closed 8-value enum — `gates/020_field_type_enum.rq` refuses any
`bpm:Field` whose type isn't one of these:

| `bpm:fieldType` | Erlang       | Elixir                                    |
|-----------------|--------------|---------------------------------------------|
| `string`        | `binary()`   | `String.t()`                                |
| `integer`       | `integer()`  | `integer()`                                 |
| `float`         | `float()`    | `float()`                                   |
| `boolean`       | `boolean()`  | `boolean()`                                 |
| `datetime`      | `binary()`   | `String.t()` (ISO8601 string on the wire)   |
| `atom`          | `atom()`     | `atom()`                                    |
| `list_string`   | `[binary()]` | `[String.t()]`                              |
| `map`           | `map()`      | `map()`                                     |

Two literal-syntax traps, both learned the hard way (see `receipts/2026-08-29-first-ggen-manufactured-slice.json`):

- `bpm:fieldRequired` must be a **plain string literal**, `"true"` or `"false"` — not an
  `^^xsd:boolean`-typed literal. The templates compare it as a string.
- A Turtle numeric literal never carries an explicit `^^xsd:integer` suffix — write
  `bpm:fieldOrder 3 .`, not `bpm:fieldOrder 3^^xsd:integer .` (the bare integer already
  *is* `xsd:integer`; only a quoted string needs the suffix, e.g. `"3"^^xsd:integer`).

Only the property values above drive codegen — the IRI local name you give an individual
(`bpm:ocel_event_rt`, `bpm:ocel_event_event_id_f`, ...) is never read by any template. The
`<record>_rt` / `<record>_<field>_f` naming convention used throughout `ontology.ttl` is
there purely so a human reading the file can tell which fields belong to which record; use
it for new entries so the file stays consistent, not because ggen requires it.

### Worked example: adding a new record type

Say you want to add a `case_variant` record (a case's activity sequence, with its
observed frequency) — two required string/integer fields. Append this to `ontology.ttl`:

```turtle
# ---------------------------------------------------------------------------
# 9. case_variant
# ---------------------------------------------------------------------------

bpm:case_variant_rt a bpm:RecordType ;
    bpm:recordName "case_variant" ;
    bpm:recordDoc "One distinct activity-sequence variant observed across cases." ;
    bpm:hasField bpm:case_variant_variant_id_f ,
                 bpm:case_variant_frequency_f .

bpm:case_variant_variant_id_f a bpm:Field ;
    bpm:fieldName "variant_id" ;
    bpm:fieldType "string" ;
    bpm:fieldDoc "Stable identifier for this variant (e.g. a hash of its activity sequence)." ;
    bpm:fieldRequired "true" ;
    bpm:fieldOrder 1 .

bpm:case_variant_frequency_f a bpm:Field ;
    bpm:fieldName "frequency" ;
    bpm:fieldType "integer" ;
    bpm:fieldDoc "Number of cases that followed this exact variant." ;
    bpm:fieldRequired "true" ;
    bpm:fieldOrder 2 .
```

Nothing else needs to change. Run the regeneration loop below and you get, for free:
an Erlang `-record(case_variant, {...})` plus `new_case_variant/1` in
`generated/erlang/src/beam4pm_types.erl`, an Elixir `BeamPM.Types.CaseVariant` struct
plus `new/1` in `generated/elixir/lib/beam4pm_types.ex`, and one ok-path + one
missing-required-field EUnit test and ExUnit test each, for exactly this new record.

## 3. Regeneration and verification loop

Every change to `ontology.ttl` or to the pack's templates must be followed by this full
loop before you open a PR. All commands run from the repo root.

```sh
# 1. Force a clean regeneration (don't trust a stale lock file).
rm ggen.lock
ggen sync run

# 2. Run both real BEAM test suites against what was just generated.
rebar3 eunit
mix test

# 3. Determinism check: prove ggen is a pure function of (ontology.ttl, pack templates),
#    with no dependency on what was already sitting in generated/.
rm -rf generated/erlang generated/elixir
ggen sync run
git diff --exit-code generated/    # must print nothing and exit 0
```

If step 3's `git diff` is non-empty, the pack (or ggen itself) is not deterministic for
your change — that is a bug to fix before merging, not a diff to accept. `make verify` /
`just verify` run submodule init + the sync step (dry-run then real) + both test suites
in one shot, but always run the determinism check (step 3) by hand for anything that
touches `ontology.ttl` or the pack's templates, since neither wrapper runs it.

Toolchain this was last verified against locally: `ggen 26.8.18`, `rebar3` on OTP
28.3.1, `mix`/Elixir 1.19.5. CI (`.github/workflows/ci.yml`) pins a different but
also-compatible combination (OTP 27.2 / Elixir 1.17.3 / rebar3 3.24.0) via
`erlef/setup-beam` — either combination should pass `rebar3 eunit`/`mix test`
identically, since nothing here depends on OTP/Elixir version-specific behavior;
if you find a real discrepancy between the two, that itself is worth reporting.
Don't forget `git clone --recurse-submodules` (or
`git submodule update --init --recursive`) first — `vendor/ggen-marketplace` is a
submodule and `ggen sync run` will fail to resolve the pack without it.

## 4. The privileged-source-exception path (rare)

If something genuinely cannot be expressed as ontology data plus a template — not "this
is inconvenient to model," but "this cannot be derived from `bpm:RecordType`/`bpm:Field`
facts by any template" — direct edits under `generated/` may be admitted, but only
through the scoped, receipted exception process in
[`docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`](docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md#privileged-exception),
never as a silent hand-edit. That process requires, before any edit is made:

- the exact subject/path being touched;
- the exact intended change;
- the authorizing principal;
- a stated reason manufacturing is currently disproportionate for this case;
- the acceptance command/behavior that will prove the change works;
- a pure-commit requirement — the commit contains only the admitted manual
  intervention, nothing else riding along;
- an expiration for the privilege.

The resulting commit must be accompanied by a receipt (see
`receipts/2026-08-29-first-ggen-manufactured-slice.json` for the shape this project's
receipts take) and by a real, Chicago-style execution — a real test run, not a mock —
against the exact subject that was hand-changed, not just "the suite still passes."
Privilege terminates immediately after the intervention: the next legitimate change to
that same subject goes back through ontology/template regeneration, not through another
manual edit. If in doubt whether your case qualifies, open an issue describing what you
tried to model in `ontology.ttl` or the pack's templates and why it didn't work, rather
than opening a PR that edits `generated/` directly.

## See also

- [`README.md`](README.md) — project overview, current manufacturing status
- [`generated/README.md`](generated/README.md) — the one-line version of rule 1
- [`docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`](docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md) — full architectural doctrine and the privileged-exception section
- [`vendor/ggen-marketplace/packs/beam4pm-process-model-pack/README.md`](vendor/ggen-marketplace/packs/beam4pm-process-model-pack/README.md) — what the pack's templates generate, file by file
