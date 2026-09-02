//! petgraph-wasm: real graph algorithms (Dijkstra/A* shortest path, Tarjan
//! strongly-connected-components, topological sort, cycle detection) over
//! named directed graphs, compiled to wasm32-wasip1 behind a plain
//! linear-memory JSON ABI (no wasm-bindgen, no JS glue) so a BEAM host
//! (wasmex/wasmtime) can call it directly -- same shape as rust4pm-wasm and
//! ferroplan-wasm's wasi_abi.rs. Built to run algorithms over the DFGs and
//! Petri nets rust4pm-wasm already produces (edges: source, target,
//! frequency/weight), without reimplementing any graph algorithm in
//! Erlang/Elixir/Gleam.
//!
//! # Wire contract
//!
//! One dispatch export: `pg_call(ptr, len) -> u64` packed as
//! `(out_ptr << 32) | out_len`. Request and response are UTF-8 JSON. Every
//! failure returns `{"error":{"code":..,"message":..,"retryable":bool}}`.
//!
//! Ops (`"op"` field of the request object):
//!   - `graph_new` `{}` -> `{"handle": n}` (always directed -- process
//!     mining's DFGs/traces are inherently directed; an undirected use case
//!     can treat every edge as bidirectional at the add_edge call site)
//!   - `add_node` `{handle, name}` -> `{"ok": true}` (idempotent -- a name
//!     already present is a no-op, not an error)
//!   - `add_edge` `{handle, from, to, weight}` -> `{"ok": true}` (auto-adds
//!     `from`/`to` as nodes if not already present, matching the DFG-edge
//!     shape rust4pm-wasm emits: no separate node-declaration step needed)
//!   - `shortest_path` `{handle, from, to}` -> `{"path": [names...],
//!     "cost": f64}` or `{"path": null, "cost": null}` if unreachable or
//!     `from`/`to` unknown (never an error -- "no path" is a real answer,
//!     not a failure). Real A* with a zero heuristic (= Dijkstra), so
//!     negative edge weights are refused explicitly rather than silently
//!     mishandled (petgraph's Dijkstra/A* both require non-negative
//!     weights; this ABI surfaces that constraint honestly).
//!   - `scc` `{handle}` -> `{"components": [[names...], ...]}` (Tarjan,
//!     each inner list sorted for determinism, outer list sorted by first
//!     element -- petgraph's own SCC order is a valid topological order of
//!     the condensation but not otherwise canonical, so this ABI imposes a
//!     stable order on top)
//!   - `toposort` `{handle}` -> `{"acyclic": true, "order": [names...]}` or
//!     `{"acyclic": false, "order": null}` (a cycle is a real, named
//!     answer -- never an error)
//!   - `is_cyclic` `{handle}` -> `{"cyclic": bool}`
//!   - `node_count` `{handle}` -> `{"count": n}`
//!   - `edge_count` `{handle}` -> `{"count": n}`
//!   - `free_graph` `{handle}` -> `{"freed": true}`
//!
//! # Handle space
//!
//! One monotonically increasing `u64` counter (starting at 1), one
//! registry (`GRAPHS: Mutex<Option<HashMap<u64, NamedGraph>>>`), the same
//! take-lock-free-reinsert discipline as rust4pm-wasm's LOGS/NETS and
//! ferroplan-wasm's SESSIONS: the lock is never held across an algorithm
//! run.
//!
//! # Memory ownership contract
//!
//! Identical to rust4pm-wasm/ferroplan-wasm: `std::alloc::alloc`/`dealloc`,
//! `Layout::from_size_align(len, 1)` throughout. `pg_call` CONSUMES the
//! request buffer; the response buffer is host-owned, freed via
//! `pg_dealloc(out_ptr, out_len)` after reading.

use petgraph::algo::{astar, is_cyclic_directed, tarjan_scc, toposort};
use petgraph::graph::{DiGraph, NodeIndex};
use serde_json::{json, Value};
use std::alloc::Layout;
use std::collections::HashMap;
use std::sync::Mutex;

struct NamedGraph {
    graph: DiGraph<String, f64>,
    index_of: HashMap<String, NodeIndex>,
}

