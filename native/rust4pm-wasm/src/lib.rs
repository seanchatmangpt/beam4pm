//! rust4pm-wasm: the real `process_mining` (rust4pm) crate compiled to
//! wasm32-wasip1 behind a plain linear-memory JSON ABI (no wasm-bindgen, no
//! JS glue) so a BEAM host (wasmex/wasmtime) can call it directly. This is
//! the ONE process-mining engine for beam4pm; Elixir/Erlang/Gleam are
//! facades over it and never reimplement any algorithm.
//!
//! Division of labor: this adapter only maps the JSON wire format into real
//! `process_mining` =0.6.2 crate calls. THE ALGORITHMS (XES parsing, DFG
//! discovery, Alpha+++ discovery, PNML parsing, the optimal alignment
//! search, and fitness computation) are 100% the canonical rust4pm
//! implementation:
//!   - `import_xes_slice` (real XES importer, plain and gzip)
//!   - `log_to_activity_projection` + variant helpers (real projection)
//!   - `discover_dfg` (real DFG discovery)
//!   - `alphappp_discover_petri_net` (real Alpha+++ discovery)
//!   - `import_pnml_reader` (real PNML importer, from bytes)
//!   - `align_variants` / `align_trace` (real optimal alignment search)
//!   - `compute_fitness` (real fitness statistics over those alignments)
//! Nothing here re-implements or approximates any of the above. The only
//! wasm-side loops are data plumbing over rust4pm's own structures
//! (per-event iteration for `activities_to_alphabet` / `activity_position`).
//!
//! # Wire contract
//!
//! One dispatch export: `r4pm_call(ptr, len) -> u64` packed as
//! `(out_ptr << 32) | out_len`. Request and response are UTF-8 JSON. Every
//! failure returns the single-key object `{"error":"<string>"}`; per-variant
//! alignment errors additionally embed the serde-serialized
//! `AlignmentError` (e.g. `{"SearchError":"LimitReached"}`) inside the ok
//! response.
//!
//! Ops (`"op"` field of the request object):
//!   - `import_xes` `{content}` -> `{handle}`
//!   - `import_xes_gz` `{content_b64}` -> `{handle}` (base64 of .xes.gz bytes)
//!   - `log_stats` `{handle}` -> `{num_cases, num_variants, num_activities,
//!     activities (sorted lexicographically), top_variant, top_variant_count}`
//!   - `top_n_variants` `{handle, n}` -> `{variants:[{activities, count,
//!     percentage}]}` (descending count; `percentage` on the 0-100 scale)
//!   - `discover_dfg` `{handle}` -> `{edges:[{source, target, frequency}]}`
//!     sorted by `(source, target)` — identical to the rf1 oracle's sort
//!   - `discover_alphappp` `{handle, config?}` -> `{net_handle, summary}`;
//!     `config` (when present) deserializes verbatim into `AlphaPPPConfig`
//!     (all 7 fields required); absent => `AlphaPPPConfig::default()`
//!   - `import_pnml` `{content}` -> `{net_handle, summary}`
//!   - `align_variants` `{log_handle, net_handle, options?}` ->
//!     `{alignments:[{activities, frequency, alignment|error}]}`
//!   - `align_trace` `{net_handle, trace:[..], options?}` ->
//!     `{moves, cost, states_visited}`
//!   - `compute_fitness` `{log_handle, net_handle, options?}` ->
//!     `{log_fitness, average_fitness, perfectly_fitting_frac, total_costs,
//!     num_variants_aligned}`
//!   - `activities_to_alphabet` `{handle}` -> `{mapping, order, num_activities}`
//!   - `activity_position` `{handle, activity}` -> `{activity, positions, total}`
//!   - `free_log` `{handle}` / `free_net` `{handle}` -> `{freed:true}`
//!
//! Alignment `options` (when present) deserializes verbatim into rust4pm's
//! `AlignmentOptions` (`cost_fn` with its four per-move-kind costs, plus
//! `max_states`; `"max_states":null` = unbounded). When absent, the default
//! is `max_states: Some(5_000_000)` over the standard cost function —
//! mirroring rf2-conformance-oracle, because the crate's own default
//! 100_000-state cap really triggers `SearchError(LimitReached)` on
//! receipt.xes-scale logs.
//!
//! UNSUPPORTED, by design and stated rather than faked: pm4py's
//! VERSION_DISCOUNTED_A_STAR discount exponent. process_mining 0.6.2 has
//! only the fixed per-move-kind `CostFunction`; there is no exponential
//! cost-decay model anywhere in the crate. An `options` object carrying
//! `exponent` / `discount` / `discount_exponent` is rejected with an
//! explicit error, never silently ignored.
//!
//! Alignment move rendering (pm4py-style 2-arrays, computed here):
//!   - sync move            -> `[activity, activity]`
//!   - log move             -> `[activity, ">>"]`
//!   - labeled model move   -> `[">>", "<label>"]`
//!   - silent model move    -> `[">>", null]` (pm4py renders `('>>', None)`)
//!
//! Pinned pm4py semantics for the two ported stats ops:
//!   - `activities_to_alphabet` (pm4py
//!     `objects/log/util/activities_to_alphabet.py`): activities ordered by
//!     descending total event count, remapped to bijective base-26 letters
//!     (`A..Z, AA, AB, ...`; index 26 = `"AA"`). One deliberate determinism
//!     pin: pandas `value_counts` tie order is quicksort-unstable across
//!     versions, so ties here are pinned to first-occurrence order in the
//!     log (traces in file order, events in order). Events lacking a
//!     `concept:name` string attribute are skipped.
//!   - `activity_position` (pm4py `stats.py`
//!     `get_activity_position_summary`): for every occurrence of the
//!     activity, its 0-based index within its trace, histogrammed. Emitted
//!     as `[index, count]` pairs sorted ascending by index; an unknown
//!     activity yields the empty histogram (pm4py returns `{}`), not an
//!     error.
//!
//! # Handle space
//!
//! One shared monotonically increasing u64 counter (starting at 1) over two
//! disjoint registries: `LOGS` (EventLog) and `NETS` (PetriNet). A log
//! handle passed to a net op errors `"unknown net handle N"` — handles
//! never alias across the two maps. Handles live for the lifetime of the
//! wasm instance; a host restart invalidates all of them.
//!
//! # Memory ownership contract
//!
//! All buffers crossing the boundary use one allocation discipline:
//! `std::alloc::alloc/dealloc` with `Layout::from_size_align(len, 1)`.
//!   - `r4pm_alloc(len) -> ptr`: host allocates the request buffer, then
//!     writes the JSON bytes into it.
//!   - `r4pm_call(ptr, len)`: CONSUMES the request buffer — it copies the
//!     bytes out and frees the buffer immediately. The host MUST NOT call
//!     `r4pm_dealloc` on the request buffer afterward (double-free).
//!   - The response buffer is owned by the HOST: after reading
//!     `out_len` bytes at `out_ptr`, the host must call
//!     `r4pm_dealloc(out_ptr, out_len)`. (Built via `Box<[u8]>`, whose
//!     layout is exactly `(len, align 1)`, matching `r4pm_dealloc`.)
//! Freed handles return their memory to the wasm allocator; linear memory
//! itself never shrinks.
//!
//! # Stdout note
//!
//! `alphappp_discover_petri_net` prints progress lines to fd 1
//! unconditionally (a crate behavior, not part of any API contract). Under
//! WASI those lines land on the host-configured stdout. The wire contract
//! is unaffected — responses travel through linear memory, never stdout —
//! so the host may route or ignore that stream freely.

