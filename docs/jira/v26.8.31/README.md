# beam4pm v26.8.31 — Igniter Capability Expansion Charter

Status: `PARTIAL_ALIVE[GGEN_IGNITER_BASE_CAPABILITY_TESTING_ALIVE(~/ggen_igniter, 10 files, 37 tests, 0 failures)] / UNKNOWN[BEAM4PM_ADOPTION_UNKNOWN(zero beam4pm consumption of the newly-tested capability surface as of this document)]` — see `05-verification-and-gates.md`.

## Mission

v26.8.31 closes a real, measured gap between what `ggen_igniter` (beam4pm's Elixir-native
manufacturing engine, vendored at `26.8.30` per `mix.lock`) can actually do and what beam4pm
actually asks it to do. A prior session in `~/ggen_igniter` — the research lab, distinct from
beam4pm the product — read that repo's real source and doc state, found large parts of the base
`igniter` hex library (`~> 0.8`) had never been exercised by a single test anywhere in it, and
wrote 10 new real test files (37 tests, 0 failures, re-verified) driven against real content from
`~/ex4pm`, closing that testing gap for real, on disk, in `~/ggen_igniter`.

That work answers "does this capability exist and work." It does not answer "does beam4pm use
it." As of this document set, beam4pm's entire manufacturing consumption of `ggen_igniter` remains
`scripts/igniter_sync.sh`'s pure EEx templating over 31 `Ash.Resource` modules — every capability
the new tests cover (`Igniter.Code.*`, `Igniter.Project.*`, `Igniter.Refactors.*`) is untouched by
beam4pm today. This package is requirements/design evidence and an adoption charter, not proof of
adoption: the underlying capability is proven in `~/ggen_igniter`; consumption in `~/beam4pm` has
not been executed.

## v26.8.31 document set

- `01-context-and-motivation.md` — states the measured gap (tested capability in `~/ggen_igniter`
  vs. zero beam4pm consumption of it) and why the doctrine already anticipated this second
  manufacturing engine without having verified its base library first.
- `02-product-requirements-igniter-capability-expansion.md` — the evidentiary basis (10 test
  files, 37 tests, 0 failures, four disclosed defects with workarounds) and the beam4pm-side
  adoption requirements — new capability lanes for `scripts/igniter_sync.sh` and its siblings.
- `03-known-defects-and-mitigations.md` — four real, reproduced defects in base `igniter` 0.8.3
  (none claimed fixed, none claimed to have a confirmed upstream fix), scoped to exactly which
  future beam4pm adoption paths they become load-bearing for.
- `04-jira-epics-stories-acceptance.md` — the implementable epic/story backlog (`B4PM-17xx` family,
  chosen to avoid collision with the existing `B4PMP-2600`-ceiling v26.8.29 backlog) binding exact
  subject, acceptance behavior, authority and evidence per story.
- `05-verification-and-gates.md` — one release gate per PR item in doc 02, reusing the v26.8.29
  standing vocabulary and evidence-dimension discipline verbatim, and drawing the explicit line
  between a passing research-lab test and an executed product-side gate.
- `06-script-by-script-capability-audit.md` — a per-script Igniter-candidacy audit of 25
  real `scripts/*.sh`/`*.exs` manufacturing and dogfood scripts (24 read and audited
  independently; the 25th, `ecosystem_process_mine.exs`, hit a real agent failure and is
  disclosed, not silently folded in); zero resolve to a strong adoption candidate, six resolve
  to weak-candidate and each gets a guard-rail item (PR-306..311 / B4PM-1705..1710 in docs 02
  and 04) rather than an adoption.

## Success state

`BEAM4PM_IGNITER_CAPABILITY_ADOPTION_ALIVE` requires observed execution, against exact admitted
subjects in `~/beam4pm`, of at least one `scripts/*_sync.sh` (or new sibling script) invoking
`Igniter.Code.*`, `Igniter.Project.*`, or `Igniter.Refactors.*` against real beam4pm manufacturing
inputs, with a Chicago-executed receipt bound to that exact subject and re-verified via
`just verify` or the matching gate in `05-verification-and-gates.md`. Until that execution happens
in this repository, the 37 passing `~/ggen_igniter` tests remain capability evidence only — real,
committed, and load-bearing for what beam4pm may safely adopt, but not evidence of adoption
itself. This package is design/requirements evidence; it is not a claim that beam4pm has consumed
the wider igniter capability surface.
