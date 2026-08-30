//! rf2-conformance-oracle: real conformance-checking oracle for beam4pm RF2.
//!
//! Wire contract (FIXED):
//!   stdin:  {"op":"conformance","xes_path":"<path>","case_attr_key":"concept:name"}
//!   stdout: {"fitness":{"log_fitness":f64,"average_fitness":f64,
//!                       "perfectly_fitting_frac":f64,"total_costs":u64},
//!            "num_variants_aligned":usize,
//!            "model_place_count":usize,
//!            "model_transition_count":usize}
//!   exit:   0 on success; nonzero with a stderr reason on malformed input,
//!           unreadable XES, or an alignment error.
//!
//! Division of labor: this adapter only maps the wire format into real
//! `process_mining` crate calls. THE ALGORITHM (Alpha+++ discovery, the
//! alignment search, and fitness computation) is 100% the canonical
//! rust4pm implementation:
//!   - `EventLog::import_from_path` (real XES importer)
//!   - `log_to_activity_projection` (real activity projection)
//!   - `alphappp_discover_petri_net` (real Alpha+++ discovery, registered
//!     under the binding name `discover_alpha+++`)
//!   - `align_variants` (real optimal alignment search per log variant)
//!   - `compute_fitness` (real fitness statistics over those alignments)
//! Nothing here re-implements or approximates any of the above.

use std::io::Read;
use std::process::ExitCode;

use serde::Deserialize;

use process_mining::conformance::alignments::{align_variants, compute_fitness, AlignmentOptions};
use process_mining::core::event_data::case_centric::utils::activity_projection::log_to_activity_projection;
use process_mining::discovery::case_centric::alphappp::full::{
    alphappp_discover_petri_net, AlphaPPPConfig,
};
use process_mining::{EventLog, Importable};

/// Thin, named wrapper over the real `EventLog::import_from_path` so the
/// two import sites (log-to-align, log-to-discover-from) share one path
/// instead of two ad hoc copies.
fn import_xes(path: &str) -> Result<EventLog, Box<dyn std::error::Error>> {
    EventLog::import_from_path(path).map_err(|e| e.into())
}

/// Redirects the process's real stdout file descriptor (1) to stderr (2)
/// for the duration of `f`, then restores it. The `process_mining` crate's
/// own `alphappp_discover_petri_net` calls raw `println!` internally
/// (progress/diagnostic lines — not part of any documented API contract);
/// without this, those lines would corrupt the single-JSON-line wire
/// contract this oracle promises on stdout. This does not touch what `f`
/// computes — only which fd its incidental `println!` calls land on.
fn with_stdout_silenced<T>(f: impl FnOnce() -> T) -> T {
    unsafe {
        let saved_stdout = libc::dup(1);
        libc::dup2(2, 1);
        let result = f();
        libc::dup2(saved_stdout, 1);
        libc::close(saved_stdout);
        result
    }
}

#[derive(Deserialize)]
struct WireInput {
    op: String,
    xes_path: String,
    #[serde(default = "default_case_attr_key")]
    #[allow(dead_code)]
    case_attr_key: String,
    /// Optional: discover the Petri net from a DIFFERENT log than the one
    /// being aligned. Defaults to `xes_path` itself (the check-step shape:
    /// discover from receipt.xes, align receipt.xes's own variants). The
    /// falsify step sets this to the clean log's path while `xes_path`
    /// points at a mutated copy, so alignment runs against the SAME fixed
    /// model the clean run used — this is what makes "an activity name
    /// that cannot appear in the discovered model" literally true, rather
    /// than re-discovering a new model that would happily learn a fresh
    /// transition for the mutated activity and mask the defect.
    #[serde(default)]
    model_xes_path: Option<String>,
}

fn default_case_attr_key() -> String {
    "concept:name".to_string()
}

fn main() -> ExitCode {
    let mut raw = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut raw) {
        eprintln!("rf2-conformance-oracle: failed to read stdin: {e}");
        return ExitCode::from(1);
    }

    let input: WireInput = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("rf2-conformance-oracle: malformed input JSON: {e}");
            return ExitCode::from(1);
        }
    };

    if input.op != "conformance" {
        eprintln!(
            "rf2-conformance-oracle: unsupported op {:?} (only \"conformance\" is supported)",
            input.op
        );
        return ExitCode::from(1);
    }

    // 1. Real XES import of the log to ALIGN — the case_centric
    //    case-based classifier reads `concept:name` for the activity label
    //    by default, matching `case_attr_key`. process_mining's own
    //    trace/event grouping and ordering rules apply unmodified (no
    //    re-implementation here).
    let log: EventLog = match import_xes(&input.xes_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!(
                "rf2-conformance-oracle: failed to import XES at {:?}: {e}",
                input.xes_path
            );
            return ExitCode::from(1);
        }
    };
    let projection = log_to_activity_projection(&log);

    // 2. Real XES import + activity projection of the log to DISCOVER THE
    //    MODEL FROM. Defaults to the same log (check-step shape). Only
    //    imported a second time when `model_xes_path` differs, so the
    //    common (check-step) path pays no extra cost.
    let model_projection = match &input.model_xes_path {
        Some(p) if p != &input.xes_path => {
            let model_log = match import_xes(p) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("rf2-conformance-oracle: failed to import model XES at {p:?}: {e}");
                    return ExitCode::from(1);
                }
            };
            log_to_activity_projection(&model_log)
        }
        _ => projection.clone(),
    };

    // 3. Real Alpha+++ discovery over the MODEL log's activity projection —
    //    no hand-built Petri net anywhere in this pipeline.
    let net = with_stdout_silenced(|| {
        alphappp_discover_petri_net(&model_projection, AlphaPPPConfig::default())
    });

    // 4. Real optimal alignment search, one alignment per log variant.
    // receipt.xes (RequestForPayment/DomesticDeclarations-scale real logs
    // with long traces) can exceed the crate's default 100_000-state cap
    // during search (`AlignmentError::SearchError(LimitReached)`) — this
    // is the crate's OWN real search-space limiter, not a bug; raise it
    // rather than silently downgrading to a partial/fake result.
    let options = AlignmentOptions {
        max_states: Some(5_000_000),
        ..AlignmentOptions::default()
    };
    let align_results = align_variants(&net, &projection, &options);
    let num_variants_aligned = align_results.len();

    // 5. Real fitness computation over those real alignments.
    let fitness = match compute_fitness(&align_results, &net, &options) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("rf2-conformance-oracle: compute_fitness failed: {e:?}");
            return ExitCode::from(1);
        }
    };

    let out = serde_json::json!({
        "fitness": {
            "log_fitness": fitness.log_fitness,
            "average_fitness": fitness.average_fitness,
            "perfectly_fitting_frac": fitness.perfectly_fitting_frac,
            "total_costs": fitness.total_costs,
        },
        "num_variants_aligned": num_variants_aligned,
        "model_place_count": net.places.len(),
        "model_transition_count": net.transitions.len(),
    });

    println!("{out}");
    ExitCode::SUCCESS
}