use std::alloc::Layout;
use std::collections::{BTreeMap, HashMap};
use std::sync::Mutex;

use base64::Engine as _;
use process_mining::conformance::alignments::{
    align_trace, align_variants, compute_fitness, AlignmentMove, AlignmentOptions,
    AlignmentResult,
};
use process_mining::core::event_data::case_centric::constants::ACTIVITY_NAME;
use process_mining::core::event_data::case_centric::utils::activity_projection::{
    get_num_cases, get_num_variants, get_projection_activities, get_top_n_variants,
    log_to_activity_projection,
};
use process_mining::core::event_data::case_centric::xes::{import_xes_slice, XESImportOptions};
use process_mining::core::event_data::object_centric::linked_ocel::SlimLinkedOCEL;
use process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_slice;
use process_mining::core::event_data::object_centric::ocel_xml::{
    export_ocel_xml, import_ocel_xml_slice,
};
use process_mining::core::event_data::object_centric::{
    OCELEvent, OCELObject, OCELRelationship, OCELType, OCELTypeAttribute, OCEL,
};
use process_mining::core::event_data::case_centric::{AttributeValue, XESEditableAttribute};
use process_mining::core::process_models::case_centric::petri_net::pnml::import_pnml_reader;
use process_mining::discovery::case_centric::alphappp::full::{
    alphappp_discover_petri_net, AlphaPPPConfig,
};
use process_mining::discovery::case_centric::dfg::discover_dfg;
use process_mining::discovery::case_centric::powl::discover_powl;
use process_mining::discovery::object_centric::dfg::get_dfg_of_object_type;
use process_mining::discovery::object_centric::variants::get_variants_of_object_type;
use process_mining::{EventLog, PetriNet};

/// Registry of imported event logs, keyed by handle.
static LOGS: Mutex<Option<HashMap<u64, EventLog>>> = Mutex::new(None);
/// Registry of imported/discovered Petri nets, keyed by handle.
static NETS: Mutex<Option<HashMap<u64, PetriNet>>> = Mutex::new(None);
/// Shared handle counter across both registries (so handles never collide,
/// and a stale log handle can never accidentally alias a net handle).
static NEXT: Mutex<u64> = Mutex::new(1);

/// OCEL registry -- same shared-counter, take/compute/re-insert discipline
/// as LOGS/NETS (see the Q1-F1 note above).
static OCELS: Mutex<Option<HashMap<u64, OCEL>>> = Mutex::new(None);

const UNSUPPORTED_DISCOUNT_MSG: &str = "unsupported: discounted cost model (pm4py \
VERSION_DISCOUNTED_A_STAR exponent) -- process_mining 0.6.2 has only the per-move-kind \
CostFunction; use standard optimal alignments";

// ---------------------------------------------------------------------------
// Memory ABI (see the module doc's ownership contract)
// ---------------------------------------------------------------------------

