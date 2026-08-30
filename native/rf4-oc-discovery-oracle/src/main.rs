//! rf4-oc-discovery-oracle: real oracle over rust4pm's (process_mining 0.6.2) OCEL 2.0
//! JSON importer + `SlimLinkedOCEL::from_ocel` + object-centric discovery
//! (`get_dfg_of_object_type`, `get_variants_of_object_type`).
//!
//! ## Real-function ground truth (read from the crate's own vendored source under
//! `~/.cargo/registry/src/.../process_mining-0.6.2/src`, not guessed)
//!
//! * `process_mining::discovery::object_centric::dfg::get_dfg_of_object_type(ocel:
//!   &SlimLinkedOCEL, ob_type: String) -> Vec<((String, String), usize)>` --
//!   `src/discovery/object_centric/dfg.rs`. Each entry is `((from_activity, to_activity),
//!   count)`, counting adjacent pairs in each object's timestamp-ordered activity trace.
//!   Sorted by count descending, ties broken by `(from, to)`.
//! * `process_mining::discovery::object_centric::variants::get_variants_of_object_type(ocel:
//!   &SlimLinkedOCEL, ob_type: String) -> Vec<(Vec<String>, usize)>` --
//!   `src/discovery/object_centric/variants.rs`. Each entry is `(activity_trace, count)`.
//!   Sorted by count descending, ties broken by the trace itself.
//! * Neither function nor their containing `discovery`/`discovery::object_centric` modules
//!   are feature-gated (`src/lib.rs:27` is a bare `pub mod discovery;`, and
//!   `discovery/object_centric/mod.rs` carries no `#[cfg(feature = ...)]`) -- unlike
//!   `process_mining::bindings` (which IS `#![cfg(feature = "bindings")]`, the feature
//!   rf3-ocel-oracle enables for a different purpose). This crate's `Cargo.toml` does NOT
//!   enable `"bindings"`; it was confirmed unnecessary by reading the source, not assumed.
//! * The real OCEL 2.0 JSON importer is
//!   `process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_path`
//!   (`Fn(path) -> Result<OCEL, std::io::Error>`, `ocel_json/mod.rs:52`).
//! * `SlimLinkedOCEL::from_ocel(OCEL) -> Self` is the real, only public constructor from an
//!   already-imported `OCEL` (`linked_ocel/slim_linked_ocel.rs:639`). **Corrected from the
//!   task's stated ground truth**: `SlimLinkedOCEL` is NOT re-exported at the
//!   `process_mining` crate root -- `src/lib.rs`'s re-export block (lines 30-46) re-exports
//!   `OCEL` (via `pub use core::{EventLog, PetriNet, OCEL};`, line 33) but never mentions
//!   `SlimLinkedOCEL`. Verified by grepping `lib.rs` directly; the real, only usable import
//!   path is the full one used below
//!   (`process_mining::core::event_data::object_centric::linked_ocel::SlimLinkedOCEL`), the
//!   same path rf3-ocel-oracle already uses successfully.
//!
//! ## Wire contract (FIXED)
//!
//! ```text
//! in:  {"op":"oc_dfg_discover","ocel_path":"<path>","ob_type":"<type>"}
//! out: {"edges":[{"source":s,"target":t,"frequency":n}, ...]}
//!      (sorted exactly as get_dfg_of_object_type returns it -- count descending, ties by
//!      (source, target); NOT re-sorted here)
//!
//! in:  {"op":"oc_variants_discover","ocel_path":"<path>","ob_type":"<type>"}
//! out: {"variants":[{"trace":[...],"count":n}, ...]}
//!      (sorted exactly as get_variants_of_object_type returns it -- count descending, ties
//!      by trace; NOT re-sorted here)
//! ```
//!
//! Exit 0 on success. Exit nonzero with a `stderr` reason for: malformed input JSON, an
//! unknown `op`, a missing/empty `ocel_path` or `ob_type`, or an unreadable/unparseable OCEL
//! JSON file (the real `std::io::Error` from `import_ocel_json_path` is surfaced verbatim,
//! never swallowed).
//!
//! ## Division of labor
//!
//! This adapter is ONLY a wire-format layer over the real crate calls. The real OCEL 2.0
//! JSON import, `SlimLinkedOCEL` linking, and object-centric DFG/variant discovery are all
//! performed by `process_mining` itself (`import_ocel_json_path`, `SlimLinkedOCEL::from_ocel`,
//! `get_dfg_of_object_type`, `get_variants_of_object_type`) -- no algorithm is
//! re-implemented here.

