#!/usr/bin/env bash
# oracle_check.sh -- W2 differential dogfood gate for beam4pm discovery.
#
# Chicago-style (no mocks): every leg below runs a REAL binary over REAL
# generated source -- the generated Erlang modules compiled by a real erlc,
# the generated Elixir modules compiled by a real elixirc, the rust4pm
# oracle built by a real cargo (native) and executed under a real wasmtime
# (wasm32-wasip1). Nothing is stubbed; the gate compares REAL stdout/file
# bytes of all four implementations, per seeded log.
#
# What it does, from the beam4pm repo root:
#   1. builds the oracle at qualification/rust4pm-oracle (native + wasm32-wasip1)
#      if the artifacts are not already present;
#   2. generates a deterministic battery of >= 6 seeded wire-contract logs
#      (no randomness anywhere -- the "large" log uses a fixed-seed LCG);
#   3. for each log computes DFG edges via:
#        a. generated Erlang  (beam4pm_discovery, escript over erlc-compiled
#           generated/erlang/src)
#        b. generated Elixir  (BeamPM.Discovery, elixirc-compiled
#           generated/elixir/lib -- compiled directly rather than via
#           `mix run -e` so the gate does not depend on hex/deps fetch for
#           the unrelated Ash dependency of beam4pm_ash.ex)
#        c. oracle NATIVE     (stdin/stdout wire contract)
#        d. oracle WASM       (same .wasm under wasmtime)
#   4. canonicalizes each output (strict shape check + sorted-key compact
#      JSON; an output that is not already edge-sorted is itself a failure)
#      and asserts all four byte-identical; the three logs with hand-derived
#      expected edges are additionally anchored against those expectations
#      (agreement alone is not correctness);
#   5. prints one PASS/FAIL line per log; exits 0 only if every log passes.
#
# Exit codes (fail-closed, mirroring ggen-ecosystem tests/test_container_smoke.sh):
#   0  every log PASS on all four implementations
#   1  divergence, oracle build failure, or a runner failure
#   2  BLOCKED -- a required real collaborator is absent (oracle crate dir,
#      cargo, wasmtime, wasm32-wasip1 std, erlc/escript, elixirc/elixir,
#      python3). BLOCKED is never reported as PASS.
#
# Parameters (env):
#   BEAM4PM_ROOT          repo root (default: pwd)
#   ORACLE_DIR            oracle crate dir (default: $BEAM4PM_ROOT/qualification/rust4pm-oracle)
#   ORACLE_BIN_NAME       cargo bin name (default: parsed from Cargo.toml [package] name)
#   CASE_ATTR_KEY         attribute key holding the case id (default: case_id)
#   ORACLE_CHECK_WORKDIR  scratch dir for logs/outputs (default: mktemp -d)

set -uo pipefail

ROOT="${BEAM4PM_ROOT:-$(pwd)}"
ORACLE_DIR="${ORACLE_DIR:-$ROOT/qualification/rust4pm-oracle}"
CASE_ATTR_KEY="${CASE_ATTR_KEY:-case_id}"
WORKDIR="${ORACLE_CHECK_WORKDIR:-$(mktemp -d "${TMPDIR:-/tmp}/oracle_check.XXXXXX")}"

ERL_SRC="$ROOT/generated/erlang/src"
EX_SRC="$ROOT/generated/elixir/lib"

blocked() { echo "BLOCKED: $*" >&2; exit 2; }
fail_now() { echo "FAIL: $*" >&2; exit 1; }

# --- BLOCKED checks: every real collaborator must actually exist -----------
for tool in cargo erlc escript elixirc elixir wasmtime python3; do
    command -v "$tool" >/dev/null 2>&1 \
        || blocked "$tool is not installed / not on PATH -- cannot run any real assertion."
done
[ -d "$ERL_SRC" ] || blocked "generated Erlang source dir absent: $ERL_SRC"
[ -d "$EX_SRC" ]  || blocked "generated Elixir source dir absent: $EX_SRC"
[ -d "$ORACLE_DIR" ] && [ -f "$ORACLE_DIR/Cargo.toml" ] \
    || blocked "rust4pm oracle crate absent at $ORACLE_DIR (expected Cargo.toml; provide qualification/rust4pm-oracle or set ORACLE_DIR). Fail-closed: the gate never fakes an oracle."
