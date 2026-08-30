## Subject

- Repository: `seanchatmangpt/beam4pm`
- Base ref: `main`
- Exact base SHA: `<sha>`
- Exact head SHA: `<sha>`

## What this changes

<!-- One or two sentences. If this regenerates anything under generated/, name the
authoritative ontology.ttl change or beam4pm-process-model-pack template change that
caused it. -->

## Generated output -- do not hand-edit

- [ ] **I did NOT edit anything under `generated/` directly.** (Required: NO. If you
      needed a change there, change `ontology.ttl` or a template in
      `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/templates/` instead
      and regenerate.)
- [ ] Any pack template change lives in the `vendor/ggen-marketplace` submodule and
      the submodule pointer in this PR is pinned to a real, pushed commit (not a
      dangling local-only commit)

## Sync verification

- [ ] I ran `rm ggen.lock && ggen sync run` from a clean lock and committed the
      resulting diff (including a no-op diff, if there was one)

```text
command: rm ggen.lock && ggen sync run
exit: <exit code>
output: <bounded evidence -- files written/unchanged from the run>
```

- [ ] I ran the determinism check: deleted `generated/erlang` and `generated/elixir`,
      re-ran `ggen sync run`, and confirmed the regenerated files are byte-identical
      to what was committed (`sha256sum` before/after)

```text
generation 1 sha256 (committed): <digest>
generation 2 sha256 (regenerated): <digest>
match: <yes/no>
```

## Language test suites

- [ ] `rebar3 eunit` passed

```text
command: rebar3 eunit
exit: <exit code>
output: <bounded evidence, e.g. "All N tests passed.">
```

- [ ] `mix test` passed

```text
command: mix test
exit: <exit code>
output: <bounded evidence, e.g. "N tests, 0 failures">
```

## New record types (if applicable)

- [ ] Added via `.github/ISSUE_TEMPLATE/new-record-type.md`'s shape, or directly as a
      `bpm:RecordType` + `bpm:Field` block in `ontology.ttl`
- [ ] `record_name` does not collide with an existing admitted record
- [ ] Every `bpm:fieldType` value is one of the closed 8-value enum
- [ ] Every `bpm:fieldRequired` value is the plain string `"true"` or `"false"`
      (never `^^xsd:boolean`)

## Source authority

- [ ] No hand-authored application/domain source was added outside the admitted
      manufacturing inputs (`ontology.ttl`, `ggen.toml`, `rebar.config`, `mix.exs`,
      `src/beam4pm.app.src`, and the vendored pack's templates) -- see
      `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`
- [ ] If a privileged source exception was used, its receipt is linked here

## Review receipt

- Falsifier: `<what would prove this change wrong>`
- Remaining known limitation or gap: `<none, or link to docs/jira/v26.8.29/15-manufacturing-slice-1-status.md>`
