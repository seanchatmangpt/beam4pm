# Getting started with beam4pm (tutorial)

Your first manufactured checkout: clone, verify, and run a real
process-mining pipeline end to end. Every command in this tutorial already
exists in the repo (`CLAUDE.md`, `justfile`).

## Prerequisites

- Elixir 1.18.4-otp-27, Erlang 27.2.4 — the `.tool-versions` pin at the repo
  root (`asdf install` if you are behind)
- `ggen` on PATH (the manufacturing engine)
- git with submodule support: `vendor/ggen-marketplace` is a submodule

## 1. Clone with submodules

```console
$ git clone --recurse-submodules <this-repo-url>
$ cd beam4pm
```

`vendor/ggen-marketplace` is a git submodule. A plain clone leaves empty
vendor dirs and the first stage of `just verify` fails at `submodules`.

## 2. Run `just verify`

```console
$ just verify
```

This is the standing verification chain (`justfile:62`): `submodules ->
sync -> authorship -> engine_dispatch -> lint_truth -> mixexs_defect_audit
-> test`. The stages:

- `submodules` — `git submodule update --init --recursive`
- `sync` — `rm -f ggen.lock; ggen sync run` — manufactures `lib/`, `src/`,
  and `gleam/` from `ontology.ttl` plus the vendored pack
- `authorship` — `scripts/gate_authorship_check.sh`: hand-authored code
  under `lib/` must be an admitted `bpm:HandAuthoredSource`, or it trips
- `engine_dispatch` — `scripts/gate_engine_dispatch_check.sh`
- `lint_truth` — `scripts/gate_lint_truth.sh`
- `mixexs_defect_audit` — `scripts/mixexs_defect_audit.sh`
- `test` — `rebar3 eunit && mix test`

A green `just verify` is the repo's definition of "the manufactured source
matches its ontology and every gate passes".

## 3. Run a real pipeline

The fastest end-to-end pipeline is the telemetry-to-traces demo
(`scripts/ingest_telemetry.exs`):

```console
$ mix run scripts/ingest_telemetry.exs
```

The script's demo block attaches the default mapper, fires three real
`:telemetry.execute/3` calls for two cases, and prints:

```
== BeamPM.Ingest.Bridge demo ==
events ingested: 3
traces mined:    2
  case "case-1": ["place", "ship"]
  case "case-2": ["place"]
```

If you only wanted to see the pipeline work, you are done.

## 4. Where to next

- Deep dive on that pipeline:
  `tutorials/ingest-telemetry-into-ocel-traces.md` (same directory)
- Understand why most of `lib/` is generated:
  `../explanation/engine-and-ggen-manufacture-flow.md`
- Look up an Ash resource or a bridge API:
  `../reference/ash-resources-index.md` /
  `../reference/ingest-and-bridge-api.md`

## Troubleshooting

- **`just verify` fails at `submodules`** — run
  `git submodule update --init --recursive` and retry.
- **`ggen: command not found`** — the engine must be on PATH; this is the
  same binary the sync gate uses.
- **`mix test` failures after editing `ontology.ttl`** — regenerate first
  (`just sync`); never patch generated files by hand.

See Also: `docs/diataxis/tutorials/ingest-telemetry-into-ocel-traces.md` ·
`docs/diataxis/explanation/engine-and-ggen-manufacture-flow.md` ·
`docs/diataxis/reference/ash-resources-index.md`
