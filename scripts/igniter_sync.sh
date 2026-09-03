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

# 0. Remove the former monolithic outputs BEFORE any split-template sync
#    below runs. Order is load-bearing, not cosmetic: real-run evidence
#    2026-09-02 showed that if lib/beam4pm_ash.ex (old, defines all 289
#    resource modules) is still on disk while step 1b's reactor-pipelined
#    sync does its own internal `mix compile` build-verification, Elixir's
#    parallel compiler hard-fails ("cannot define module
#    BeamPM.Ash.Resources.AdoptionMilestone because it is currently being
#    defined in lib/beam4pm_ash/resources/adoption_milestone.ex:3") because
#    the old monolith and the new per-resource files under
#    lib/beam4pm_ash/resources/ would define the same module names in the
#    same compile pass. Deleting first (both are pure regeneration targets
#    of the templates below -- never hand-edited) avoids that collision
#    entirely, same as deleting a file being renamed before writing its
#    replacement.
rm -f lib/beam4pm_ash.ex test/beam4pm_ash_test.exs

# 1a. Ash resources: one Ash.Resource module PER admitted bpm:RecordType row
#     (ETS data layer, uuid_primary_key :id, ontology-derived attributes),
#     one file per resource under lib/beam4pm_ash/resources/. Split out of
#     the former single lib/beam4pm_ash.ex monolith 2026-09-02: a measured
#     synthetic reproduction at matching scale (N=289) showed a
#     single-resource edit forces a ~60s recompile of one monolithic file
#     vs. ~0.9-1.8s per resource file here -- a real, bounded compile-speed
#     win. `--on-stale prune` really deletes any resource file left over
#     from a record removed from ontology.ttl since the last sync (so the
#     directory never accumulates orphans as the admitted record set
#     changes), while still writing this run's outputs first.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --for-each records \
  --on-stale prune \
  --template "$IGN/templates/beam4pm_ash_resource.ex.eex" \
  --out "lib/beam4pm_ash/resources/<%= record_name %>.ex"

# 1b. BeamPM.Ash.Domain (registers every resource from 1a by name) plus the
#     static BeamPM.Autonomy.Kernel module -- neither has a per-record
#     shape, so both stay single-output like the pre-split monolith.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --template "$IGN/templates/beam4pm_ash_domain.ex.eex" \
  --out lib/beam4pm_ash_domain.ex

# 2a. Chicago ExUnit CRUD suite: one real Ash.create!/Ash.read! round-trip
#     per admitted record type, deterministic sample values, no mocks -- one
#     test file per resource under test/beam4pm_ash/resources/, split for
#     the same marginal-compile-cost reason as 1a. mix's default
#     test_paths ["test"] recurses, and test/test_helper.exs (unchanged)
#     already covers this nested directory, so no new test_helper is
#     needed. `--on-stale prune` mirrors 1a.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --for-each records \
  --on-stale prune \
  --template "$IGN/templates/beam4pm_ash_resource_test.exs.eex" \
  --out "test/beam4pm_ash/resources/<%= record_name %>_test.exs"

# 2b. BeamPM.AutonomyKernelGeneratedTest: static, no per-record shape, so it
#     stays a single output file like the pre-split monolith test.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --template "$IGN/templates/beam4pm_ash_kernel_test.exs.eex" \
  --out test/beam4pm_ash_kernel_test.exs

# 3. (optional) Cross-engine identity probe: the EEx-rendered manifest must
#    be byte-identical to the Rust-ggen/Tera-manufactured
#    lib/beam4pm_types_manifest.ex.
#    Verified result 2026-08-29: BYTE-IDENTICAL (on both engines).
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --template "$IGN/templates/beam4pm_types_manifest.ex.eex" \
  --out tmp_probe/beam4pm_types_manifest.ex
diff -u lib/beam4pm_types_manifest.ex tmp_probe/beam4pm_types_manifest.ex \
  && echo "cross-engine identity probe: BYTE-IDENTICAL"

# Verify (as actually run in the scratch consumer: exit 0, and
# `1 doctest, 32 tests, 0 failures` - 31 of those tests are this suite).
mix compile --warnings-as-errors
mix test
