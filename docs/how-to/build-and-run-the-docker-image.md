# How to Build and Run the Docker Image

This recipe builds the beam4pm product container image locally, explains what
`.dockerignore` excludes and why, and validates the local build matches CI.

## Build the image

From the repo root:

```sh
docker build -t beam4pm:local .
```

`Dockerfile` (Dockerfile:1-159) is a two-stage build. "Two platforms" in this repo means
two build *stages/targets*, not a multi-arch matrix — there is no `--platform` or buildx
cross-arch flag anywhere in the file. The two stages use two different Erlang/OTP base
images:

- **`builder`** (Dockerfile:24) — `hexpm/elixir:1.18.5-erlang-27.2.4-debian-bookworm-20260824`.
  Compiles everything, runs the full gate sequence, and builds the WASM engine.
- **final** (Dockerfile:152) — `hexpm/erlang:29.0-debian-bookworm-20260610-slim`, a newer,
  Erlang-only, slimmer base (OTP 29 vs the builder's OTP 27.2.4). Only the compiled BEAM
  files are copied in.

The build runs the project's real test gates as part of the image build — `rebar3 compile
&& rebar3 eunit` (Dockerfile:80), `mix deps.get` (Dockerfile:81), and `mix test` under
`scripts/env/rust4pm_reactor_env.sh` (Dockerfile:82). Any failing suite fails the `docker
build`. Expect the build to take a while: it installs `rebar3` 3.24.0 (Dockerfile:44-46),
installs Rust via rustup stable (Dockerfile:54, needed because bookworm's apt rustc 1.63 is
too old for oxigraph 0.5.9 used by `ggen_igniter`'s `native/ggen_graph_nif`), and compiles
four Rust oracle binaries (rf1-dfg, rf2-conformance, rf3-ocel, rf4-oc-discovery,
Dockerfile:71-74) used as real subprocess collaborators by the RF1-RF4 Chicago-style tests.

After the main `mix test` run, the build compiles the wasm32-wasip1 rust4pm-wasm engine
(Dockerfile:89) and runs a second, narrower suite,
`beam4pm_rust4pm_ci_test.exs` (Dockerfile:90), against that freshly-built WASM engine using
a checked-in portable fixture rather than the 29MB canonical corpus. This ordering — build
the WASM artifact *after* the primary `mix test` run, not before — is deliberate
(Dockerfile:84-88); see the `.dockerignore` section below for the bug this ordering
protects against.

Note that **Gleam is deliberately excluded** from the image (Dockerfile:17-21): no `gleam`
binary exists in the hexpm base images and no arch-conditional install path was
implemented. Gleam projection validation happens only in CI via `erlef/setup-beam`'s
`gleam-version` input, not in this Dockerfile.

## Run the image

The final stage's `CMD` runs a hand-authored demo Erlang module compiled into
`_build/default/lib/beam4pm/ebin` (Dockerfile:96-149, entrypoint at Dockerfile:158) that
seeds an OCEL log and runs `traces_from_events -> dfg_from_traces -> conformance`:

```sh
docker run --rm beam4pm:local
```

For the deployment shape this same image is intended for — Cloud Run
(`infra/gcp/cloudrun/main.tf`) or a Packer-baked GCE image running the container under
systemd on port 8080 (`infra/gcp/packer/beam4pm-image.pkr.hcl`) — see
`docs/how-to/` or `infra/gcp/` directly; both are ggen-generated from `b4pi:` ontology
facts and currently at "generated, unapplied" status (main.tf:28-31).

## What `.dockerignore` excludes, and why

`.dockerignore` documents two evidence-based exclusion rules:

1. **`vendor/`, `_build/`, `deps/`, `docs/`, `playground/`, `generated/gleam/build/`**
   (.dockerignore:9-16) — keeps the build context lean. The vendored `ggen-marketplace`
   submodule plus local build dirs measured ~500MB of context bloat even though the
   Dockerfile never `COPY`s them — Docker still uploads the entire build context before
   evaluating any `COPY` instruction. This also stops `vendor/_build` churn from
   invalidating the `type=gha` layer cache used by the build-push-action
   (.dockerignore:1-8).

2. **`native/*/target/`** (.dockerignore:34) — excludes each Rust oracle/engine crate's own
   build output. This guards against a real, previously-hit bug (.dockerignore:18-33): if
   you run `scripts/rust4pm_wasm_build.sh` locally before `docker build` — a natural thing
   to do given this repo's own build instructions — a pre-built `native/rust4pm-wasm/target/`
   artifact would leak into the image via `COPY native ./native` (Dockerfile:63). That would
   make `BeamPM.Rust4PM.wasm_built?/0` return `true` during the Dockerfile's *early*
   `mix test` step (Dockerfile:82), which deliberately runs *before*
   `scripts/rust4pm_wasm_build.sh` (Dockerfile:89) — flipping
   `test/beam4pm_rust4pm_test.exs`'s `setup_all` into a real-engine test branch that then
   fails looking for a host-only fixture path (`~/wasm4pm/data/InternationalDeclarations.xes`),
   invalidating all 13 tests in that file. CI never hits this because GitHub Actions runners
   start from a clean checkout with no pre-built `native/*/target/`. Excluding this path
   keeps the Dockerfile's two-stage WASM-build ordering authoritative regardless of local
   build state.

**Practical consequence:** if you've locally run `scripts/rust4pm_wasm_build.sh` (or any
other script that populates a `native/*/target/` directory) before building the image,
leave it as-is — `.dockerignore` already excludes it from the build context, so it will not
leak into the container.

## Validate the local build matches CI

CI builds this same `Dockerfile` from a clean checkout. To reproduce that locally:

1. Confirm your working tree has no stray build artifacts that aren't already covered by
   `.dockerignore` — a clean `git clone` build is the closest match to CI's runner state.
2. Run `docker build -t beam4pm:local .` and confirm both gate steps embedded in the build
   pass: `rebar3 eunit` (Dockerfile:80) and `mix test` (Dockerfile:82), plus the WASM-engine
   suite `beam4pm_rust4pm_ci_test.exs` (Dockerfile:90). A failure in any of these fails the
   `docker build` itself — there is no separate CI-only test step to reconcile.
3. If the build fails locally but the notes above (real bug: 13 invalid tests in
   `test/beam4pm_rust4pm_test.exs`) match your symptom, check for a leaked
   `native/*/target/` directory in your working tree and confirm it is excluded by
   `.dockerignore:34` rather than accidentally re-included.
4. Since there is no multi-arch matrix in this Dockerfile (no `--platform` flags), a
   single local `docker build` on your host architecture is a valid proxy for what CI's
   `type=gha`-cached build-push-action produces — there is no second architecture target to
   reconcile against.

## See Also

- `CLAUDE.md` — repo-wide manufacturing doctrine and build/sync/test commands
- `scripts/gate_m2_check.sh` — the determinism gate proving ggen output doesn't depend on
  prior disk state (unrelated to the container build, but the same "prior state must not
  leak in" principle the `.dockerignore:34` rule enforces for `native/*/target/`)
- `infra/gcp/cloudrun/main.tf` — Cloud Run deployment of this same image
- `infra/gcp/packer/beam4pm-image.pkr.hcl` — Packer-baked GCE image running this same
  container under systemd