/// Allocate `len` bytes for the host to write a request into. `len == 0`
/// returns null (the host never allocates empty requests).
#[no_mangle]
pub extern "C" fn r4pm_alloc(len: usize) -> *mut u8 {
    if len == 0 {
        return std::ptr::null_mut();
    }
    match Layout::from_size_align(len, 1) {
        Ok(layout) => unsafe { std::alloc::alloc(layout) },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a buffer previously produced by `r4pm_alloc` (host-side misuse
/// recovery) or returned by `r4pm_call` (the normal response-free path).
#[no_mangle]
pub extern "C" fn r4pm_dealloc(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    if let Ok(layout) = Layout::from_size_align(len, 1) {
        unsafe { std::alloc::dealloc(ptr, layout) }
    }
}

/// One dispatch entry point: request JSON in linear memory -> response JSON.
/// Returns a packed u64: `(out_ptr << 32) | out_len` of the response buffer.
///
/// CONSUMES the request buffer (copies it out, then frees it) — the host
/// must not dealloc the request after this call. The response buffer is the
/// host's to free via `r4pm_dealloc(out_ptr, out_len)` after reading.
#[no_mangle]
pub extern "C" fn r4pm_call(ptr: *mut u8, len: usize) -> u64 {
    let input: Vec<u8> = if ptr.is_null() || len == 0 {
        Vec::new()
    } else {
        let copied = unsafe { std::slice::from_raw_parts(ptr, len) }.to_vec();
        r4pm_dealloc(ptr, len);
        copied
    };
    let out = dispatch(&input).unwrap_or_else(|e| {
        serde_json::to_vec(&serde_json::json!({ "error": e })).unwrap_or_else(|_| {
            // Only reachable if the error string itself cannot serialize,
            // which valid UTF-8 cannot trigger; kept total regardless.
            b"{\"error\":\"internal: response serialization failed\"}".to_vec()
        })
    });
    let out_len = out.len();
    let out_ptr = Box::into_raw(out.into_boxed_slice()) as *mut u8 as u64;
    (out_ptr << 32) | (out_len as u64)
}

// ---------------------------------------------------------------------------
// Handle registry helpers
// ---------------------------------------------------------------------------

fn next_handle() -> Result<u64, String> {
    let mut next = NEXT
        .lock()
        .map_err(|_| "internal: handle counter lock poisoned".to_string())?;
    let id = *next;
    *next += 1;
    Ok(id)
}

fn insert_log(log: EventLog) -> Result<u64, String> {
    let id = next_handle()?;
    LOGS.lock()
        .map_err(|_| "internal: log registry lock poisoned".to_string())?
        .get_or_insert_with(HashMap::new)
        .insert(id, log);
    Ok(id)
}

fn insert_net(net: PetriNet) -> Result<u64, String> {
    let id = next_handle()?;
    NETS.lock()
        .map_err(|_| "internal: net registry lock poisoned".to_string())?
        .get_or_insert_with(HashMap::new)
        .insert(id, net);
    Ok(id)
}

// Q1-F1 fix (adversarial review, this session): NEVER hold a registry lock
// across the computation. wasm32-wasip1 std has the no-threads Mutex and this
// crate builds with panic="abort", so a host-side epoch-interrupt trap (the
// wrapper's per-op timeout) or any guest panic mid-compute would abandon a
// held MutexGuard with no Drop -- permanently wedging the registry and
// bricking every subsequent op. Instead: REMOVE the value under a short
// lock, drop the guard, compute lock-free, and re-insert under a fresh
// lock. A trap mid-compute now costs exactly the handle(s) in flight, never
// the engine. (The lock()/unwrap-shaped poison arms are gone with it:
// poisoning requires unwinding, which panic="abort" makes unreachable.)
fn take_log(id: u64) -> Result<EventLog, String> {
    LOGS.lock()
        .map_err(|_| "internal: log registry lock poisoned".to_string())?
        .as_mut()
        .and_then(|m| m.remove(&id))
        .ok_or_else(|| format!("unknown log handle {id}"))
}

fn put_log(id: u64, log: EventLog) {
    if let Ok(mut guard) = LOGS.lock() {
        guard.get_or_insert_with(HashMap::new).insert(id, log);
    }
}

fn take_net(id: u64) -> Result<PetriNet, String> {
    NETS.lock()
        .map_err(|_| "internal: net registry lock poisoned".to_string())?
        .as_mut()
        .and_then(|m| m.remove(&id))
        .ok_or_else(|| format!("unknown net handle {id}"))
}

fn put_net(id: u64, net: PetriNet) {
    if let Ok(mut guard) = NETS.lock() {
        guard.get_or_insert_with(HashMap::new).insert(id, net);
    }
}

fn with_log<T>(id: u64, f: impl FnOnce(&EventLog) -> Result<T, String>) -> Result<T, String> {
    let log = take_log(id)?;
    let out = f(&log);
    put_log(id, log);
    out
}

fn with_net<T>(id: u64, f: impl FnOnce(&PetriNet) -> Result<T, String>) -> Result<T, String> {
    let net = take_net(id)?;
    let out = f(&net);
    put_net(id, net);
    out
}

/// Take order is fixed LOGS -> NETS; on a missing net the log is re-inserted
/// before returning, so a bad net handle never leaks the log handle.
fn with_log_and_net<T>(
    log_id: u64,
    net_id: u64,
    f: impl FnOnce(&EventLog, &PetriNet) -> Result<T, String>,
) -> Result<T, String> {
    let log = take_log(log_id)?;
    let net = match take_net(net_id) {
        Ok(net) => net,
        Err(e) => {
            put_log(log_id, log);
            return Err(e);
        }
    };
    let out = f(&log, &net);
    put_net(net_id, net);
    put_log(log_id, log);
    out
}

fn remove_log(id: u64) -> Result<(), String> {
    LOGS.lock()
        .map_err(|_| "internal: log registry lock poisoned".to_string())?
        .as_mut()
        .and_then(|m| m.remove(&id))
        .map(|_| ())
        .ok_or_else(|| format!("unknown log handle {id}"))
}

/// Deterministic variant ordering. The crate's `get_top_n_variants` derives
/// its order from the projection's HashMap-grouped trace list, which is
/// NONDETERMINISTIC across calls when frequencies tie (caught by a real
/// failing T8: two imports of running-example.xes returned different
/// `top_variant`s, all six variants tied at count 1). Presentation-order
/// pinning only -- the variants and counts are 100% the crate's own.
fn sorted_variants(
    proj: &process_mining::core::event_data::case_centric::utils::activity_projection::EventLogActivityProjection,
    n: usize,
) -> Vec<process_mining::core::event_data::case_centric::utils::activity_projection::ProcessVariant> {
    let mut all = get_top_n_variants(proj, usize::MAX);
    all.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.activities.cmp(&b.activities)));
    all.truncate(n);
    all
}

fn insert_ocel(ocel: OCEL) -> Result<u64, String> {
    let mut next = NEXT
        .lock()
        .map_err(|_| "internal: id counter lock poisoned".to_string())?;
    let id = *next;
    *next += 1;
    drop(next);
    OCELS
        .lock()
        .map_err(|_| "internal: ocel registry lock poisoned".to_string())?
        .get_or_insert_with(HashMap::new)
        .insert(id, ocel);
    Ok(id)
}

fn take_ocel(id: u64) -> Result<OCEL, String> {
    OCELS
        .lock()
        .map_err(|_| "internal: ocel registry lock poisoned".to_string())?
        .as_mut()
        .and_then(|m| m.remove(&id))
        .ok_or_else(|| format!("unknown ocel handle {id}"))
}

fn put_ocel(id: u64, ocel: OCEL) {
    if let Ok(mut guard) = OCELS.lock() {
        guard.get_or_insert_with(HashMap::new).insert(id, ocel);
    }
}

/// Mutating access (the OCEL-building ops): take, mutate, re-insert.
fn with_ocel_mut<T>(id: u64, f: impl FnOnce(&mut OCEL) -> Result<T, String>) -> Result<T, String> {
    let mut ocel = take_ocel(id)?;
    let out = f(&mut ocel);
    put_ocel(id, ocel);
    out
}

fn remove_net(id: u64) -> Result<(), String> {
    NETS.lock()
        .map_err(|_| "internal: net registry lock poisoned".to_string())?
        .as_mut()
        .and_then(|m| m.remove(&id))
        .map(|_| ())
        .ok_or_else(|| format!("unknown net handle {id}"))
}

// ---------------------------------------------------------------------------
// Shared rendering helpers
// ---------------------------------------------------------------------------

fn parse_type_attributes(v: &serde_json::Value) -> Result<Vec<OCELTypeAttribute>, String> {
    match v.get("attributes") {
        None | Some(serde_json::Value::Null) => Ok(Vec::new()),
        Some(serde_json::Value::Array(items)) => items
            .iter()
            .map(|item| {
                let name = item
                    .get("name")
                    .and_then(|x| x.as_str())
                    .ok_or("type attribute missing string name")?;
                let value_type = item
                    .get("type")
                    .and_then(|x| x.as_str())
                    .ok_or("type attribute missing string type")?;
                Ok(OCELTypeAttribute {
                    name: name.to_string(),
                    value_type: value_type.to_string(),
                })
            })
            .collect(),
        Some(_) => Err("attributes must be an array".to_string()),
    }
}

fn parse_relationships(
    v: &serde_json::Value,
    key: &str,
) -> Result<Vec<OCELRelationship>, String> {
    match v.get(key) {
        None | Some(serde_json::Value::Null) => Ok(Vec::new()),
        Some(serde_json::Value::Array(items)) => items
            .iter()
            .map(|item| {
                let pair = item
                    .as_array()
                    .filter(|a| a.len() == 2)
                    .ok_or_else(|| format!("{key} entries must be [object_id, qualifier] pairs"))?;
                let object_id = pair[0]
                    .as_str()
                    .ok_or_else(|| format!("{key} object_id must be a string"))?;
                let qualifier = pair[1]
                    .as_str()
                    .ok_or_else(|| format!("{key} qualifier must be a string"))?;
                Ok(OCELRelationship {
                    object_id: object_id.to_string(),
                    qualifier: qualifier.to_string(),
                })
            })
            .collect(),
        Some(_) => Err(format!("{key} must be an array")),
    }
}

fn ok_json(value: &serde_json::Value) -> Result<Vec<u8>, String> {
    serde_json::to_vec(value).map_err(|e| format!("internal: response serialization failed: {e}"))
}

fn req_u64(v: &serde_json::Value, key: &str) -> Result<u64, String> {
    v[key].as_u64().ok_or_else(|| format!("missing {key}"))
}

fn req_str<'a>(v: &'a serde_json::Value, key: &str) -> Result<&'a str, String> {
    v[key].as_str().ok_or_else(|| format!("missing {key}"))
}

