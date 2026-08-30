//! rf3-ocel-oracle: differential-testing oracle for
//! `process_mining::bindings::slim_ocel_bindings` (STREAM RF3) plus the crate's real OCEL
//! 2.0 JSON importer, run against real wasm4pm OCEL fixtures (including the real
//! negative/adversarial fixtures under `/Users/sac/wasm4pm/fixtures/negative/`).
//!
//! ## Real-function ground truth (discovered by reading process_mining 0.6.2's own
//! vendored source under `~/.cargo/registry/src/.../process_mining-0.6.2/src`, not
//! guessed):
//!
//! * The entire `process_mining::bindings` module is `#![cfg(feature = "bindings")]` —
//!   this oracle's Cargo.toml enables that feature explicitly; without it none of this
//!   compiles.
//! * `process_mining::bindings::slim_ocel_bindings` is a **private** module
//!   (`mod slim_ocel_bindings;`, not `pub mod`) containing **private** `#[register_binding]`
//!   trampoline functions (`locel_new`, `locel_add_event_type`, `locel_add_object_type`,
//!   `locel_add_event`, `locel_add_object`, `locel_add_e2o`, `locel_add_o2o`,
//!   `locel_construct_ocel`, ...). They are reachable only through the crate's dynamic
//!   binding-call registry (`bindings::call`/`list_functions`), not as plain Rust API. Each
//!   trampoline is a one-line, zero-extra-logic wrapper around a real **public** inherent
//!   method of `SlimLinkedOCEL` (e.g. `locel_add_event_type` is exactly
//!   `ocel.add_event_type(&event_type, attributes)`). This oracle exercises the real
//!   `SlimLinkedOCEL` methods directly — the identical code path the private trampolines
//!   call into — since that is the only way to run this construction path as plain Rust
//!   without also standing up the crate's dynamic binding-call machinery.
//! * `num_events`, `num_objects`, and `ocel_type_stats` (the three stat functions the task
//!   spec named) ARE real, `pub`, directly-callable functions — but they live at the TOP of
//!   `process_mining::bindings` itself (`src/bindings/mod.rs`), not inside
//!   `slim_ocel_bindings.rs`. So is `slim_link_ocel(&OCEL) -> SlimLinkedOCEL`, the exact
//!   `SlimLinkedOCEL::from_ocel(ocel.clone())` conversion. All four are used here verbatim.
//! * The real OCEL 2.0 JSON importer is
//!   `process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_path`
//!   (there is no `import_ocel_json` re-exported at the crate root under that name).
//!
//! ## Wire contract (FIXED)
//!
//! One JSON object on stdin, one JSON object on stdout, always well-formed JSON on
//! success (`exit 0`) -- including a *discovered* domain outcome (a structurally
//! malformed OCEL fixture, a duplicate id silently dropped, an undeclared type silently
//! auto-declared). Exit nonzero with a stderr reason only for a WIRE-level problem this
//! oracle cannot even attempt to answer (malformed stdin JSON, unknown `op`, missing
//! required field, `ocel_path` that does not exist on disk).
//!
//! ```text
//! in:  {"op":"ocel_stats","ocel_path":"<path>"}
//! out: {"ok":true,
//!       "num_events":N,"num_objects":N,"type_stats":{"event_type_counts":{...},
//!         "object_type_counts":{...}},
//!       "raw":{...plain-OCEL-struct diagnostics, no dedup/validation applied...},
//!       "reconstructed":{...post round-trip diagnostics...}}
//!      | {"ok":false,"error":"ocel_json_import_failed","detail":"<serde/io display>"}
//!
//! in:  {"op":"ocel_build_slim"}
//! out: {"ok":true,
//!       "built":{"num_events":2,"num_objects":2,"type_stats":{...},
//!                "e2o_relationship_count":3,"o2o_relationship_count":1},
//!       "reconstructed_ocel":{"num_events":2,"num_objects":2,
//!                              "e2o_relationship_count":3,"o2o_relationship_count":1},
//!       "roundtrip":{"num_events":2,"num_objects":2,"type_stats":{...}}}
//! ```

