#!/usr/bin/env bash
# GATE M5 — cross-language identity check.
#
# Proves that representative semantic objects (every admitted bpm:RecordType,
# in both a full and a required-fields-only variant) round-trip across the
# generated Erlang and Elixir wire boundaries:
#
#   1. Erlang writes JSON wire samples for all records x variants (*.erl.json).
#   2. Elixir decodes and verifies every Erlang-written sample against its own
#      independently constructed samples, then writes its own (*.ex.json).
#   3. Erlang decodes and verifies every Elixir-written sample.
#
# Identity is asserted at the wire-semantic level: to_map(decode(other
# language's JSON)) must equal to_map(locally constructed sample). Any failure
# in either direction exits non-zero. This script is ops tooling only — every
# module it calls (beam4pm_roundtrip, BeamPM.Roundtrip, the codecs, the types)
# is ggen-manufactured (see the header comment in each file, not directory placement).
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

echo "GATE M5 roundtrip: PASS (both directions)"