SYSROOT="$(rustc --print sysroot 2>/dev/null)" || blocked "rustc not runnable"
[ -d "$SYSROOT/lib/rustlib/wasm32-wasip1" ] \
    || blocked "rust wasm32-wasip1 std is not installed (rustup target add wasm32-wasip1)"

# --- 1. build the oracle (native + wasm32-wasip1) if not built -------------
BIN_NAME="${ORACLE_BIN_NAME:-$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ORACLE_DIR/Cargo.toml" | head -1)}"
[ -n "$BIN_NAME" ] || blocked "could not determine oracle bin name from $ORACLE_DIR/Cargo.toml (set ORACLE_BIN_NAME)"
NATIVE_BIN="$ORACLE_DIR/target/release/$BIN_NAME"
WASM_BIN="$ORACLE_DIR/target/wasm32-wasip1/release/$BIN_NAME.wasm"

if [ ! -x "$NATIVE_BIN" ]; then
    echo "== building oracle (native) at $ORACLE_DIR =="
    cargo build --release --manifest-path "$ORACLE_DIR/Cargo.toml" \
        || fail_now "oracle native build failed"
fi
if [ ! -f "$WASM_BIN" ]; then
    echo "== building oracle (wasm32-wasip1) at $ORACLE_DIR =="
    cargo build --release --target wasm32-wasip1 --manifest-path "$ORACLE_DIR/Cargo.toml" \
        || fail_now "oracle wasm32-wasip1 build failed"
fi
[ -x "$NATIVE_BIN" ] || blocked "oracle native binary still absent after build: $NATIVE_BIN"
[ -f "$WASM_BIN" ]   || blocked "oracle wasm module still absent after build: $WASM_BIN"

mkdir -p "$WORKDIR/logs" "$WORKDIR/expected" "$WORKDIR/results" "$WORKDIR/ebin" "$WORKDIR/exbin"

# --- 2. deterministic seeded log battery (wire-contract JSON) --------------
python3 - "$WORKDIR" "$CASE_ATTR_KEY" <<'PYGEN' || fail_now "log generation failed"
import json, os, sys

workdir, ck = sys.argv[1], sys.argv[2]
logs, expected = {}, {}

def ev(eid, etype, etime, attrs="__ABSENT__"):
    e = {"event_id": eid, "event_type": etype, "event_time": etime}
    if attrs != "__ABSENT__":
        e["attributes"] = attrs
    return e

# 01: the demo 3-case log (the exact 8-event seeded log from the generated
# discovery EUnit/ExUnit courts: 3 cases, one no-case-key event, one
# no-attributes event, deliberately unsorted input, one same-time id tie).
logs["01-demo-3case"] = [
    ev("e5", "c", "2026-08-29T10:02:00Z", {ck: "c1"}),
    ev("e4", "b", "2026-08-29T10:01:30Z", {ck: "c2"}),
    ev("e1", "a", "2026-08-29T10:00:00Z", {ck: "c1"}),
    ev("e7", "x", "2026-08-29T10:04:00Z", {"other": "v"}),
    ev("e2", "a", "2026-08-29T10:01:30Z", {ck: "c2"}),
    ev("e6", "a", "2026-08-29T10:03:00Z", {ck: "c3"}),
    ev("e3", "b", "2026-08-29T10:01:00Z", {ck: "c1"}),
    ev("e8", "y", "2026-08-29T10:05:00Z"),
]
expected["01-demo-3case"] = [("a", "b", 2), ("b", "c", 1)]

# 02: single-event traces only -> zero edges.
logs["02-single-event-traces"] = [
    ev(f"s{i}", act, f"2026-08-29T09:00:0{i}Z", {ck: f"sc{i}"})
    for i, act in enumerate(["alpha", "beta", "gamma", "delta"])
]
expected["02-single-event-traces"] = []

# 03: duplicate adjacent activities (a->a self-loop) in one case.
logs["03-self-loop"] = [
    ev(f"L{i}", act, f"2026-08-29T08:00:{i:02d}Z", {ck: "loop1"})
    for i, act in enumerate(["a", "a", "a", "b", "a"])
]
expected["03-self-loop"] = [("a", "a", 2), ("a", "b", 1), ("b", "a", 1)]

