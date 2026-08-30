//! rf1-dfg-oracle: real oracle over rust4pm's (process_mining 0.6.2) XES
//! importer + `log_to_activity_projection` + `discover_dfg` +
//! case_centric activity-projection queries.
//!
//! Wire contract (FIXED):
//!   stdin:  {"op":"dfg_discover","xes_path":"<path>"}
//!   stdout: {"edges":[{"source":s,"target":t,"frequency":n}, ...],
//!            "num_cases":N,"num_variants":N,
//!            "top_variant":[...activity names in sequence...],
//!            "activities":[...all activity names, sorted...]}
//!           edges sorted by (source, target); nothing else on stdout.
//!   exit:   0 on success; nonzero with a stderr reason on:
//!             - malformed input JSON / unknown "op"
//!             - a xes_path that does not exist (real fs error surfaced
//!               verbatim from `EventLog::import_from_path`)
//!             - a xes_path that exists but fails to XML/XES-parse (a real
//!               `EventLogIOError::Xes(...)` from rust4pm's own importer)
//!
//! Division of labor (load-bearing, mirrors
//! beam4pm/qualification/rust4pm-oracle's README convention): this adapter
//! only maps the wire format to/from the crate's own types. The REAL XES
//! import, activity projection, and directly-follows-graph discovery are
//! all performed by `process_mining` itself
//! (`EventLog::import_from_path`, `log_to_activity_projection`,
//! `discover_dfg`, `get_num_cases`, `get_num_variants`,
//! `get_projection_activities`, `get_top_n_variants`) -- no algorithm is
//! re-implemented here.

use std::io::Read;
use std::process::ExitCode;

use serde::Deserialize;
use serde_json::Value;

use process_mining::core::event_data::case_centric::utils::activity_projection::{
    get_num_cases, get_num_variants, get_projection_activities, get_top_n_variants,
    log_to_activity_projection,
};
use process_mining::discovery::case_centric::dfg::discover_dfg;
use process_mining::{EventLog, Importable};

#[derive(Deserialize)]
struct WireInput {
    op: String,
    xes_path: Option<String>,
}

fn main() -> ExitCode {
    let mut raw = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut raw) {
        eprintln!("rf1-dfg-oracle: failed to read stdin: {e}");
        return ExitCode::from(1);
    }

    let input: WireInput = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("rf1-dfg-oracle: malformed input JSON: {e}");
            return ExitCode::from(1);
        }
    };

    match input.op.as_str() {
        "dfg_discover" => run_dfg_discover(input.xes_path),
        other => {
            eprintln!("rf1-dfg-oracle: unknown op {other:?} (supported: \"dfg_discover\")");
            ExitCode::from(1)
        }
    }
}

fn run_dfg_discover(xes_path: Option<String>) -> ExitCode {
    let xes_path = match xes_path {
        Some(p) if !p.is_empty() => p,
        _ => {
            eprintln!("rf1-dfg-oracle: dfg_discover requires a non-empty \"xes_path\"");
            return ExitCode::from(1);
        }
    };

    // THE REAL XES IMPORTER: process_mining::EventLog::import_from_path,
    // dispatching on the ".xes" extension to `import_xes` internally
    // (process_mining-0.6.2's `Importable` impl for `EventLog`). A
    // nonexistent path surfaces as a real `EventLogIOError::Io(..)`; a
    // present-but-corrupt/truncated XES file surfaces as a real
    // `EventLogIOError::Xes(XESParseError(..))` -- neither is caught or
    // papered over here.
    let log = match EventLog::import_from_path(&xes_path) {
        Ok(log) => log,
        Err(e) => {
            eprintln!("rf1-dfg-oracle: XES import failed for {xes_path:?}: {e}");
            return ExitCode::from(2);
        }
    };

    // THE REAL ACTIVITY PROJECTION + CASE-CENTRIC QUERIES: all four of
    // these are rust4pm's own public functions over its own
    // `EventLogActivityProjection` -- no counting logic is duplicated here.
    let projection = log_to_activity_projection(&log);
    let num_cases = get_num_cases(&projection);
    let num_variants = get_num_variants(&projection);
    let activities: Vec<String> = {
        let mut acts = get_projection_activities(&projection).to_vec();
        acts.sort();
        acts
    };
    let top_variant: Vec<String> = get_top_n_variants(&projection, 1)
        .into_iter()
        .next()
        .map(|v| v.activities)
        .unwrap_or_default();

    // THE REAL DFG DISCOVERY: process_mining's own
    // discovery::case_centric::dfg::discover_dfg over the imported EventLog
    // (default classifier, i.e. XES `concept:name`).
    let dfg = discover_dfg(&log);

    let mut edges: Vec<(String, String, u32)> = dfg
        .directly_follows_relations
        .iter()
        .map(|((s, t), f)| (s.to_string(), t.to_string(), *f))
        .collect();
    edges.sort();

    let out = serde_json::json!({
        "edges": edges.into_iter().map(|(s, t, f)| {
            serde_json::json!({"source": s, "target": t, "frequency": f})
        }).collect::<Vec<Value>>(),
        "num_cases": num_cases,
        "num_variants": num_variants,
        "top_variant": top_variant,
        "activities": activities,
    });

    println!("{out}");
    ExitCode::SUCCESS
}
