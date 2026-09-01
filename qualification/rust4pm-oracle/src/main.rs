//! rust4pm-oracle: differential-testing oracle for beam4pm DFG and POWL
//! discovery.
//!
//! Wire contract (FIXED):
//!   stdin:  {"op": "dfg" | "powl",             (optional, default "dfg")
//!            "case_attr_key": "<string>",
//!            "events": [{"event_id": s, "event_type": s, "event_time": s,
//!                        "attributes": {..}}, ...]}
//!
//!   `op` omitted or "dfg" — stdout:
//!     {"edges": [{"source_activity": s, "target_activity": s,
//!                 "frequency": n}, ...]}
//!     sorted by source_activity then target_activity; nothing else.
//!
//!   `op: "powl"` — stdout:
//!     {"powl": <the discovered `Powl` struct, serde-serialized as-is>}
//!     `Powl`/`PowlNode` derive `Serialize` in the fork
//!     (`process_mining::core::process_models::case_centric::powl`); this
//!     adapter emits that struct verbatim (wrapped in a top-level "powl"
//!     key) rather than a hand-rolled projection, so the wire output is
//!     exactly what `discover_powl` produced — nothing normalized away.
//!
//!   exit:   0 on success; nonzero with a stderr reason on malformed input
//!           (including an unrecognized "op" value).
//!
//! Backward compatibility: any existing caller that omits "op" entirely
//! gets the original DFG-only wire behavior unchanged.
//!
//! Division of labor: this adapter only maps the wire format into the
//! `process_mining` crate's own `EventLog` representation (traces grouped by
//! `case_attr_key`, events sorted by (event_time, event_id) exactly per
//! beam4pm's generated `beam4pm_discovery:traces_from_events/2`). The
//! directly-follows COUNTING is performed by the crate's own
//! `process_mining::discovery::case_centric::dfg::discover_dfg`, and the
//! POWL discovery is performed by the crate's own
//! `process_mining::discovery::case_centric::powl::discover_powl` — both the
//! canonical rust4pm algorithms — not re-implemented here.

use std::collections::BTreeMap;
use std::io::Read;
use std::process::ExitCode;

use serde::Deserialize;
use serde_json::Value;

use process_mining::core::event_data::case_centric::{
    Attribute, AttributeValue, Event, Trace,
};
use process_mining::discovery::case_centric::dfg::discover_dfg;
use process_mining::discovery::case_centric::powl::discover_powl;
use process_mining::EventLog;

/// `concept:name` — the XES activity key `Event::new` also uses; declared
/// here only for the trace-level case-id attribute we attach for fidelity.
const TRACE_CONCEPT_NAME: &str = "concept:name";

#[derive(Deserialize)]
struct WireInput {
    #[serde(default)]
    op: Option<String>,
    case_attr_key: String,
    events: Vec<WireEvent>,
}

#[derive(Deserialize)]
struct WireEvent {
    event_id: String,
    event_type: String,
    event_time: String,
    #[serde(default)]
    attributes: Option<Value>,
}

