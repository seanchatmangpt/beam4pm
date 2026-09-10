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
# reconciliation manifest at .ggen_igniter/manifest.json (repo root), and
# step 0b writes the merged consumer+pack graph to tmp_probe/ontology_merged.ttl
# (gitignored scratch, reproducible path).
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

# 0b. Merged graph for the Ash leg. ggen_igniter loads exactly ONE --ontology
#     file (mix task option `ontology: :string`; GgenIgniter.Ontology.load!/1
#     is a single RDF.Turtle.read_file!/1), but the Ash templates' query
#     igniter/queries/ash_fields.rq JOINs the consumer's bpm:Field rows
#     against the bpm:FieldType vocabulary (bpm:ashTypeExpr, bpm:sampleElixir)
#     that lives in the PACK's ontology.ttl -- the Rust ggen leg gets that
#     merge for free from ggen.toml [packs]; igniter has no equivalent.
#     Measured 2026-09-05: the JOIN binds 0 Ash types on ontology.ttl alone
#     (every resource render refused by name) and all 1074 field rows on the
#     concatenation. Plain concatenation is lawful Turtle here: neither file
#     declares @base and a repeated @prefix is a no-op redefinition. Fixed,
#     gitignored path (tmp_probe/, never mktemp) so the ontology path a
#     receipt records is reproducible run to run; tmp_probe/ is outside
#     gate_m2_check.sh's SEARCH_DIRS and the merged file carries no
#     GENERATED marker, so it is never mistaken for manufactured output.
#     Originally only steps 1a/2a consumed this, with step 3 (fields.rq) and
#     scripts/pro_type_pages_sync.sh running on the bare consumer graph --
#     safe while beam4pm-process-model-pack was the only wired pack
#     contributing bpm:RecordType facts. Broken by frontier-release-beam-pack
#     (2026-09-09): a SECOND pack now contributes bpm:RecordType/bpm:Field
#     facts (frontier_source_release/opportunity/benchmark/evidence), which
#     the Rust ggen leg picks up for free via ggen.toml's [packs] merge but
#     ontology.ttl alone does not -- step 3's cross-engine identity probe
#     DIVERGED for real (ggen_igniter's manifest missing all 4 frontier_*
#     records the Rust leg had). Fixed by also concatenating every
#     ADDITIONAL_PACK_ONTOLOGY below into MERGED_TTL and using it for step 3
#     too, not just 1a/2a.
MERGED_TTL="tmp_probe/ontology_merged.ttl"
mkdir -p tmp_probe
ADDITIONAL_PACK_ONTOLOGIES=(
  "vendor/ggen-marketplace/packs/frontier-release-beam-pack/ontology.ttl"
)
cat ontology.ttl "$PACK/ontology.ttl" "${ADDITIONAL_PACK_ONTOLOGIES[@]}" > "$MERGED_TTL"

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
#     changes), while still writing this run's outputs first. Attribute
#     types come from the vocabulary's bpm:ashTypeExpr via ash_fields.rq on
#     the merged graph (0b) -- datetime is :utc_datetime_usec, so the
#     microseconds every other leg carries on the wire survive the Ash leg
#     (the former in-template ladder said :utc_datetime and truncated them).
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --query ash_fields="$IGN/queries/ash_fields.rq" \
  --for-each records \
  --on-stale prune \
  --template "$IGN/templates/beam4pm_ash_resource.ex.eex" \
  --out "lib/beam4pm_ash/resources/<%= record_name %>.ex"

# 1b. BeamPM.Ash.Domain (registers every resource from 1a by name) plus the
#     static BeamPM.Autonomy.Kernel module -- neither has a per-record
#     shape, so both stay single-output like the pre-split monolith. Must
#     run on MERGED_TTL, same as 1a: a bare-ontology.ttl run here once
#     generated every lib/beam4pm_ash/resources/frontier_*.ex resource
#     module (1a, correctly on MERGED_TTL) but left them unregistered in
#     BeamPM.Ash.Domain, a real "Resource ... is not accepted by
#     BeamPM.Ash.Domain" Ash.create/3 failure caught by
#     test/beam4pm_ash_roundtrip_test.exs, not a hypothetical.
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --template "$IGN/templates/beam4pm_ash_domain.ex.eex" \
  --out lib/beam4pm_ash_domain.ex

