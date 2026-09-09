#!/usr/bin/env bash
# GATE M5 — cross-language identity check.
#
# Proves that representative semantic objects (every admitted bpm:RecordType,
# in both a full and a required-fields-only variant) round-trip across the
# generated Erlang, Elixir and Ash wire boundaries:
#
#   1. Erlang writes JSON wire samples for all records x variants (*.erl.json).
#   2. Elixir decodes and verifies every Erlang-written sample against its own
#      independently constructed samples, then writes its own (*.ex.json).
#   3. Erlang decodes and verifies every Elixir-written sample.
#   4. Ash (the fourth sibling projection) verifies the SAME Erlang-written
#      samples from step 1: BeamPM.Codec.decode -> Ash.create on the real ETS
#      data layer -> Ash.get by primary key -> field-by-field identity against
#      the same independent BeamPM.Roundtrip sample step 2 used.
#
# Identity is asserted at the wire-semantic level for steps 2-3: to_map(decode(
# other language's JSON)) must equal to_map(locally constructed sample). Step 4
# cannot use to_map (it does not apply to an Ash struct), so it compares the
# read-back record's public attributes field by field: every attribute whose
# bpm:ashTypeExpr is in the :utc_datetime family via
# DateTime.compare(ash_read, DateTime.from_iso8601(wire)) == :eq (Ash normalizes
# the ISO 8601 string the other legs carry verbatim into a UTC %DateTime{} with
# microsecond {n, 6}; nil == nil for an optional datetime absent from the
# minimal wire), every other attribute via ==, and the synthetic
# uuid_primary_key :id asserted to be the ONLY Ash-only attribute. Any failure
# in any direction exits non-zero. This script is ops tooling only — every
# module it calls (beam4pm_roundtrip, BeamPM.Roundtrip, BeamPM.AshRoundtrip,
# the codecs, the types, the Ash resources) is ggen/ggen_igniter-manufactured
# (see the header comment in each file, not directory placement).
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/ebin" "$TMP/wire"

erlc -o "$TMP/ebin" src/*.erl

erl -noshell -pa "$TMP/ebin" -eval "ok = beam4pm_roundtrip:write_samples(\"$TMP/wire\"), halt(0)."

mix run -e "
{pass, failures} = BeamPM.Roundtrip.verify_samples(\"$TMP/wire\", \"erl\")
IO.puts(\"elixir-verifies-erlang: #{pass} pass, #{length(failures)} fail\")
Enum.each(failures, &IO.puts/1)
if failures != [], do: System.halt(1)
:ok = BeamPM.Roundtrip.write_samples(\"$TMP/wire\")
"

erl -noshell -pa "$TMP/ebin" -eval "
{Pass, Failures} = beam4pm_roundtrip:verify_samples(\"$TMP/wire\", \"ex\"),
io:format(\"erlang-verifies-elixir: ~p pass, ~p fail~n\", [Pass, length(Failures)]),
lists:foreach(fun(F) -> io:format(\"~s~n\", [F]) end, Failures),
case Failures of [] -> halt(0); _ -> halt(1) end."

# Step 4 runs inside the same mktemp lifetime as step 1, so the *.erl.json
# fixtures it reads are exactly the bytes Erlang wrote above. Logger is raised
# to :warning because Ash.DataLayer.Ets logs one debug block per create (578 of
# them under the dev default) that would bury the gate line.
mix run -e "
Logger.configure(level: :warning)
{pass, failures} = BeamPM.AshRoundtrip.verify_samples(\"$TMP/wire\", \"erl\")
IO.puts(\"ash-verifies-wire: #{pass} pass, #{length(failures)} fail\")
Enum.each(failures, &IO.puts/1)
if failures != [], do: System.halt(1)
"

echo "GATE M5 roundtrip: PASS (all three directions)"