use std::io::Read;
use std::process::ExitCode;

use serde::Deserialize;
use serde_json::{json, Value};

use process_mining::core::event_data::object_centric::linked_ocel::SlimLinkedOCEL;
use process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_path;
use process_mining::discovery::object_centric::dfg::get_dfg_of_object_type;
use process_mining::discovery::object_centric::variants::get_variants_of_object_type;
use process_mining::OCEL;

#[derive(Deserialize)]
struct WireInput {
    op: String,
    ocel_path: Option<String>,
    ob_type: Option<String>,
}

fn main() -> ExitCode {
    let mut raw = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut raw) {
        eprintln!("rf4-oc-discovery-oracle: failed to read stdin: {e}");
        return ExitCode::from(1);
    }

    let input: WireInput = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("rf4-oc-discovery-oracle: malformed input JSON: {e}");
            return ExitCode::from(1);
        }
    };

    let ocel_path = match input.ocel_path {
        Some(p) if !p.is_empty() => p,
        _ => {
            eprintln!("rf4-oc-discovery-oracle: op {:?} requires a non-empty \"ocel_path\"", input.op);
            return ExitCode::from(1);
        }
    };
    let ob_type = match input.ob_type {
        Some(t) if !t.is_empty() => t,
        _ => {
            eprintln!("rf4-oc-discovery-oracle: op {:?} requires a non-empty \"ob_type\"", input.op);
            return ExitCode::from(1);
        }
    };

    match input.op.as_str() {
        "oc_dfg_discover" => match oc_dfg_discover(&ocel_path, &ob_type) {
            Ok(out) => {
                println!("{out}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("rf4-oc-discovery-oracle: oc_dfg_discover failed for {ocel_path:?}: {e}");
                ExitCode::from(2)
            }
        },
        "oc_variants_discover" => match oc_variants_discover(&ocel_path, &ob_type) {
            Ok(out) => {
                println!("{out}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!(
                    "rf4-oc-discovery-oracle: oc_variants_discover failed for {ocel_path:?}: {e}"
                );
                ExitCode::from(2)
            }
        },
        other => {
            eprintln!(
                "rf4-oc-discovery-oracle: unknown op {other:?} (supported: \"oc_dfg_discover\", \"oc_variants_discover\")"
            );
            ExitCode::from(1)
        }
    }
}

/// Import the real `OCEL` at `ocel_path` and link it into a real `SlimLinkedOCEL` --
/// shared by both ops. The `std::io::Error` from `import_ocel_json_path` (a nonexistent
/// path, or a present-but-unparseable OCEL JSON file) is surfaced verbatim via its `Display`
/// impl, never swallowed or wrapped in a different message.
fn import_slim(ocel_path: &str) -> Result<SlimLinkedOCEL, std::io::Error> {
    let ocel: OCEL = import_ocel_json_path(ocel_path)?;
    Ok(SlimLinkedOCEL::from_ocel(ocel))
}