# 1c. BeamPM.AshRoundtrip -- the Ash leg of GATE M5 (scripts/roundtrip_check.sh,
#     third direction "ash-verifies-wire"). Single output: for every admitted
#     record x {full, minimal} it decodes the SAME wire fixture the Erlang and
#     Elixir legs exchange through BeamPM.Codec, creates the Ash resource on
#     the real ETS data layer, reads it back by primary key and compares field
#     by field against BeamPM.Roundtrip's independent sample (datetime
#     attributes via DateTime.compare/2 == :eq, everything else via ==; the
#     synthetic uuid_primary_key :id disclosed as the only Ash-only attribute
#     and asserted so). Needs ash_fields.rq on the merged graph (0b) to know
#     which attributes are in the :utc_datetime family; refuses by record and
#     field name on an unbound ?ash_type_expr like its two siblings.
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --query ash_fields="$IGN/queries/ash_fields.rq" \
  --template "$IGN/templates/beam4pm_ash_roundtrip.ex.eex" \
  --out lib/beam4pm_ash_roundtrip.ex

# 2a. Real Ash.create!/Ash.read! round-trip per admitted record type,
#     deterministic sample values, no mocks -- collapsed into ONE output
#     file (test/beam4pm_ash_resources_test.exs), unlike 1a's per-resource
#     lib/ split. The lib/ split (1a) has a real, measured compile-cost
#     rationale that does not apply here: this was previously one test
#     FILE per resource (592 files, all async: false, one BEAM
#     test-process spawn each) under test/beam4pm_ash/resources/, which
#     dominated `mix test` wall clock (~592 of the suite's slowest tests)
#     while only proving Ash's own ETS create/read mechanics repeatedly,
#     not beam4pm-specific logic. The real signal -- each resource's
#     attributes correctly mirror its admitted record type's fields -- is
#     now proven by one runtime loop over all resources inside a single
#     test, same per-resource/per-field assertions, labeled by record name
#     on failure. Delete the old per-resource directory first since the
#     output path itself changed (a stale one wouldn't be pruned by
#     --on-stale, which no longer applies to a single-output template).
rm -rf test/beam4pm_ash/resources
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --template "$IGN/templates/beam4pm_ash_resource_test.exs.eex" \
  --out test/beam4pm_ash_resources_test.exs

# 2c. BeamPM.AshRoundtripTest: the same-language ("ex" fixtures) exercise of
#     1c's module plus two named falsifiers (a no-fraction datetime and a
#     mutated string on the wire must each be refused naming record, variant
#     and field). Cleans its own ETS rows up (Ash.DataLayer.Ets.stop/1 per
#     resource, waiting for the table to be gone) because the 2a suite reads
#     back with a one-row read-all. The cross-language "erl" direction stays
#     in scripts/roundtrip_check.sh, which has erlc/erl.
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --query ash_fields="$IGN/queries/ash_fields.rq" \
  --template "$IGN/templates/beam4pm_ash_roundtrip_test.exs.eex" \
  --out test/beam4pm_ash_roundtrip_test.exs

# 2b. BeamPM.AutonomyKernelGeneratedTest: static, no per-record shape, so it
#     stays a single output file like the pre-split monolith test. Run on
#     MERGED_TTL for consistency with every other `records` consumer in
#     this script since 0b (frontier-release-beam-pack) -- if this template
#     ever starts counting/listing records (it does not today), a bare
#     ontology.ttl run would silently under-report the same way 1b did.
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --template "$IGN/templates/beam4pm_ash_kernel_test.exs.eex" \
  --out test/beam4pm_ash_kernel_test.exs

# 3. Cross-engine identity probe: the EEx-rendered manifest must be
#    byte-identical to the Rust-ggen/Tera-manufactured
#    lib/beam4pm_types_manifest.ex. Verified BYTE-IDENTICAL 2026-08-29 (both
#    engines) and again 2026-09-05. FATAL since 2026-09-05: the former
#    `diff ... && echo` form never failed this script -- under `set -e` a
#    `cmd && other` list whose first command fails is not an error, so a
#    divergence between the two engines printed a diff and kept going. Runs
#    on MERGED_TTL (0b, now including every ADDITIONAL_PACK_ONTOLOGY), not
#    the bare consumer graph -- the Rust leg's own manifest template runs
#    against ggen.toml's full [packs] merge, so this probe must match that
#    same scope or a pack-contributed record type (e.g. frontier-release-
#    beam-pack's frontier_*) makes the two engines diverge for real, not
#    just report a false positive.
mix ggen_igniter.sync \
  --ontology "$MERGED_TTL" \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --template "$IGN/templates/beam4pm_types_manifest.ex.eex" \
  --out tmp_probe/beam4pm_types_manifest.ex
if diff -u lib/beam4pm_types_manifest.ex tmp_probe/beam4pm_types_manifest.ex; then
  echo "cross-engine identity probe: BYTE-IDENTICAL"
else
  echo "cross-engine identity probe: DIVERGED -- the igniter and Rust ggen engines disagree on beam4pm_types_manifest.ex (see diff above)" >&2
  exit 1
fi

# Verify (as actually run in the scratch consumer: exit 0, and
# `1 doctest, 32 tests, 0 failures` - 31 of those tests are this suite).
mix compile --warnings-as-errors
mix test
