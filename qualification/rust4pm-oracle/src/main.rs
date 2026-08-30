//! rust4pm-oracle: differential-testing oracle for beam4pm DFG discovery.
//!
//! Wire contract (FIXED):
//!   stdin:  {"case_attr_key": "<string>",
//!            "events": [{"event_id": s, "event_type": s, "event_time": s,
//!                        "attributes": {..}}, ...]}
//!   stdout: {"edges": [{"source_activity": s, "target_activity": s,
//!                       "frequency": n}, ...]}
//!           sorted by source_activity then target_activity; nothing else.
//!   exit:   0 on success; nonzero with a stderr reason on malformed input.
//!
//! Division of labor: this adapter only maps the wire format into the
//! `process_mining` crate's own `EventLog` representation (traces grouped by
//! `case_attr_key`, events sorted by (event_time, event_id) exactly per
//! beam4pm's generated `beam4pm_discovery:traces_from_events/2`). The
//! directly-follows COUNTING is performed by the crate's own
//! `process_mining::discovery::case_centric::dfg::discover_dfg` — the
//! canonical rust4pm algorithm — not re-implemented here.

use std::collections::BTreeMap;
use std::io::Read;
use std::process::ExitCode;

use serde::Deserialize;
use serde_json::Value;

use process_mining::core::event_data::case_centric::{
    Attribute, AttributeValue, Event, Trace,
};
use process_mining::discovery::case_centric::dfg::discover_dfg;
use process_mining::EventLog;

/// `concept:name` — the XES activity key `Event::new` also uses; declared
/// here only for the trace-level case-id attribute we attach for fidelity.
const TRACE_CONCEPT_NAME: &str = "concept:name";

#[derive(Deserialize)]
struct WireInput {
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

    // THE ALGORITHM: rust4pm's own DFG discovery does all the counting.
    let dfg = discover_dfg(&log);

    // Project the crate's DirectlyFollowsGraph onto the fixed wire output,
    // sorted by source_activity then target_activity.
    let mut edges: Vec<(String, String, u32)> = dfg
        .directly_follows_relations
        .iter()
        .map(|((source, target), freq)| (source.to_string(), target.to_string(), *freq))
        .collect();
    edges.sort();

    let out = Value::Object(
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
    );

    println!("{out}");
    ExitCode::SUCCESS
}