/// op: oc_dfg_discover. Wraps the REAL
/// `process_mining::discovery::object_centric::dfg::get_dfg_of_object_type` verbatim; no
/// re-sorting, re-counting, or filtering is applied to its output.
fn oc_dfg_discover(ocel_path: &str, ob_type: &str) -> Result<Value, std::io::Error> {
    let slim = import_slim(ocel_path)?;
    let edges = get_dfg_of_object_type(&slim, ob_type.to_string());
    Ok(json!({
        "edges": edges.into_iter().map(|((source, target), frequency)| {
            json!({"source": source, "target": target, "frequency": frequency})
        }).collect::<Vec<Value>>(),
    }))
}

/// op: oc_variants_discover. Wraps the REAL
/// `process_mining::discovery::object_centric::variants::get_variants_of_object_type`
/// verbatim; no re-sorting, re-counting, or filtering is applied to its output.
fn oc_variants_discover(ocel_path: &str, ob_type: &str) -> Result<Value, std::io::Error> {
    let slim = import_slim(ocel_path)?;
    let variants = get_variants_of_object_type(&slim, ob_type.to_string());
    Ok(json!({
        "variants": variants.into_iter().map(|(trace, count)| {
            json!({"trace": trace, "count": count})
        }).collect::<Vec<Value>>(),
    }))
}

// -- Chicago-style tests: real fixture file, real process_mining calls, state-based
// assertions. No mocking of any kind -- `import_slim`/`oc_dfg_discover`/
// `oc_variants_discover` above call straight through to the real process_mining crate; these
// tests call those same functions in-process (no subprocess spawn needed since the op-dispatch
// logic is already factored into plain functions main() also calls) against the real fixture
// file on disk.
#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str =
        "/Users/sac/beam4pm/qualification/fixtures/positive-self-authored.ocel.json";

    /// Hand-computed expectation from the task's fixture walkthrough: object `order-1`
    /// (type Order) has activity trace ["Create Order", "Ship Order"] (2 events -> 1
    /// adjacent pair); object `item-1` (type Item) has activity trace ["Ship Order"] (1
    /// event -> 0 adjacent pairs, hence an empty DFG for "Item").
    #[test]
    fn oc_dfg_discover_order_matches_hand_computation() {
        let out = oc_dfg_discover(FIXTURE, "Order").expect("real fixture must import cleanly");
        assert_eq!(
            out,
            json!({"edges": [{"source": "Create Order", "target": "Ship Order", "frequency": 1}]})
        );
    }

    #[test]
    fn oc_dfg_discover_item_is_empty_single_event_trace_has_no_adjacent_pairs() {
        let out = oc_dfg_discover(FIXTURE, "Item").expect("real fixture must import cleanly");
        assert_eq!(out, json!({"edges": []}));
    }

    #[test]
    fn oc_variants_discover_order_matches_hand_computation() {
        let out =
            oc_variants_discover(FIXTURE, "Order").expect("real fixture must import cleanly");
        assert_eq!(
            out,
            json!({"variants": [{"trace": ["Create Order", "Ship Order"], "count": 1}]})
        );
    }

    #[test]
    fn oc_variants_discover_item_matches_hand_computation() {
        let out =
            oc_variants_discover(FIXTURE, "Item").expect("real fixture must import cleanly");
        assert_eq!(out, json!({"variants": [{"trace": ["Ship Order"], "count": 1}]}));
    }

    /// Real error path: a nonexistent ocel_path must produce a real `Err(std::io::Error)`
    /// from `import_ocel_json_path` (surfaced through `import_slim`), never a panic.
    #[test]
    fn nonexistent_ocel_path_is_a_real_error_not_a_panic() {
        let dfg_result = oc_dfg_discover("/Users/sac/beam4pm/qualification/fixtures/does-not-exist.ocel.json", "Order");
        assert!(dfg_result.is_err(), "expected a real io::Error, got {dfg_result:?}");

        let variants_result = oc_variants_discover(
            "/Users/sac/beam4pm/qualification/fixtures/does-not-exist.ocel.json",
            "Order",
        );
        assert!(
            variants_result.is_err(),
            "expected a real io::Error, got {variants_result:?}"
        );
    }
}
