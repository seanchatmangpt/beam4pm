# Case study: `BeamPM.Types.OcelEvent` validated against a real, independent downstream emitter (xaas)

Date: 2026-08-30.
Subject repo: `/Users/sac/xaas` — a real Elixir/Phoenix/Ash 3.x SaaS-marketplace platform,
unrelated to beam4pm's own codebase and not authored with beam4pm's schema in mind.

## Why this is a real external validation, not a designed-in fixture

`BeamPM.Types.OcelEvent`/`OcelObject`/`OcelRelationship` were built as this repo's own
projection of OCEL 2.0. Until now they had never been checked against an OCEL emitter this
repo didn't author. xaas independently built `Xaas.Telemetry.OcelAshEmitter`, which attaches
to Ash's real `:telemetry` events and appends one real JSON-OCEL line
(`ocel:eid`/`ocel:activity`/`ocel:timestamp`/`ocel:omap`/`ocel:vmap`) per real Ash action —
built for xaas's own OpenTelemetry correlation needs, with no knowledge of beam4pm's schema.

## What was actually run

- xaas's `test/xaas/telemetry/ocel_beam4pm_compatibility_test.exs` drives a real Ash action
  (`Xaas.Operations.CapabilityLivenessReceipt.ingest`), reads the real line
  `OcelAshEmitter` appended to its own log, maps the real JSON-OCEL keys onto beam4pm's real
  atom keys, and calls beam4pm's real, unmodified `BeamPM.Types.OcelEvent.new/1` — loaded
  read-only via `Code.require_file/2` against this repo's checkout path. No mix dependency
  was added on either side; no field, branch, or return shape in `OcelEvent.new/1` was
  assumed rather than read from `lib/beam4pm_types.ex` first.
- Result: **PASS**. `OcelEvent.new/1` accepts the mapped real xaas event and every field
  round-trips exactly, via a pure key rename (`ocel:eid → :event_id`,
  `ocel:activity → :event_type`, `ocel:timestamp → :event_time`, `ocel:vmap → :attributes`).

## The one real gap this surfaced

`ocel:omap` (JSON-OCEL's object-reference list — the standard's mechanism for saying which
objects an event touched) has **no corresponding field on `BeamPM.Types.OcelEvent`**. This
repo instead models object participation as separate records
(`OcelObject`/`OcelRelationship`), which a JSON-OCEL `ocel:omap` array does not map onto
without an explicit translation step: one `OcelRelationship` per `omap` entry, keyed by a
real qualifier, plus one `OcelObject` the first time each object id is seen. That
translator does not exist in either repo as of this case study — named here, not built.

xaas's own follow-up (`lib/xaas/telemetry/ocel_ash_emitter.ex`, commit `de303e0`) went one
step further and investigated whether a *real* instance-level object reference (not just
the acting resource's own name) could be added to `ocel:omap` at all. Their finding,
independently arrived at by reading Ash's own source
(`deps/ash/lib/ash/actions/create/create.ex`): Ash's `:stop` telemetry metadata is built
*before* the action's `do_run/4` executes, so the changeset/result — and therefore any real
foreign-key/relationship instance value — is never available to a telemetry handler at all.
This is a genuine upstream Ash constraint on any Ash-based OCEL emitter, not an xaas-local
gap; it bounds what any Ash `:telemetry`-based `omap` population can ever claim without
deeper instrumentation than the public telemetry span exposes. xaas chose to disclose
possible-but-unconfirmed relationship *types* (via `Ash.Resource.Info.relationships/1`) as
`vmap` enrichment only, explicitly not as `omap` entries — declining to misrepresent
declared schema shape as confirmed instance participation.

## Standing

- **`OcelEvent` real-world compatibility**: ALIVE — confirmed via a real, re-runnable check
  against a real, independently-built emitter.
- **`omap` → `OcelObject`/`OcelRelationship` translator**: not built (BLOCKED on nothing
  external — genuinely just unbuilt work, tracked here as a real, disclosed gap rather than
  silently dropped).
- **Instance-level object references from an Ash `:telemetry`-based emitter**: bounded by a
  real Ash constraint (metadata excludes changeset/result at `:stop` time) — any future
  Ash-sourced OCEL emitter feeding this schema inherits the same ceiling unless it
  instruments deeper than the public telemetry span.

## Cross-references

- xaas: `docs/claude/diataxis/explanation/ocel-beam4pm-compatibility.md`,
  `test/xaas/telemetry/ocel_beam4pm_compatibility_test.exs`,
  `test/xaas/telemetry/ocel_ash_emitter_test.exs`,
  `lib/xaas/telemetry/ocel_ash_emitter.ex` (commits `4358a51`, `de303e0`)
- beam4pm: `lib/beam4pm_types.ex` (`OcelEvent`/`OcelObject`/`OcelRelationship`, unmodified by
  this case study)