fn main() -> ExitCode {
    let mut raw = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut raw) {
        eprintln!("rust4pm-oracle: failed to read stdin: {e}");
        return ExitCode::from(1);
    }

    let input: WireInput = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("rust4pm-oracle: malformed input JSON: {e}");
            return ExitCode::from(1);
        }
    };

    let op = input.op.clone().unwrap_or_else(|| "dfg".to_string());
    if op != "dfg" && op != "powl" {
        eprintln!("rust4pm-oracle: unrecognized op {op:?} (expected \"dfg\" or \"powl\")");
        return ExitCode::from(1);
    }

    // Group events by the case-id value found at `case_attr_key` in each
    // event's attributes map. Mirrors beam4pm_discovery:traces_from_events/2:
    // events with absent/undefined attributes or without the key are SKIPPED
    // (not an error). An attributes value that is present but not a JSON
    // object violates the ocel_event schema and is rejected as malformed.
    //
    // BTreeMap keys the cases by the case-id's canonical JSON encoding, which
    // is injective over JSON values (a string "x" encodes as "\"x\"", distinct
    // from a bare number/bool), and yields deterministic trace order. Trace
    // order does not affect DFG edge counts.
    let mut by_case: BTreeMap<String, Vec<(String, String, String)>> = BTreeMap::new();
    for ev in &input.events {
        let attrs = match &ev.attributes {
            None | Some(Value::Null) => continue,
            Some(Value::Object(m)) => m,
            Some(other) => {
                eprintln!(
                    "rust4pm-oracle: event {}: attributes is not an object (got {})",
                    ev.event_id, other
                );
                return ExitCode::from(1);
            }
        };
        let case_val = match attrs.get(&input.case_attr_key) {
            Some(v) => v,
            None => continue,
        };
        let case_key = match case_val {
            Value::String(s) => format!("\"{s}\""),
            other => other.to_string(),
        };
        by_case.entry(case_key).or_default().push((
            ev.event_time.clone(),
            ev.event_id.clone(),
            ev.event_type.clone(),
        ));
    }

    // Construct the process_mining crate's OWN EventLog representation:
    // one Trace per case; events sorted by (event_time, event_id) — byte-wise
    // lexicographic, identical to Erlang binary ordering of ISO8601 strings
    // with event_id tie-break, per beam4pm's generated discovery semantics.
    let mut log = EventLog::new();
    for (case_key, mut entries) in by_case {
        entries.sort(); // (event_time, event_id, event_type) tuple order
        let mut trace = Trace::new();
        trace.attributes.push(Attribute::new(
            TRACE_CONCEPT_NAME.to_string(),
            AttributeValue::String(case_key),
        ));
        for (_time, _id, event_type) in entries {
            // Event::new stores the activity under the XES `concept:name`
            // key — exactly what the crate's default classifier reads.
            trace.events.push(Event::new(event_type));
        }
        log.traces.push(trace);
    }

    let out = match op.as_str() {
        "powl" => {
            // THE ALGORITHM: rust4pm's own POWL discovery. `Powl` derives
            // `Serialize` in the fork, so this is the real discovered
            // structure serialized as-is, not a hand-rolled projection.
            let powl = discover_powl(&log);
            let powl_json = match serde_json::to_value(&powl) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("rust4pm-oracle: failed to serialize discovered POWL model: {e}");
                    return ExitCode::from(1);
                }
            };
            serde_json::json!({ "powl": powl_json })
        }
        _ => {
            // THE ALGORITHM: rust4pm's own DFG discovery does all the counting.
            let dfg = discover_dfg(&log);

            // Project the crate's DirectlyFollowsGraph onto the fixed wire
            // output, sorted by source_activity then target_activity.
            let mut edges: Vec<(String, String, u32)> = dfg
                .directly_follows_relations
                .iter()
                .map(|((source, target), freq)| (source.to_string(), target.to_string(), *freq))
                .collect();
            edges.sort();

            Value::Object(
                [(
                    "edges".to_string(),
                    Value::Array(
                        edges
                            .into_iter()
                            .map(|(s, t, f)| {
                                serde_json::json!({
                                    "source_activity": s,
                                    "target_activity": t,
                                    "frequency": f,
                                })
                            })
                            .collect(),
                    ),
                )]
                .into_iter()
                .collect(),
            )
        }
    };

    println!("{out}");
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use std::io::Write;
    use std::process::{Command, Stdio};

    /// Runs the built `rust4pm-oracle` release binary against the given
    /// fixture file with the given op, returning stdout as a String.
    /// Requires `cargo build --release` to have already produced the
    /// binary — this is a real subprocess integration test (Chicago style:
    /// the actual binary, actual stdin/stdout pipes), not a mock of the
    /// wire contract.
    fn run_oracle(op: &str, fixture: &str) -> String {
        let manifest_dir = env!("CARGO_MANIFEST_DIR");
        let bin = format!("{manifest_dir}/target/release/rust4pm-oracle");
        let fixture_path = format!("{manifest_dir}/testdata/{fixture}");
        let mut input: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&fixture_path).unwrap_or_else(|e| {
                panic!("failed to read fixture {fixture_path}: {e}")
            }))
            .expect("fixture must be valid JSON");
        input["op"] = serde_json::Value::String(op.to_string());

        let mut child = Command::new(&bin)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap_or_else(|e| {
                panic!("failed to spawn {bin} (run `cargo build --release` first): {e}")
            });
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.to_string().as_bytes())
            .expect("write to oracle stdin");
        let output = child.wait_with_output().expect("wait for oracle");
        assert!(
            output.status.success(),
            "oracle exited nonzero: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).expect("oracle stdout must be UTF-8")
    }

    #[test]
    fn dfg_op_on_seeded_8_events_matches_known_edges() {
        let stdout = run_oracle("dfg", "seeded_8_events.json");
        let parsed: serde_json::Value = serde_json::from_str(&stdout).expect("valid JSON stdout");
        let edges = parsed["edges"].as_array().expect("edges array");
        assert_eq!(edges.len(), 3, "expected 3 DFG edges, got: {stdout}");
        assert_eq!(edges[0]["source_activity"], "receive_order");
        assert_eq!(edges[0]["target_activity"], "ship_order");
        assert_eq!(edges[0]["frequency"], 1);
    }

    #[test]
    fn powl_op_on_concurrent_bc_fixture_discovers_real_structure() {
        let stdout = run_oracle("powl", "concurrent_bc_events.json");
        let parsed: serde_json::Value = serde_json::from_str(&stdout).expect("valid JSON stdout");
        let powl = parsed
            .get("powl")
            .expect("stdout must have a top-level \"powl\" key");
        // Real discovery output, not a stub: the model must be a non-empty
        // JSON object/array with actual node content, and it must NOT be
        // the DFG wire shape.
        assert!(
            powl.is_object() || powl.is_array(),
            "powl output must be a real structured value, got: {stdout}"
        );
        assert!(
            parsed.get("edges").is_none(),
            "powl op must not also emit the dfg wire shape"
        );
        let serialized = powl.to_string();
        assert!(
            !serialized.is_empty() && serialized != "{}" && serialized != "null",
            "powl output must not be empty/stub, got: {stdout}"
        );
    }
}