use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;
use std::path::Path;
use std::process::ExitCode;

use chrono::{DateTime, FixedOffset, TimeZone, Utc};
use serde::Deserialize;
use serde_json::{json, Value};

use process_mining::bindings::{num_events, num_objects, ocel_type_stats, slim_link_ocel};
use process_mining::core::event_data::object_centric::linked_ocel::{
    LinkedOCELAccess, SlimLinkedOCEL,
};
use process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_path;
use process_mining::OCEL;

#[derive(Deserialize)]
#[serde(tag = "op")]
enum WireInput {
    #[serde(rename = "ocel_stats")]
    OcelStats { ocel_path: String },
    #[serde(rename = "ocel_build_slim")]
    OcelBuildSlim {},
}

fn main() -> ExitCode {
    let mut raw = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut raw) {
        eprintln!("rf3-ocel-oracle: failed to read stdin: {e}");
        return ExitCode::from(1);
    }

    let input: WireInput = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("rf3-ocel-oracle: malformed wire input JSON: {e}");
            return ExitCode::from(1);
        }
    };

    match input {
        WireInput::OcelStats { ocel_path } => run_ocel_stats(&ocel_path),
        WireInput::OcelBuildSlim {} => run_ocel_build_slim(),
    }
}

// -- op: ocel_stats ----------------------------------------------------------------

fn run_ocel_stats(ocel_path: &str) -> ExitCode {
    let path = Path::new(ocel_path);
    if !path.exists() {
        eprintln!("rf3-ocel-oracle: ocel_path does not exist: {ocel_path}");
        return ExitCode::from(1);
    }

    // THE REAL IMPORTER: process_mining's own OCEL 2.0 JSON deserializer. Note what it
    // does NOT do: it is a plain `serde_json::from_reader` into `Vec<OCELEvent>` /
    // `Vec<OCELObject>` -- no duplicate-id check, no declared-type check, no referential
    // integrity check on relationships. Those checks (or their absence) only appear once
    // the plain `OCEL` is converted into a `SlimLinkedOCEL` below.
    let ocel: OCEL = match import_ocel_json_path(path) {
        Ok(o) => o,
        Err(e) => {
            println!(
                "{}",
                json!({"ok": false, "error": "ocel_json_import_failed", "detail": e.to_string()})
            );
            return ExitCode::SUCCESS;
        }
    };

    let raw = raw_diagnostics(&ocel);

    // THE REAL CONSTRUCTION PATH: process_mining::bindings::slim_link_ocel is the exact
    // public wrapper around `SlimLinkedOCEL::from_ocel(ocel.clone())` -- same function the
    // (private) `locel_*` binding trampolines exist to expose dynamically.
    let slim: SlimLinkedOCEL = slim_link_ocel(&ocel);
    let slim_num_events = num_events(&slim);
    let slim_num_objects = num_objects(&slim);
    let slim_stats = ocel_type_stats(&slim);

    // THE REAL locel_construct_ocel PATH: SlimLinkedOCEL::construct_ocel is exactly what
    // the private `locel_construct_ocel` binding trampoline calls.
    let reconstructed: OCEL = slim.construct_ocel();
    let reconstructed_diag = relationship_diagnostics(&reconstructed);

    let out = json!({
        "ok": true,
        "num_events": slim_num_events,
        "num_objects": slim_num_objects,
        "type_stats": {
            "event_type_counts": slim_stats.event_type_counts,
            "object_type_counts": slim_stats.object_type_counts,
        },
        "raw": raw,
        "reconstructed": {
            "num_events": reconstructed.events.len(),
            "num_objects": reconstructed.objects.len(),
            "e2o_relationship_count": reconstructed_diag.0,
            "o2o_relationship_count": reconstructed_diag.1,
        },
    });
    println!("{out}");
    ExitCode::SUCCESS
}