# 04: interleaved timestamps across 6 cases (round-robin), input order
# deliberately scrambled (deterministic permutation), plus one same-time
# event-id tie inside case k1.
events, eid = [], 0
for rnd, act in enumerate(["start", "mid", "finish"]):
    for ci in range(1, 7):
        eid += 1
        events.append(
            ev(f"i{eid:03d}", act, f"2026-08-29T11:{rnd:02d}:{ci:02d}Z", {ck: f"k{ci}"})
        )
# tie: same timestamp as k1's "mid" (11:01:01), id sorts after i007
events.append(ev("i090", "extra", "2026-08-29T11:01:01Z", {ck: "k1"}))
events = events[::2] + events[1::2]
events.reverse()
logs["04-interleaved"] = events
expected["04-interleaved"] = [
    ("extra", "finish", 1), ("mid", "extra", 1), ("mid", "finish", 5), ("start", "mid", 6),
]

# 05: events missing the case attribute in all three shapes -- key absent
# from attributes, empty attributes object, attributes field absent -- must
# be skipped by every implementation.
logs["05-missing-case-attr"] = [
    ev("m1", "A", "2026-08-29T07:00:01Z", {ck: "mc1"}),
    ev("m2", "B", "2026-08-29T07:00:02Z", {ck: "mc1"}),
    ev("m3", "X", "2026-08-29T07:00:03Z", {"other": "v"}),
    ev("m4", "Y", "2026-08-29T07:00:04Z", {}),
    ev("m5", "Z", "2026-08-29T07:00:05Z"),
    ev("m6", "C", "2026-08-29T07:00:06Z", {ck: "mc1"}),
    ev("m7", "A", "2026-08-29T07:00:07Z", {ck: "mc2"}),
    ev("m8", "B", "2026-08-29T07:00:08Z", {ck: "mc2"}),
]
expected["05-missing-case-attr"] = [("A", "B", 2), ("B", "C", 1)]

# 06: large log, 150 events, 12 cases, fixed-seed LCG (pure integer math,
# no randomness), injected timestamp ties and skipped events.
state = 26082900
def lcg():
    global state
    state = (state * 1103515245 + 12345) % (2**31)
    return state
acts = ["alpha", "beta", "gamma", "delta", "epsilon"]
events = []
secs_prev = 0
for i in range(150):
    case = f"c{lcg() % 12:02d}"
    act = acts[lcg() % 5]
    secs = secs_prev if (i % 10 == 9) else i * 7   # every 10th event ties
    secs_prev = secs
    hh, rem = 12 + secs // 3600, secs % 3600
    t = f"2026-08-29T{hh:02d}:{rem // 60:02d}:{rem % 60:02d}Z"
    if i % 13 == 12:
        events.append(ev(f"g{i:04d}", act, t, {"noise": str(lcg() % 100)}))
    else:
        events.append(ev(f"g{i:04d}", act, t, {ck: case, "amount": lcg() % 1000}))
logs["06-large-seeded"] = events

# 07: unicode + JSON-escaping edge cases in activity names and case ids
# (multibyte UTF-8, quotes, backslashes, tabs) -- exercises string handling
# and byte-order sorting across all four serializers.
logs["07-unicode-escapes"] = [
    ev("u1", "ünïcode", "2026-08-29T06:00:01Z", {ck: "u/one"}),
    ev("u2", "活動-open", "2026-08-29T06:00:02Z", {ck: "u/one"}),
    ev("u3", 'quote"act', "2026-08-29T06:00:03Z", {ck: "u/one"}),
    ev("u4", "Zed", "2026-08-29T06:00:04Z", {ck: "u/one"}),
    ev("u5", "apple", "2026-08-29T06:00:05Z", {ck: "ußtwo"}),
    ev("u6", "back\\slash", "2026-08-29T06:00:06Z", {ck: "ußtwo"}),
    ev("u7", "tab\tact", "2026-08-29T06:00:07Z", {ck: "ußtwo"}),
    ev("u8", "ünïcode", "2026-08-29T06:00:08Z", {ck: "ußtwo"}),
]

