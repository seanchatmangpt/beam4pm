# beam4pm Documentation

Organized by [Diátaxis](https://diataxis.fr/): tutorials teach, how-to guides solve
a task, reference describes, explanation clarifies. Pick the quadrant that matches
what you're trying to do, not the one that sounds most complete.

## Tutorials — learn by doing

- [Getting Started with beam4pm](tutorials/getting-started.md) — clone, `just verify`, first manufactured checkout
- [Manufacture a New Record Type](tutorials/manufacture-a-new-record-type.md) — add a `bpm:RecordType`, watch it become real Erlang/Elixir/Gleam code

## How-to guides — accomplish a task

- [Regenerate One Manufactured Module Family](how-to/regenerate-one-manufactured-module.md)
- [Run GATE M2 Safely and Diagnose a Failure](how-to/run-gate-m2.md)
- [Add a New BeamPM.Pro.* Capability Module](how-to/add-a-beam4pm-pro-capability.md)
- [Debug a ggen Sync Failure](how-to/debug-a-ggen-sync-failure.md)
- [Build and Run the Docker Image](how-to/build-and-run-the-docker-image.md)

## Reference — look things up

- [BEAM4PM Automation Scripts](reference/scripts.md) — every `scripts/*.sh`, one-line purpose each
- [BeamPM.Pro Modules Reference](reference/beam4pm-pro-modules.md) — commercial-layer module API surface
- [BeamPM.Discovery and BeamPM.Precision API Reference](reference/discovery-and-conformance-api.md)
- [beam4pm Types Reference](reference/beam4pm_types_reference.md) — generated, every `bpm:RecordType`
- [Per-record-type pages](reference/types/) — generated, one page per admitted record type
- [FAQ](FAQ.md)

## Explanation — understand why

- [Why Generated Code Lives in `src/`, Not `generated/`](explanation/why-generated-code-lives-in-src.md)
- [Two Manufacturing Engines](explanation/two-manufacturing-engines.md) — Rust ggen (Tera) vs ggen_igniter (EEx)
- [Object-Centric Process Mining in beam4pm](explanation/object-centric-process-mining-in-beam4pm.md)
- [beam4pm_pro: A Commercial Layer, Not a Fork](explanation/beam4pm-pro-commercial-layer.md)

## Product and release doctrine

`docs/jira/v26.8.29/` is the authoritative architecture, product-requirements,
pricing/packaging, GTM, security, and release-gate package — start at
[`docs/jira/v26.8.29/README.md`](jira/v26.8.29/README.md).

## See Also

- `CLAUDE.md` — repository overview and command reference
- `ontology.ttl` — the RDF instance data that drives manufacturing
