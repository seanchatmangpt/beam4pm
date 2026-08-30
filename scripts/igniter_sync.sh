#!/usr/bin/env bash
# GATE M3 (Elixir/Ash leg) - ggen_igniter-manufactured Ash projection for beam4pm.
#
# Run from the beam4pm repo root, with the pack's igniter assets at
# vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/
# (i.e. this stream's out/pack/igniter/ tree merged into the pack).
#
# Requirements (see mix_deps_note.md): {:ggen_igniter, "~> 26.8"} and
# {:ash, "~> 3.0"} in mix.exs, Elixir >= 1.17, OTP >= 25, and a working
# Rust/cargo toolchain (ggen_igniter's default oxigraph query engine is a
# Rustler NIF compiled as part of compiling the library itself).
#
# Engine note: the default --engine oxigraph is used below, exactly as
# executed and verified 2026-08-29 (ggen_igniter 26.8.30, Ash 3.32.1,
# Elixir 1.19.5/OTP 28). The EEx templates normalize oxigraph's raw
# N-Triples-style terms AND re-sort all rows internally, so if the Rustler
# NIF cannot be built on a host, appending `--engine sparql` to each sync
# invocation is a verified-equivalent fallback (both engines were A/B'd to
# byte-identical output; the sparql hex package's real ORDER BY bug is
# neutralized by the in-template Enum.sort_by re-sorting).
#
# Side effect: ggen_igniter records each (template, out) recipe in a
# reconciliation manifest at .ggen_igniter/manifest.json (repo root).
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

# 1. Ash resources + domain: 31 Ash.Resource modules (ETS data layer,
#    uuid_primary_key :id, ontology-derived attributes) + BeamPM.Ash.Domain.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --template "$IGN/templates/beam4pm_ash.ex.eex" \
  --out generated/elixir/lib/beam4pm_ash.ex

# 2. Chicago ExUnit CRUD suite: one real Ash.create!/Ash.read! round-trip
#    per admitted record type, deterministic sample values, no mocks.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --template "$IGN/templates/beam4pm_ash_test.exs.eex" \
  --out generated/elixir/test/beam4pm_ash_test.exs

# 3. (optional) Cross-engine identity probe: the EEx-rendered manifest must
#    be byte-identical to the Rust-ggen/Tera-manufactured
#    generated/elixir/lib/beam4pm_types_manifest.ex.
#    Verified result 2026-08-29: BYTE-IDENTICAL (on both engines).
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --template "$IGN/templates/beam4pm_types_manifest.ex.eex" \
  --out tmp_probe/beam4pm_types_manifest.ex
diff -u generated/elixir/lib/beam4pm_types_manifest.ex tmp_probe/beam4pm_types_manifest.ex \
  && echo "cross-engine identity probe: BYTE-IDENTICAL"

# Verify (as actually run in the scratch consumer: exit 0, and
# `1 doctest, 32 tests, 0 failures` - 31 of those tests are this suite).
mix compile --warnings-as-errors
mix test