/// Diagnostics computed from the PLAIN `OCEL` struct as `import_ocel_json_path` returns
/// it -- before any `SlimLinkedOCEL` construction, so with zero dedup/validation applied.
fn raw_diagnostics(ocel: &OCEL) -> Value {
    let distinct_event_ids: BTreeSet<&str> = ocel.events.iter().map(|e| e.id.as_str()).collect();
    let distinct_object_ids: BTreeSet<&str> =
        ocel.objects.iter().map(|o| o.id.as_str()).collect();

    let declared_event_types: BTreeSet<&str> =
        ocel.event_types.iter().map(|t| t.name.as_str()).collect();
    let declared_object_types: BTreeSet<&str> = ocel
        .object_types
        .iter()
        .map(|t| t.name.as_str())
        .collect();

    let observed_event_types: BTreeSet<&str> =
        ocel.events.iter().map(|e| e.event_type.as_str()).collect();
    let observed_object_types: BTreeSet<&str> = ocel
        .objects
        .iter()
        .map(|o| o.object_type.as_str())
        .collect();

    let undeclared_event_types_used: Vec<&str> = observed_event_types
        .difference(&declared_event_types)
        .copied()
        .collect();
    let undeclared_object_types_used: Vec<&str> = observed_object_types
        .difference(&declared_object_types)
        .copied()
        .collect();

    let mut event_type_counts: BTreeMap<&str, usize> = BTreeMap::new();
    for e in &ocel.events {
        *event_type_counts.entry(e.event_type.as_str()).or_insert(0) += 1;
    }
    let mut object_type_counts: BTreeMap<&str, usize> = BTreeMap::new();
    for o in &ocel.objects {
        *object_type_counts
            .entry(o.object_type.as_str())
            .or_insert(0) += 1;
    }

    let (e2o_relationship_count, o2o_relationship_count) = relationship_diagnostics(ocel);

    json!({
        "num_events": ocel.events.len(),
        "num_objects": ocel.objects.len(),
        "distinct_event_ids": distinct_event_ids.len(),
        "distinct_object_ids": distinct_object_ids.len(),
        "declared_event_types": declared_event_types,
        "declared_object_types": declared_object_types,
        "observed_event_types": observed_event_types,
        "undeclared_event_types_used": undeclared_event_types_used,
        "undeclared_object_types_used": undeclared_object_types_used,
        "event_type_counts": event_type_counts,
        "object_type_counts": object_type_counts,
        "e2o_relationship_count": e2o_relationship_count,
        "o2o_relationship_count": o2o_relationship_count,
    })
}

/// `(e2o_relationship_count, o2o_relationship_count)` for any `OCEL` (raw-imported or
/// reconstructed via `SlimLinkedOCEL::construct_ocel`).
fn relationship_diagnostics(ocel: &OCEL) -> (usize, usize) {
    let e2o: usize = ocel.events.iter().map(|e| e.relationships.len()).sum();
    let o2o: usize = ocel.objects.iter().map(|o| o.relationships.len()).sum();
    (e2o, o2o)
}

// -- op: ocel_build_slim -------------------------------------------------------------

fn ts(rfc3339: &str) -> DateTime<FixedOffset> {
    DateTime::parse_from_rfc3339(rfc3339)
        .unwrap_or_else(|_| Utc.timestamp_opt(0, 0).unwrap().fixed_offset())
}