for name, evs in sorted(logs.items()):
    with open(os.path.join(workdir, "logs", name + ".json"), "w") as f:
        json.dump({"case_attr_key": ck, "events": evs}, f, ensure_ascii=True)
for name, edges in sorted(expected.items()):
    with open(os.path.join(workdir, "expected", name + ".json"), "w") as f:
        json.dump({"edges": [
            {"source_activity": s, "target_activity": t, "frequency": n}
            for s, t, n in edges]}, f, ensure_ascii=True)
print(f"generated {len(logs)} seeded logs ({len(expected)} with hand-derived expected edges)")
PYGEN

# --- 3. compile the generated Erlang + Elixir discovery stack --------------
echo "== compiling generated Erlang (erlc) =="
erlc -o "$WORKDIR/ebin" \
    "$ERL_SRC/beam4pm_types.erl" "$ERL_SRC/beam4pm_codec.erl" "$ERL_SRC/beam4pm_discovery.erl" \
    || fail_now "erlc failed on generated/erlang/src"

echo "== compiling generated Elixir (elixirc) =="
( cd "$WORKDIR/exbin" && elixirc \
    "$EX_SRC/beam4pm_types.ex" "$EX_SRC/beam4pm_codec.ex" "$EX_SRC/beam4pm_discovery.ex" ) \
    || fail_now "elixirc failed on generated/elixir/lib"

# --- 4. runners (real escript / real elixir; results written to files) -----
cat > "$WORKDIR/erl_runner.escript" <<'ERLRUN'
#!/usr/bin/env escript
%% W2 gate runner: wire-contract log -> generated beam4pm_discovery -> edges JSON.
main([Ebin, LogPath, OutPath]) ->
    true = code:add_patha(Ebin),
    {ok, Bin} = file:read_file(LogPath),
    Decoded = json:decode(Bin),
    #{<<"case_attr_key">> := Key, <<"events">> := EventMaps} = Decoded,
    Events = lists:map(
        fun(M) ->
            case beam4pm_codec:from_map(ocel_event, M) of
                {ok, Ev} -> Ev;
                {error, Reason} -> erlang:error({bad_event, Reason, M})
            end
        end, EventMaps),
    Traces = beam4pm_discovery:traces_from_events(Events, Key),
    Edges = beam4pm_discovery:dfg_from_traces(Traces),
    EdgeMaps = [beam4pm_codec:to_map(E) || E <- Edges],
    Out = iolist_to_binary(json:encode(#{<<"edges">> => EdgeMaps})),
    ok = file:write_file(OutPath, Out);
main(_) ->
    io:format(standard_error, "usage: erl_runner.escript EBIN LOG OUT~n", []),
    halt(64).
ERLRUN

cat > "$WORKDIR/elixir_runner.exs" <<'EXRUN'
# W2 gate runner: wire-contract log -> generated BeamPM.Discovery -> edges JSON.
[log_path, out_path] = System.argv()
%{"case_attr_key" => key, "events" => event_maps} = JSON.decode!(File.read!(log_path))
events =
  Enum.map(event_maps, fn m ->
    {:ok, ev} = BeamPM.Codec.from_map(:ocel_event, m)
    ev
  end)
traces = BeamPM.Discovery.traces_from_events(events, key)
edges = BeamPM.Discovery.dfg_from_traces(traces)
edge_maps = Enum.map(edges, &BeamPM.Codec.to_map/1)
File.write!(out_path, JSON.encode!(%{"edges" => edge_maps}))
EXRUN

# --- canonicalizer: strict shape + already-sorted check + stable bytes -----
cat > "$WORKDIR/canon.py" <<'PYCANON'
import json, sys
inp, outp = sys.argv[1], sys.argv[2]
def die(msg):
    print(f"canon: {inp}: {msg}", file=sys.stderr); sys.exit(1)
try:
    with open(inp, "rb") as f:
        data = json.load(f)
except Exception as exc:
    die(f"not parseable JSON: {exc}")
if not isinstance(data, dict) or set(data.keys()) != {"edges"}:
    die('top-level must be exactly {"edges": [...]}')
edges = data["edges"]
if not isinstance(edges, list):
    die("edges must be a list")
norm = []
for i, e in enumerate(edges):
    if not isinstance(e, dict) or set(e.keys()) != {"source_activity", "target_activity", "frequency"}:
        die(f"edge[{i}] must have exactly source_activity/target_activity/frequency: {e!r}")
    s, t, n = e["source_activity"], e["target_activity"], e["frequency"]
    if not isinstance(s, str) or not isinstance(t, str):
        die(f"edge[{i}] activities must be strings")
    if not isinstance(n, int) or isinstance(n, bool) or n < 1:
        die(f"edge[{i}] frequency must be a positive integer, got {n!r}")
    norm.append((s, t, n))
pairs = [(s, t) for s, t, _ in norm]
if pairs != sorted(pairs):
    die("edges are not sorted by (source_activity, target_activity)")
if len(set(pairs)) != len(pairs):
    die("duplicate (source_activity, target_activity) edge")
with open(outp, "w") as f:
    json.dump({"edges": [
        {"source_activity": s, "target_activity": t, "frequency": n}
        for s, t, n in norm]},
        f, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    f.write("\n")
PYCANON

# --- 5. run all four implementations per log and compare -------------------
PASS_COUNT=0
FAIL_COUNT=0

run_impl() { # run_impl <impl> <resdir> <log> ; produces <resdir>/<impl>.canon.json
    local impl="$1" resdir="$2" log="$3"
    local raw="$resdir/$impl.json" canon="$resdir/$impl.canon.json"
    case "$impl" in
        erlang) escript "$WORKDIR/erl_runner.escript" "$WORKDIR/ebin" "$log" "$raw" ;;
        elixir) elixir -pa "$WORKDIR/exbin" "$WORKDIR/elixir_runner.exs" "$log" "$raw" ;;
        native) "$NATIVE_BIN" < "$log" > "$raw" ;;
        wasm)   wasmtime run "$WASM_BIN" < "$log" > "$raw" ;;
    esac || { echo "  $impl runner exited nonzero" >&2; return 1; }
    python3 "$WORKDIR/canon.py" "$raw" "$canon" || { echo "  $impl output failed canonicalization" >&2; return 1; }
}