/// Summary shape shared by `discover_alphappp` and `import_pnml`.
fn net_summary(net: &PetriNet) -> serde_json::Value {
    let silent = net.transitions.values().filter(|t| t.label.is_none()).count();
    serde_json::json!({
        "places": net.places.len(),
        "transitions": net.transitions.len(),
        "silent_transitions": silent,
        "arcs": net.arcs.len(),
        "has_initial_marking": net.initial_marking.is_some(),
        "num_final_markings": net.final_markings.as_ref().map(|m| m.len()).unwrap_or(0),
    })
}

/// Parse the optional `"options"` key into rust4pm's `AlignmentOptions`.
///
/// Absent/null => `max_states: Some(5_000_000)` over the standard cost
/// function (rf2-conformance-oracle's load-bearing default — the crate's
/// own 100_000 cap really triggers `LimitReached` at receipt.xes scale).
/// The discount-key guard runs BEFORE serde because serde would silently
/// ignore unknown keys, and silently ignoring a requested cost model is
/// exactly the faking this engine refuses to do.
fn parse_alignment_options(v: &serde_json::Value) -> Result<AlignmentOptions, String> {
    match v.get("options") {
        None | Some(serde_json::Value::Null) => Ok(AlignmentOptions {
            max_states: Some(5_000_000),
            ..AlignmentOptions::default()
        }),
        Some(opts) => {
            if let Some(obj) = opts.as_object() {
                for key in ["exponent", "discount", "discount_exponent"] {
                    if obj.contains_key(key) {
                        return Err(UNSUPPORTED_DISCOUNT_MSG.to_string());
                    }
                }
            }
            serde_json::from_value(opts.clone()).map_err(|e| format!("bad options: {e}"))
        }
    }
}

/// Render rust4pm alignment moves as pm4py-style `[log_side, model_side]`
/// 2-arrays (see the module doc). `activities` is the aligned trace's
/// activity sequence, used to resolve `trace_event_index`.
fn render_moves(
    moves: &[AlignmentMove],
    activities: &[String],
    net: &PetriNet,
) -> Result<Vec<serde_json::Value>, String> {
    moves
        .iter()
        .map(|m| match m {
            AlignmentMove::SyncMove {
                trace_event_index, ..
            } => {
                let a = activities.get(*trace_event_index).ok_or_else(|| {
                    format!(
                        "internal: sync move references event index {trace_event_index} \
                         beyond trace length {}",
                        activities.len()
                    )
                })?;
                Ok(serde_json::json!([a, a]))
            }
            AlignmentMove::LogMove { trace_event_index } => {
                let a = activities.get(*trace_event_index).ok_or_else(|| {
                    format!(
                        "internal: log move references event index {trace_event_index} \
                         beyond trace length {}",
                        activities.len()
                    )
                })?;
                Ok(serde_json::json!([a, ">>"]))
            }
            AlignmentMove::ModelMove { transition } => {
                let t = net.transitions.get(&transition.0).ok_or_else(|| {
                    format!(
                        "internal: model move references unknown transition {}",
                        transition.0
                    )
                })?;
                match &t.label {
                    Some(label) => Ok(serde_json::json!([">>", label])),
                    None => Ok(serde_json::json!([">>", serde_json::Value::Null])),
                }
            }
        })
        .collect()
}

/// `{"moves": .., "cost": .., "states_visited": ..}` for one alignment.
fn alignment_json(
    result: &AlignmentResult,
    activities: &[String],
    net: &PetriNet,
) -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "moves": render_moves(&result.moves, activities, net)?,
        "cost": result.cost,
        "states_visited": result.states_visited,
    }))
}