impl NamedGraph {
    fn new() -> Self {
        NamedGraph {
            graph: DiGraph::new(),
            index_of: HashMap::new(),
        }
    }

    fn node(&mut self, name: &str) -> NodeIndex {
        if let Some(&idx) = self.index_of.get(name) {
            idx
        } else {
            let idx = self.graph.add_node(name.to_string());
            self.index_of.insert(name.to_string(), idx);
            idx
        }
    }
}

static NEXT_HANDLE: Mutex<u64> = Mutex::new(1);
static GRAPHS: Mutex<Option<HashMap<u64, NamedGraph>>> = Mutex::new(None);

fn next_handle() -> Result<u64, String> {
    let mut next = NEXT_HANDLE
        .lock()
        .map_err(|_| "internal: handle counter lock poisoned".to_string())?;
    let id = *next;
    *next += 1;
    Ok(id)
}

fn with_graph<T>(handle: u64, f: impl FnOnce(&mut NamedGraph) -> T) -> Result<T, String> {
    let mut g = {
        let mut guard = GRAPHS
            .lock()
            .map_err(|_| "internal: graph registry lock poisoned".to_string())?;
        guard
            .get_or_insert_with(HashMap::new)
            .remove(&handle)
            .ok_or_else(|| format!("unknown graph handle {handle}"))?
    };
    let out = f(&mut g);
    let mut guard = GRAPHS
        .lock()
        .map_err(|_| "internal: graph registry lock poisoned".to_string())?;
    guard.get_or_insert_with(HashMap::new).insert(handle, g);
    Ok(out)
}

fn insert_graph(g: NamedGraph) -> Result<u64, String> {
    let id = next_handle()?;
    let mut guard = GRAPHS
        .lock()
        .map_err(|_| "internal: graph registry lock poisoned".to_string())?;
    guard.get_or_insert_with(HashMap::new).insert(id, g);
    Ok(id)
}

// ---------------------------------------------------------------------------
// Memory ABI (see the module doc's ownership contract)
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn pg_alloc(len: usize) -> *mut u8 {
    if len == 0 {
        return std::ptr::null_mut();
    }
    match Layout::from_size_align(len, 1) {
        Ok(layout) => unsafe { std::alloc::alloc(layout) },
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn pg_dealloc(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    if let Ok(layout) = Layout::from_size_align(len, 1) {
        unsafe { std::alloc::dealloc(ptr, layout) }
    }
}

#[no_mangle]
pub extern "C" fn pg_call(ptr: *mut u8, len: usize) -> u64 {
    let input: Vec<u8> = if ptr.is_null() || len == 0 {
        Vec::new()
    } else {
        let copied = unsafe { std::slice::from_raw_parts(ptr, len) }.to_vec();
        pg_dealloc(ptr, len);
        copied
    };
    let out = dispatch(&input).unwrap_or_else(|message| {
        serde_json::to_vec(&err_json("PG_ADAPTER", &message)).unwrap_or_else(|_| {
            b"{\"error\":{\"code\":\"PG_ADAPTER\",\"message\":\"internal: response serialization failed\",\"retryable\":false}}".to_vec()
        })
    });
    let out_len = out.len();
    let out_ptr = Box::into_raw(out.into_boxed_slice()) as *mut u8 as u64;
    (out_ptr << 32) | (out_len as u64)
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

fn err_json(code: &str, msg: &str) -> Value {
    json!({ "error": { "code": code, "message": msg, "retryable": false } })
}

fn field_str<'a>(req: &'a Value, name: &str) -> Result<&'a str, String> {
    req.get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("missing or non-string field `{name}`"))
}

fn field_u64(req: &Value, name: &str) -> Result<u64, String> {
    req.get(name)
        .and_then(Value::as_u64)
        .ok_or_else(|| format!("missing or non-integer field `{name}`"))
}