echo "== differential battery: erlang vs elixir vs oracle-native vs oracle-wasm =="
for log in "$WORKDIR"/logs/*.json; do
    name="$(basename "$log" .json)"
    resdir="$WORKDIR/results/$name"
    mkdir -p "$resdir"
    log_ok=1
    for impl in erlang elixir native wasm; do
        run_impl "$impl" "$resdir" "$log" || log_ok=0
    done
    if [ "$log_ok" -eq 1 ]; then
        for impl in erlang elixir wasm; do
            if ! cmp -s "$resdir/native.canon.json" "$resdir/$impl.canon.json"; then
                log_ok=0
                echo "  DIVERGENCE on $name: $impl != native" >&2
                diff "$resdir/native.canon.json" "$resdir/$impl.canon.json" >&2 || true
            fi
        done
    fi
    if [ "$log_ok" -eq 1 ] && [ -f "$WORKDIR/expected/$name.json" ]; then
        python3 "$WORKDIR/canon.py" "$WORKDIR/expected/$name.json" "$resdir/expected.canon.json" \
            || fail_now "expected-edges fixture for $name failed canonicalization (gate bug)"
        if ! cmp -s "$resdir/expected.canon.json" "$resdir/native.canon.json"; then
            log_ok=0
            echo "  ANCHOR MISMATCH on $name: all four agree but differ from hand-derived expected edges" >&2
            diff "$resdir/expected.canon.json" "$resdir/native.canon.json" >&2 || true
        fi
    fi
    edge_count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["edges"]))' "$resdir/native.canon.json" 2>/dev/null || echo '?')"
    if [ "$log_ok" -eq 1 ]; then
        echo "PASS: $name (erlang == elixir == oracle-native == oracle-wasm, $edge_count edges)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL: $name (see divergence above)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo "== oracle_check: $PASS_COUNT passed, $FAIL_COUNT failed (workdir: $WORKDIR) =="
if [ "$FAIL_COUNT" -ne 0 ]; then
    echo "ORACLE_CHECK: FAIL"
    exit 1
fi
[ "$PASS_COUNT" -ge 6 ] || fail_now "battery too small: only $PASS_COUNT logs ran (>= 6 required)"
echo "ORACLE_CHECK: PASS"