/// Serialize an `AlignmentError` into a string carrying its serde form,
/// for top-level `{"error": ...}` responses (align_trace/compute_fitness).
fn alignment_error_string(context: &str, e: &impl serde::Serialize) -> String {
    match serde_json::to_string(e) {
        Ok(json) => format!("{context}: {json}"),
        Err(ser_err) => format!("{context}: (error unserializable: {ser_err})"),
    }
}

/// Bijective base-26 letters, pm4py `activities_to_alphabet` style:
/// 0..=25 -> `A..Z`, 26 -> `AA`, 27 -> `AB`, ... (the `chr((i % 26) + 'A')`
/// prepend loop from activities_to_alphabet.py, exactly).
fn index_to_letters(index: usize) -> String {
    let mut i = index as i64;
    let mut letters: Vec<char> = Vec::new();
    loop {
        letters.push((b'A' + (i % 26) as u8) as char);
        i = i / 26 - 1;
        if i < 0 {
            break;
        }
    }
    letters.iter().rev().collect()
}

/// The event's `concept:name` value, when present as a string attribute.
fn event_activity(event: &process_mining::core::event_data::case_centric::Event) -> Option<&str> {
    match event.attributes.get_by_key(ACTIVITY_NAME) {
        Some(attr) => match &attr.value {
            AttributeValue::String(s) => Some(s.as_str()),
            _ => None,
        },
        None => None,
    }
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

fn dispatch(input: &[u8]) -> Result<Vec<u8>, String> {
    let v: serde_json::Value =
        serde_json::from_slice(input).map_err(|e| format!("bad input json: {e}"))?;
    let op = v["op"].as_str().ok_or("missing op")?;
    match op {
        "import_xes" => {
            let content = req_str(&v, "content")?;
            let log: EventLog =
                import_xes_slice(content.as_bytes(), false, XESImportOptions::default())
                    .map_err(|e| format!("xes import failed: {e:?}"))?;
            let id = insert_log(log)?;
            ok_json(&serde_json::json!({ "handle": id }))
        }
        "import_xes_gz" => {
            let b64 = req_str(&v, "content_b64")?;
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(b64)
                .map_err(|e| format!("bad base64 in content_b64: {e}"))?;
            let log: EventLog = import_xes_slice(&bytes, true, XESImportOptions::default())
                .map_err(|e| format!("xes import failed: {e:?}"))?;
            let id = insert_log(log)?;
            ok_json(&serde_json::json!({ "handle": id }))
        }
        "log_stats" => {
            let id = req_u64(&v, "handle")?;
            let value = with_log(id, |log| {
                let proj = log_to_activity_projection(log);
                let mut activities: Vec<String> = get_projection_activities(&proj).to_vec();
                activities.sort();
                let top = sorted_variants(&proj, 1).into_iter().next();
                Ok(serde_json::json!({
                    "num_cases": get_num_cases(&proj),
                    "num_variants": get_num_variants(&proj),
                    "num_activities": activities.len(),
                    "activities": activities,
                    "top_variant": top.as_ref().map(|t| t.activities.clone()),
                    "top_variant_count": top.as_ref().map(|t| t.count),
                }))
            })?;
            ok_json(&value)
        }
        "top_n_variants" => {
            let id = req_u64(&v, "handle")?;
            // Q1-F6: on wasm32 a u64 `as usize` truncates (2^32 -> 0 == "none"
            // instead of "all"); saturate instead so huge n means "all".
            let n = usize::try_from(req_u64(&v, "n")?).unwrap_or(usize::MAX);
            let value = with_log(id, |log| {
                let proj = log_to_activity_projection(log);
                let variants = sorted_variants(&proj, n);
                serde_json::to_value(&variants)
                    .map(|vs| serde_json::json!({ "variants": vs }))
                    .map_err(|e| format!("internal: variant serialization failed: {e}"))
            })?;
            ok_json(&value)
        }
        "discover_dfg" => {
            let id = req_u64(&v, "handle")?;
            let value = with_log(id, |log| {
                let dfg = discover_dfg(log);
                let mut edges: Vec<(String, String, u32)> = dfg
                    .directly_follows_relations
                    .iter()
                    .map(|((s, t), f)| (s.to_string(), t.to_string(), *f))
                    .collect();
                edges.sort();
                let edges: Vec<serde_json::Value> = edges
                    .into_iter()
                    .map(|(s, t, f)| {
                        serde_json::json!({"source": s, "target": t, "frequency": f})
                    })
                    .collect();
                Ok(serde_json::json!({ "edges": edges }))
            })?;
            ok_json(&value)
        }
        "discover_powl" => {
            let id = req_u64(&v, "handle")?;
            let value = with_log(id, |log| {
                let powl = discover_powl(log);
                serde_json::to_value(&powl)
                    .map(|model| serde_json::json!({ "powl": model }))
                    .map_err(|e| format!("internal: powl serialization failed: {e}"))
            })?;
            ok_json(&value)
        }
        "discover_alphappp" => {
            let id = req_u64(&v, "handle")?;
            let config: AlphaPPPConfig = match v.get("config") {
                None | Some(serde_json::Value::Null) => AlphaPPPConfig::default(),
                Some(c) => serde_json::from_value(c.clone())
                    .map_err(|e| format!("bad config: {e}"))?,
            };
            let net = with_log(id, |log| {
                let proj = log_to_activity_projection(log);
                // Real Alpha+++ discovery; the discovered net always carries
                // initial + final markings, so its handle feeds the
                // alignment ops directly. (Its progress println!s go to the
                // WASI stdout — see the module doc's stdout note.)
                Ok(alphappp_discover_petri_net(&proj, config))
            })?;
            let summary = net_summary(&net);
            let net_id = insert_net(net)?;
            ok_json(&serde_json::json!({ "net_handle": net_id, "summary": summary }))
        }
        "import_pnml" => {
            let content = req_str(&v, "content")?;
            let net = import_pnml_reader(&mut content.as_bytes())
                .map_err(|e| format!("pnml import failed: {e}"))?;
            let summary = net_summary(&net);
            let net_id = insert_net(net)?;
            ok_json(&serde_json::json!({ "net_handle": net_id, "summary": summary }))
        }
        "align_variants" => {
            let log_id = req_u64(&v, "log_handle")?;
            let net_id = req_u64(&v, "net_handle")?;
            let options = parse_alignment_options(&v)?;
            let value = with_log_and_net(log_id, net_id, |log, net| {
                let proj = log_to_activity_projection(log);
                let mut results = align_variants(net, &proj, &options);
                // Same nondeterminism class as sorted_variants (the
                // projection's variant order is HashMap-derived): pin the
                // OUTPUT order to (frequency desc, activities asc). The
                // alignments themselves are untouched crate results.
                results.sort_by(|a, b| {
                    b.frequency
                        .cmp(&a.frequency)
                        .then_with(|| a.activities.cmp(&b.activities))
                });
                let results = results;
                let mut out = Vec::with_capacity(results.len());
                for r in &results {
                    let mut entry = serde_json::Map::new();
                    entry.insert("activities".to_string(), serde_json::json!(r.activities));
                    entry.insert("frequency".to_string(), serde_json::json!(r.frequency));
                    match &r.result {
                        Ok(a) => {
                            entry.insert(
                                "alignment".to_string(),
                                alignment_json(a, &r.activities, net)?,
                            );
                        }
                        Err(e) => {
                            entry.insert(
                                "error".to_string(),
                                serde_json::to_value(e).map_err(|se| {
                                    format!("internal: error serialization failed: {se}")
                                })?,
                            );
                        }
                    }
                    out.push(serde_json::Value::Object(entry));
                }
                Ok(serde_json::json!({ "alignments": out }))
            })?;
            ok_json(&value)
        }
        "align_trace" => {
            let net_id = req_u64(&v, "net_handle")?;
            let trace: Vec<String> = v["trace"]
                .as_array()
                .ok_or("missing trace")?
                .iter()
                .map(|x| {
                    x.as_str()
                        .map(str::to_string)
                        .ok_or_else(|| "trace entries must be strings".to_string())
                })
                .collect::<Result<_, _>>()?;
            let options = parse_alignment_options(&v)?;
            let value = with_net(net_id, |net| {
                let trace_refs: Vec<&str> = trace.iter().map(String::as_str).collect();
                match align_trace(net, &trace_refs, &options) {
                    Ok(result) => alignment_json(&result, &trace, net),
                    Err(e) => Err(alignment_error_string("alignment failed", &e)),
                }
            })?;
            ok_json(&value)
        }
        "compute_fitness" => {
            let log_id = req_u64(&v, "log_handle")?;
            let net_id = req_u64(&v, "net_handle")?;
            let options = parse_alignment_options(&v)?;
            let value = with_log_and_net(log_id, net_id, |log, net| {
                let proj = log_to_activity_projection(log);
                let results = align_variants(net, &proj, &options);
                let num_variants_aligned = results.len();
                // Crate behavior, surfaced not masked: compute_fitness
                // propagates the FIRST per-variant error — one failed
                // variant fails the whole op.
                match compute_fitness(&results, net, &options) {
                    Ok(f) => Ok(serde_json::json!({
                        "log_fitness": f.log_fitness,
                        "average_fitness": f.average_fitness,
                        "perfectly_fitting_frac": f.perfectly_fitting_frac,
                        "total_costs": f.total_costs,
                        "num_variants_aligned": num_variants_aligned,
                    })),
                    Err(e) => Err(alignment_error_string("compute_fitness failed", &e)),
                }
            })?;
            ok_json(&value)
        }
        "activities_to_alphabet" => {
            let id = req_u64(&v, "handle")?;
            let value = with_log(id, |log| {
                // Count per-activity event totals + first-seen rank in one
                // pass over rust4pm's own structures (data plumbing only).
                let mut stats: HashMap<String, (u64, usize)> = HashMap::new();
                for trace in &log.traces {
                    for event in &trace.events {
                        if let Some(activity) = event_activity(event) {
                            let first_seen_rank = stats.len();
                            let entry = stats
                                .entry(activity.to_string())
                                .or_insert((0, first_seen_rank));
                            entry.0 += 1;
                        }
                    }
                }
                let mut items: Vec<(String, u64, usize)> = stats
                    .into_iter()
                    .map(|(activity, (count, first_seen))| (activity, count, first_seen))
                    .collect();
                // Descending count; ties pinned to first-occurrence order
                // (the documented determinism pin over pandas value_counts).
                items.sort_by(|a, b| b.1.cmp(&a.1).then(a.2.cmp(&b.2)));
                let mapping: serde_json::Map<String, serde_json::Value> = items
                    .iter()
                    .enumerate()
                    .map(|(i, (activity, _, _))| {
                        (activity.clone(), serde_json::json!(index_to_letters(i)))
                    })
                    .collect();
                let order: Vec<serde_json::Value> = items
                    .iter()
                    .map(|(activity, count, _)| serde_json::json!([activity, count]))
                    .collect();
                Ok(serde_json::json!({
                    "mapping": mapping,
                    "order": order,
                    "num_activities": items.len(),
                }))
            })?;
            ok_json(&value)
        }
        "activity_position" => {
            let id = req_u64(&v, "handle")?;
            let activity = req_str(&v, "activity")?.to_string();
            let value = with_log(id, |log| {
                let mut histogram: BTreeMap<usize, u64> = BTreeMap::new();
                for trace in &log.traces {
                    for (index, event) in trace.events.iter().enumerate() {
                        if event_activity(event) == Some(activity.as_str()) {
                            *histogram.entry(index).or_insert(0) += 1;
                        }
                    }
                }
                let total: u64 = histogram.values().sum();
                let positions: Vec<serde_json::Value> = histogram
                    .iter()
                    .map(|(index, count)| serde_json::json!([index, count]))
                    .collect();
                Ok(serde_json::json!({
                    "activity": activity,
                    "positions": positions,
                    "total": total,
                }))
            })?;
            ok_json(&value)
        }
        "free_log" => {
            let id = req_u64(&v, "handle")?;
            remove_log(id)?;
            ok_json(&serde_json::json!({ "freed": true }))
        }
        "free_net" => {
            let id = req_u64(&v, "handle")?;
            remove_net(id)?;
            ok_json(&serde_json::json!({ "freed": true }))
        }
        // ------------------------------------------------------------------
        // OCEL construction ops -- the rust4pm docs site's own two documented
        // examples ("Building a Linked OCEL": declare event/object types, add
        // events/objects with E2O/O2O relations, export OCEL 2.0), expressed
        // over the crate's real OCEL structs (OCELType/OCELEvent/OCELObject/
        // OCELRelationship all crate types with derived serde; export is the
        // crate's own OCEL 2.0 JSON shape via serde, byte-compatible with
        // its importer).
        // ------------------------------------------------------------------
        "ocel_new" => {
            let ocel = OCEL {
                event_types: Vec::new(),
                object_types: Vec::new(),
                events: Vec::new(),
                objects: Vec::new(),
            };
            let id = insert_ocel(ocel)?;
            ok_json(&serde_json::json!({ "ocel_handle": id }))
        }
        "ocel_add_event_type" | "ocel_add_object_type" => {
            let id = req_u64(&v, "ocel_handle")?;
            let name = req_str(&v, "name")?.to_string();
            let attributes = parse_type_attributes(&v)?;
            let is_event = op == "ocel_add_event_type";
            let value = with_ocel_mut(id, |ocel| {
                let bucket = if is_event {
                    &mut ocel.event_types
                } else {
                    &mut ocel.object_types
                };
                if bucket.iter().any(|ty| ty.name == name) {
                    return Err(format!("duplicate type {name:?}"));
                }
                bucket.push(OCELType { name: name.clone(), attributes: attributes.clone() });
                Ok(serde_json::json!({ "added": name }))
            })?;
            ok_json(&value)
        }
        "ocel_add_object" => {
            let id = req_u64(&v, "ocel_handle")?;
            let obj_id = req_str(&v, "id")?.to_string();
            let obj_type = req_str(&v, "type")?.to_string();
            let o2o = parse_relationships(&v, "o2o")?;
            let value = with_ocel_mut(id, |ocel| {
                if !ocel.object_types.iter().any(|ty| ty.name == obj_type) {
                    return Err(format!("undeclared object type {obj_type:?}"));
                }
                if ocel.objects.iter().any(|o| o.id == obj_id) {
                    return Err(format!("duplicate object id {obj_id:?}"));
                }
                ocel.objects.push(OCELObject {
                    id: obj_id.clone(),
                    object_type: obj_type,
                    attributes: Vec::new(),
                    relationships: o2o,
                });
                Ok(serde_json::json!({ "added": obj_id }))
            })?;
            ok_json(&value)
        }
        "ocel_add_event" => {
            let id = req_u64(&v, "ocel_handle")?;
            let ev_id = req_str(&v, "id")?.to_string();
            let ev_type = req_str(&v, "type")?.to_string();
            let time = req_str(&v, "time")?;
            let time = chrono::DateTime::parse_from_rfc3339(time)
                .map_err(|e| format!("bad event time {time:?}: {e}"))?;
            let e2o = parse_relationships(&v, "e2o")?;
            let value = with_ocel_mut(id, |ocel| {
                if !ocel.event_types.iter().any(|ty| ty.name == ev_type) {
                    return Err(format!("undeclared event type {ev_type:?}"));
                }
                for rel in &e2o {
                    if !ocel.objects.iter().any(|o| o.id == rel.object_id) {
                        return Err(format!("e2o references unknown object {:?}", rel.object_id));
                    }
                }
                ocel.events.push(OCELEvent {
                    id: ev_id.clone(),
                    event_type: ev_type,
                    time,
                    attributes: Vec::new(),
                    relationships: e2o,
                });
                Ok(serde_json::json!({ "added": ev_id }))
            })?;
            ok_json(&value)
        }
        "ocel_stats" => {
            let id = req_u64(&v, "handle").or_else(|_| req_u64(&v, "ocel_handle"))?;
            let ocel = take_ocel(id)?;
            let mut ev_counts: BTreeMap<&str, u64> = BTreeMap::new();
            for e in &ocel.events {
                *ev_counts.entry(e.event_type.as_str()).or_insert(0) += 1;
            }
            let mut ob_counts: BTreeMap<&str, u64> = BTreeMap::new();
            for o in &ocel.objects {
                *ob_counts.entry(o.object_type.as_str()).or_insert(0) += 1;
            }
            let value = serde_json::json!({
                "num_events": ocel.events.len(),
                "num_objects": ocel.objects.len(),
                "num_event_types": ocel.event_types.len(),
                "num_object_types": ocel.object_types.len(),
                "events_per_type": ev_counts,
                "objects_per_type": ob_counts,
            });
            put_ocel(id, ocel);
            ok_json(&value)
        }
        "ocel_to_json" => {
            let id = req_u64(&v, "handle").or_else(|_| req_u64(&v, "ocel_handle"))?;
            let ocel = take_ocel(id)?;
            let value = serde_json::to_value(&ocel)
                .map_err(|e| format!("internal: OCEL serialization failed: {e}"));
            put_ocel(id, ocel);
            ok_json(&serde_json::json!({ "ocel": value? }))
        }
        "xes_to_ocel" => {
            // Canonical-dataset variant of the "Building a Linked OCEL"
            // example: one OCEL object per XES case (object type =
            // `case_object_type`), one OCEL event per XES event with an E2O
            // relation to its case object. Only plumbing over crate
            // structures -- no algorithm.
            let id = req_u64(&v, "handle")?;
            let case_object_type = req_str(&v, "case_object_type")?.to_string();
            let qualifier = req_str(&v, "qualifier")?.to_string();
            let ocel = with_log(id, |log| {
                let mut event_types: Vec<OCELType> = Vec::new();
                let mut objects: Vec<OCELObject> = Vec::new();
                let mut events: Vec<OCELEvent> = Vec::new();
                for (t_idx, trace) in log.traces.iter().enumerate() {
                    let case_id = trace
                        .attributes
                        .iter()
                        .find(|a| a.key == ACTIVITY_NAME)
                        .and_then(|a| match &a.value {
                            AttributeValue::String(s) => Some(s.clone()),
                            _ => None,
                        })
                        .unwrap_or_else(|| format!("case_{t_idx}"));
                    let obj_id = format!("{case_object_type}:{case_id}");
                    objects.push(OCELObject {
                        id: obj_id.clone(),
                        object_type: case_object_type.clone(),
                        attributes: Vec::new(),
                        relationships: Vec::new(),
                    });
                    for (e_idx, event) in trace.events.iter().enumerate() {
                        let activity = event
                            .attributes
                            .iter()
                            .find(|a| a.key == ACTIVITY_NAME)
                            .and_then(|a| match &a.value {
                                AttributeValue::String(s) => Some(s.clone()),
                                _ => None,
                            });
                        let Some(activity) = activity else { continue };
                        let time = event
                            .attributes
                            .iter()
                            .find(|a| a.key == "time:timestamp")
                            .and_then(|a| match &a.value {
                                AttributeValue::Date(d) => Some(*d),
                                _ => None,
                            })
                            .ok_or_else(|| {
                                format!(
                                    "event {e_idx} of case {case_id:?} has no                                      time:timestamp Date attribute"
                                )
                            })?;
                        if !event_types.iter().any(|ty| ty.name == activity) {
                            event_types.push(OCELType {
                                name: activity.clone(),
                                attributes: Vec::new(),
                            });
                        }
                        events.push(OCELEvent {
                            id: format!("e_{t_idx}_{e_idx}"),
                            event_type: activity,
                            time,
                            attributes: Vec::new(),
                            relationships: vec![OCELRelationship {
                                object_id: obj_id.clone(),
                                qualifier: qualifier.clone(),
                            }],
                        });
                    }
                }
                event_types.sort_by(|a, b| a.name.cmp(&b.name));
                Ok(OCEL {
                    event_types,
                    object_types: vec![OCELType {
                        name: case_object_type.clone(),
                        attributes: Vec::new(),
                    }],
                    events,
                    objects,
                })
            })?;
            let ocel_id = insert_ocel(ocel)?;
            ok_json(&serde_json::json!({ "ocel_handle": ocel_id }))
        }
        "import_ocel_json" => {
            // Docs example "Importing OCEL 2.0 JSON" via the crate's real
            // slice importer (same function family rf4-oc-discovery-oracle
            // pins via `import_ocel_json_path`; slice variant is the
            // wasm-safe one -- no filesystem in wasip1 here).
            let content = req_str(&v, "content")?;
            let ocel: OCEL = import_ocel_json_slice(content.as_bytes())
                .map_err(|e| format!("ocel json import failed: {e}"))?;
            let id = insert_ocel(ocel)?;
            ok_json(&serde_json::json!({ "ocel_handle": id }))
        }
        "import_ocel_xml" => {
            // Docs example "Importing OCEL 2.0 XML". base64 like
            // import_xes_gz so arbitrary bytes survive the JSON ABI.
            let b64 = req_str(&v, "content_b64")?;
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(b64)
                .map_err(|e| format!("bad base64 in content_b64: {e}"))?;
            let ocel: OCEL = import_ocel_xml_slice(&bytes)
                .map_err(|e| format!("ocel xml import failed: {e}"))?;
            let id = insert_ocel(ocel)?;
            ok_json(&serde_json::json!({ "ocel_handle": id }))
        }
        "ocel_to_xml" => {
            // Docs example "Exporting OCEL 2.0 XML" via the crate's own
            // `export_ocel_xml` into an in-memory quick_xml Writer; returned
            // base64 so the bytes survive the JSON ABI unmangled (mirror of
            // import_ocel_xml's content_b64).
            let id = req_u64(&v, "handle").or_else(|_| req_u64(&v, "ocel_handle"))?;
            let ocel = take_ocel(id)?;
            let mut buf: Vec<u8> = Vec::new();
            let result = {
                let mut writer = quick_xml::Writer::new(&mut buf);
                export_ocel_xml(&mut writer, &ocel)
            };
            put_ocel(id, ocel);
            result.map_err(|e| format!("ocel xml export failed: {e}"))?;
            ok_json(&serde_json::json!({
                "content_b64": base64::engine::general_purpose::STANDARD.encode(&buf),
            }))
        }
        "ocel_dfg_of_object_type" | "ocel_variants_of_object_type" => {
            // Docs examples "Object-Centric DFG" / "Object-Centric
            // Variants": SlimLinkedOCEL::from_ocel + the two real discovery
            // functions (exact paths + output orderings read from the
            // crate's vendored source -- see rf4-oc-discovery-oracle's
            // header doc; this is the same code compiled to wasm).
            //
            // from_ocel consumes an OCEL by value, so clone out of the
            // registry and re-insert the original BEFORE computing: the
            // handle stays live across this call, and a hypothetical trap
            // inside discovery costs only this call, never the handle
            // (same Q1-F1 discipline as everywhere else).
            let id = req_u64(&v, "handle").or_else(|_| req_u64(&v, "ocel_handle"))?;
            let object_type = req_str(&v, "object_type")?.to_string();
            let ocel = take_ocel(id)?;
            let owned = ocel.clone();
            put_ocel(id, ocel);
            if !owned.object_types.iter().any(|t| t.name == object_type) {
                return Err(format!(
                    "unknown object_type {object_type:?} (known: {:?})",
                    owned
                        .object_types
                        .iter()
                        .map(|t| t.name.as_str())
                        .collect::<Vec<_>>()
                ));
            }
            let slim = SlimLinkedOCEL::from_ocel(owned);
            if op == "ocel_dfg_of_object_type" {
                // Crate already sorts: count desc, ties by (from, to).
                let edges = get_dfg_of_object_type(&slim, object_type);
                let rendered: Vec<serde_json::Value> = edges
                    .iter()
                    .map(|((from, to), count)| {
                        serde_json::json!({ "from": from, "to": to, "count": count })
                    })
                    .collect();
                ok_json(&serde_json::json!({
                    "num_edges": rendered.len(),
                    "edges": rendered,
                }))
            } else {
                // Crate already sorts: count desc, ties by the trace itself.
                let variants = get_variants_of_object_type(&slim, object_type);
                let num_variants = variants.len();
                let n = v
                    .get("n")
                    .and_then(serde_json::Value::as_u64)
                    .map_or(usize::MAX, |n| n as usize);
                let rendered: Vec<serde_json::Value> = variants
                    .iter()
                    .take(n)
                    .map(|(activities, count)| {
                        serde_json::json!({ "activities": activities, "count": count })
                    })
                    .collect();
                ok_json(&serde_json::json!({
                    "num_variants": num_variants,
                    "variants": rendered,
                }))
            }
        }
        "free_ocel" => {
            let id = req_u64(&v, "handle").or_else(|_| req_u64(&v, "ocel_handle"))?;
            let _ = take_ocel(id)?;
            ok_json(&serde_json::json!({ "freed": true }))
        }
        other => Err(format!("unknown op: {other}")),
    }
}