/// Build a tiny real 2-event/2-object `SlimLinkedOCEL` PROGRAMMATICALLY -- exercising the
/// exact same `SlimLinkedOCEL` methods the private `locel_new`/`locel_add_event_type`/
/// `locel_add_object_type`/`locel_add_event`/`locel_add_object`/`locel_add_e2o`/
/// `locel_add_o2o` binding trampolines wrap 1:1 -- then reconstructs it back to a full
/// `OCEL` via `construct_ocel` (== `locel_construct_ocel`), then re-links the
/// reconstructed `OCEL` back into a fresh `SlimLinkedOCEL` via `slim_link_ocel` and
/// re-measures it: a real round-trip proof (build -> flatten -> re-link -> re-measure),
/// not just a single one-way conversion.
fn run_ocel_build_slim() -> ExitCode {
    // locel_new()
    let mut slim = SlimLinkedOCEL::new();

    // locel_add_event_type() x2, locel_add_object_type() x2 -- no attributes, matching
    // this oracle's own tiny fixture (attribute round-tripping is exercised separately by
    // the ocel_stats op against real fixture files).
    slim.add_event_type("CreateOrder", vec![]);
    slim.add_event_type("ShipOrder", vec![]);
    slim.add_object_type("Order", vec![]);
    slim.add_object_type("Item", vec![]);

    // locel_add_object() x2
    let order_idx = slim
        .add_object("Order", Some("order-1".to_string()), vec![], vec![])
        .expect("Order type was just declared above");
    let item_idx = slim
        .add_object("Item", Some("item-1".to_string()), vec![], vec![])
        .expect("Item type was just declared above");

    // locel_add_event() x2 -- e1 carries its E2O to `order-1` inline via the
    // `relationships` positional argument; e2 is added with zero inline relationships so
    // its E2O links can be exercised via locel_add_e2o below instead.
    let _e1_idx = slim
        .add_event(
            "CreateOrder",
            ts("2026-05-01T09:00:00Z"),
            Some("e1".to_string()),
            vec![],
            vec![("order".to_string(), order_idx)],
        )
        .expect("CreateOrder type was just declared above");
    let e2_idx = slim
        .add_event(
            "ShipOrder",
            ts("2026-05-01T10:00:00Z"),
            Some("e2".to_string()),
            vec![],
            vec![],
        )
        .expect("ShipOrder type was just declared above");

    // locel_add_e2o() x2
    let e2o_1 = slim.add_e2o(e2_idx, order_idx, "order".to_string());
    let e2o_2 = slim.add_e2o(e2_idx, item_idx, "item".to_string());

    // locel_add_o2o() x1
    let o2o_1 = slim.add_o2o(order_idx, item_idx, "contains".to_string());

    let built_num_events = num_events(&slim);
    let built_num_objects = num_objects(&slim);
    let built_stats = ocel_type_stats(&slim);
    let built_e2o: usize = [e2o_1, e2o_2].iter().filter(|ok| **ok).count() + 1; // +1 for e1's inline relationship
    let built_o2o: usize = usize::from(o2o_1);

    // locel_construct_ocel()
    let reconstructed: OCEL = slim.construct_ocel();
    let (reconstructed_e2o, reconstructed_o2o) = relationship_diagnostics(&reconstructed);

    // Round-trip: re-link the RECONSTRUCTED OCEL back into a fresh SlimLinkedOCEL via the
    // same real slim_link_ocel function used by the ocel_stats op, then re-measure.
    let roundtrip_slim: SlimLinkedOCEL = slim_link_ocel(&reconstructed);
    let roundtrip_num_events = num_events(&roundtrip_slim);
    let roundtrip_num_objects = num_objects(&roundtrip_slim);
    let roundtrip_stats = ocel_type_stats(&roundtrip_slim);

    let out = json!({
        "ok": true,
        "built": {
            "num_events": built_num_events,
            "num_objects": built_num_objects,
            "type_stats": {
                "event_type_counts": built_stats.event_type_counts,
                "object_type_counts": built_stats.object_type_counts,
            },
            "e2o_relationship_count": built_e2o,
            "o2o_relationship_count": built_o2o,
        },
        "reconstructed_ocel": {
            "num_events": reconstructed.events.len(),
            "num_objects": reconstructed.objects.len(),
            "e2o_relationship_count": reconstructed_e2o,
            "o2o_relationship_count": reconstructed_o2o,
        },
        "roundtrip": {
            "num_events": roundtrip_num_events,
            "num_objects": roundtrip_num_objects,
            "type_stats": {
                "event_type_counts": roundtrip_stats.event_type_counts,
                "object_type_counts": roundtrip_stats.object_type_counts,
            },
        },
    });
    println!("{out}");
    ExitCode::SUCCESS
}