fn dispatch(input: &[u8]) -> Result<Vec<u8>, String> {
    let req: Value = serde_json::from_slice(input).map_err(|e| format!("request JSON: {e}"))?;
    let op = req
        .get("op")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing `op` field".to_string())?;

    let response: Value = match op {
        "graph_new" => op_graph_new()?,
        "add_node" => op_add_node(&req)?,
        "add_edge" => op_add_edge(&req)?,
        "shortest_path" => op_shortest_path(&req)?,
        "scc" => op_scc(&req)?,
        "toposort" => op_toposort(&req)?,
        "is_cyclic" => op_is_cyclic(&req)?,
        "node_count" => op_node_count(&req)?,
        "edge_count" => op_edge_count(&req)?,
        "free_graph" => op_free_graph(&req)?,
        other => {
            return serde_json::to_vec(&err_json("PG_UNKNOWN_OP", &format!("unknown op `{other}`")))
                .map_err(|e| e.to_string())
        }
    };
    serde_json::to_vec(&response).map_err(|e| e.to_string())
}

fn op_graph_new() -> Result<Value, String> {
    let handle = insert_graph(NamedGraph::new())?;
    Ok(json!({ "handle": handle }))
}

fn op_add_node(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let name = field_str(req, "name")?;
    with_graph(handle, |g| {
        g.node(name);
    })?;
    Ok(json!({ "ok": true }))
}

fn op_add_edge(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let from = field_str(req, "from")?;
    let to = field_str(req, "to")?;
    let weight = req.get("weight").and_then(Value::as_f64).unwrap_or(1.0);
    with_graph(handle, |g| {
        let a = g.node(from);
        let b = g.node(to);
        g.graph.add_edge(a, b, weight);
    })?;
    Ok(json!({ "ok": true }))
}

fn op_shortest_path(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let from = field_str(req, "from")?;
    let to = field_str(req, "to")?;

    let result = with_graph(handle, |g| {
        let (Some(&start), Some(&goal)) = (g.index_of.get(from), g.index_of.get(to)) else {
            return Ok(None);
        };
        // A* with a zero heuristic is exactly Dijkstra -- petgraph's own
        // documented equivalence. Both algorithms require non-negative
        // edge weights; refuse honestly rather than returning a
        // meaningless "shortest" path under negative weights.
        if g.graph.edge_weights().any(|w| *w < 0.0) {
            return Err("shortest_path requires non-negative edge weights".to_string());
        }
        Ok(astar(&g.graph, start, |n| n == goal, |e| *e.weight(), |_| 0.0).map(|(cost, path)| {
            let names: Vec<String> = path.iter().map(|&idx| g.graph[idx].clone()).collect();
            (cost, names)
        }))
    })??;

    match result {
        Some((cost, names)) => Ok(json!({ "path": names, "cost": cost })),
        None => Ok(json!({ "path": null, "cost": null })),
    }
}

fn op_scc(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let mut components = with_graph(handle, |g| {
        let raw = tarjan_scc(&g.graph);
        let mut components: Vec<Vec<String>> = raw
            .into_iter()
            .map(|comp| {
                let mut names: Vec<String> = comp.into_iter().map(|idx| g.graph[idx].clone()).collect();
                names.sort();
                names
            })
            .collect();
        components.sort();
        components
    })?;
    components.sort();
    Ok(json!({ "components": components }))
}

fn op_toposort(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let order = with_graph(handle, |g| {
        toposort(&g.graph, None)
            .ok()
            .map(|order| order.into_iter().map(|idx| g.graph[idx].clone()).collect::<Vec<_>>())
    })?;
    match order {
        Some(names) => Ok(json!({ "acyclic": true, "order": names })),
        None => Ok(json!({ "acyclic": false, "order": null })),
    }
}

fn op_is_cyclic(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let cyclic = with_graph(handle, |g| is_cyclic_directed(&g.graph))?;
    Ok(json!({ "cyclic": cyclic }))
}

fn op_node_count(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let count = with_graph(handle, |g| g.graph.node_count())?;
    Ok(json!({ "count": count }))
}

fn op_edge_count(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let count = with_graph(handle, |g| g.graph.edge_count())?;
    Ok(json!({ "count": count }))
}

fn op_free_graph(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let mut guard = GRAPHS
        .lock()
        .map_err(|_| "internal: graph registry lock poisoned".to_string())?;
    let existed = guard.get_or_insert_with(HashMap::new).remove(&handle).is_some();
    if !existed {
        return Err(format!("unknown graph handle {handle}"));
    }
    Ok(json!({ "freed": true }))
}
