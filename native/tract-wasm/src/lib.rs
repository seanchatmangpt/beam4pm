//! tract-wasm: a real ONNX-inference engine (sonos/tract -- the same crate
//! Wasmtime's own WASI-NN implementation uses for this exact target)
//! compiled to wasm32-wasip1 behind a plain linear-memory JSON ABI (no
//! wasm-bindgen, no JS glue) so a BEAM host (wasmex/wasmtime) can call it
//! directly -- same shape as rust4pm-wasm, ferroplan-wasm, petgraph-wasm.
//! Loads and runs real ONNX models: no inference math is reimplemented
//! here, this crate only frames tract's own optimized runnable graph.
//!
//! # Wire contract
//!
//! One dispatch export: `tr_call(ptr, len) -> u64` packed as
//! `(out_ptr << 32) | out_len`. Request and response are UTF-8 JSON. Every
//! failure returns `{"error":{"code":..,"message":..,"retryable":bool}}`.
//!
//! Ops (`"op"` field of the request object):
//!   - `load_model` `{"model_b64": ...}` -- base64 ONNX bytes (JSON strings
//!     cannot carry raw protobuf bytes). Optimizes and compiles the model
//!     to a runnable plan immediately (not lazily) so a malformed/
//!     unsupported-op model fails loudly at load time, not on first run.
//!     -> `{"handle": n, "inputs": [{"name":s,"shape":[dims|null]}],
//!     "outputs": [{"name":s,"shape":[dims|null]}]}` (a `null` dim is a
//!     symbolic/dynamic axis tract could not fully resolve at load time --
//!     reported honestly, not guessed).
//!   - `run` `{"handle": n, "inputs": [{"shape":[dims],"data":[f32,...]}]}`
//!     -- one f32 tensor per model input, in declared input order.
//!     -> `{"outputs": [{"shape":[dims],"data":[f32,...]}]}`, one per
//!     model output, in declared output order.
//!   - `model_info` `{"handle": n}` -- same input/output fact shape as
//!     `load_model`'s response, without re-loading.
//!   - `free_model` `{"handle": n}` -> `{"freed": true}`
//!
//! Only f32 tensors are supported by this ABI (the overwhelmingly common
//! case for ONNX inference); a model with a non-f32 input/output is
//! refused explicitly at `run` time with a named error, never silently
//! coerced or truncated.
//!
//! # Handle space
//!
//! One monotonically increasing `u64` counter (starting at 1), one
//! registry (`MODELS: Mutex<Option<HashMap<u64, RunnableOnnxModel>>>`),
//! the same take-lock-free-reinsert discipline as the other three wasm
//! engines: the lock is never held across a `run` (real inference is the
//! one operation here worth not serializing the whole registry over).
//!
//! # Memory ownership contract
//!
//! Identical to the other three engines: `std::alloc::alloc`/`dealloc`,
//! `Layout::from_size_align(len, 1)` throughout. `tr_call` CONSUMES the
//! request buffer; the response buffer is host-owned, freed via
//! `tr_dealloc(out_ptr, out_len)` after reading.

use serde_json::{json, Value};
use std::alloc::Layout;
use std::collections::HashMap;
use std::io::Cursor;
use std::sync::Mutex;
use tract_onnx::prelude::*;

type Plan = RunnableModel<TypedFact, Box<dyn TypedOp>, TypedModel>;

static NEXT_HANDLE: Mutex<u64> = Mutex::new(1);
static MODELS: Mutex<Option<HashMap<u64, Plan>>> = Mutex::new(None);

fn next_handle() -> Result<u64, String> {
    let mut next = NEXT_HANDLE
        .lock()
        .map_err(|_| "internal: handle counter lock poisoned".to_string())?;
    let id = *next;
    *next += 1;
    Ok(id)
}

fn with_model<T>(handle: u64, f: impl FnOnce(&Plan) -> T) -> Result<T, String> {
    let guard = MODELS
        .lock()
        .map_err(|_| "internal: model registry lock poisoned".to_string())?;
    let plan = guard
        .as_ref()
        .and_then(|m| m.get(&handle))
        .ok_or_else(|| format!("unknown model handle {handle}"))?;
    Ok(f(plan))
}

fn insert_model(plan: Plan) -> Result<u64, String> {
    let id = next_handle()?;
    let mut guard = MODELS
        .lock()
        .map_err(|_| "internal: model registry lock poisoned".to_string())?;
    guard.get_or_insert_with(HashMap::new).insert(id, plan);
    Ok(id)
}

// ---------------------------------------------------------------------------
// Memory ABI (see the module doc's ownership contract)
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn tr_alloc(len: usize) -> *mut u8 {
    if len == 0 {
        return std::ptr::null_mut();
    }
    match Layout::from_size_align(len, 1) {
        Ok(layout) => unsafe { std::alloc::alloc(layout) },
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn tr_dealloc(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    if let Ok(layout) = Layout::from_size_align(len, 1) {
        unsafe { std::alloc::dealloc(ptr, layout) }
    }
}

#[no_mangle]
pub extern "C" fn tr_call(ptr: *mut u8, len: usize) -> u64 {
    let input: Vec<u8> = if ptr.is_null() || len == 0 {
        Vec::new()
    } else {
        let copied = unsafe { std::slice::from_raw_parts(ptr, len) }.to_vec();
        tr_dealloc(ptr, len);
        copied
    };
    let out = dispatch(&input).unwrap_or_else(|message| {
        serde_json::to_vec(&err_json("TR_ADAPTER", &message)).unwrap_or_else(|_| {
            b"{\"error\":{\"code\":\"TR_ADAPTER\",\"message\":\"internal: response serialization failed\",\"retryable\":false}}".to_vec()
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
        "load_model" => op_load_model(&req)?,
        "run" => op_run(&req)?,
        "model_info" => op_model_info(&req)?,
        "free_model" => op_free_model(&req)?,
        other => {
            return serde_json::to_vec(&err_json("TR_UNKNOWN_OP", &format!("unknown op `{other}`")))
                .map_err(|e| e.to_string())
        }
    };
    serde_json::to_vec(&response).map_err(|e| e.to_string())
}

/// One `[{"name":s,"shape":[dims|null]}]` entry per outlet -- `null` for
/// any axis tract could not resolve to a concrete integer at load time.
fn describe_outlets(model: &TypedModel, outlets: &[OutletId]) -> Vec<Value> {
    outlets
        .iter()
        .map(|&outlet| {
            let name = model.node(outlet.node).name.clone();
            let shape = model
                .outlet_fact(outlet)
                .ok()
                .map(|fact| {
                    fact.shape
                        .iter()
                        .map(|dim| dim.to_i64().ok().map(Value::from).unwrap_or(Value::Null))
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            json!({ "name": name, "shape": shape })
        })
        .collect()
}

fn op_load_model(req: &Value) -> Result<Value, String> {
    let model_b64 = req
        .get("model_b64")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing or non-string field `model_b64`".to_string())?;
    let bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, model_b64)
        .map_err(|e| format!("model_b64: invalid base64: {e}"))?;

    let mut cursor = Cursor::new(bytes);
    let inference_model = tract_onnx::onnx()
        .model_for_read(&mut cursor)
        .map_err(|e| format!("ONNX parse failed: {e}"))?;

    let typed = inference_model
        .into_optimized()
        .map_err(|e| format!("model optimization failed: {e}"))?;

    let inputs = describe_outlets(&typed, &typed.input_outlets().map_err(|e| e.to_string())?);
    let outputs = describe_outlets(&typed, &typed.output_outlets().map_err(|e| e.to_string())?);

    let plan = typed
        .into_runnable()
        .map_err(|e| format!("model compilation failed: {e}"))?;

    let handle = insert_model(plan)?;
    Ok(json!({ "handle": handle, "inputs": inputs, "outputs": outputs }))
}

fn op_model_info(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    with_model(handle, |plan| {
        let model = plan.model();
        let inputs = describe_outlets(model, model.input_outlets().unwrap_or_default());
        let outputs = describe_outlets(model, model.output_outlets().unwrap_or_default());
        json!({ "inputs": inputs, "outputs": outputs })
    })
}

fn op_run(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let inputs_json = req
        .get("inputs")
        .and_then(Value::as_array)
        .ok_or_else(|| "missing or non-array field `inputs`".to_string())?;

    let mut inputs: TVec<TValue> = TVec::new();
    for (i, input) in inputs_json.iter().enumerate() {
        let shape: Vec<usize> = input
            .get("shape")
            .and_then(Value::as_array)
            .ok_or_else(|| format!("inputs[{i}]: missing or non-array `shape`"))?
            .iter()
            .map(|v| v.as_u64().map(|n| n as usize))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| format!("inputs[{i}]: shape entries must be non-negative integers"))?;
        let data: Vec<f32> = input
            .get("data")
            .and_then(Value::as_array)
            .ok_or_else(|| format!("inputs[{i}]: missing or non-array `data`"))?
            .iter()
            .map(|v| v.as_f64().map(|f| f as f32))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| format!("inputs[{i}]: data entries must be numeric"))?;

        let expected: usize = shape.iter().product();
        if data.len() != expected {
            return Err(format!(
                "inputs[{i}]: shape {shape:?} implies {expected} values, data has {}",
                data.len()
            ));
        }

        let tensor = tract_ndarray::ArrayD::from_shape_vec(shape, data)
            .map_err(|e| format!("inputs[{i}]: shape/data mismatch: {e}"))?;
        inputs.push(Tensor::from(tensor).into());
    }

    let outputs = with_model(handle, |plan| plan.run(inputs))?
        .map_err(|e| format!("inference failed: {e}"))?;

    let out_json: Vec<Value> = outputs
        .iter()
        .map(|tvalue| {
            let arr = tvalue
                .to_array_view::<f32>()
                .map_err(|e| format!("output is not an f32 tensor: {e}"))?;
            let shape: Vec<usize> = arr.shape().to_vec();
            let data: Vec<f32> = arr.iter().copied().collect();
            Ok(json!({ "shape": shape, "data": data }))
        })
        .collect::<Result<Vec<_>, String>>()?;

    Ok(json!({ "outputs": out_json }))
}

fn op_free_model(req: &Value) -> Result<Value, String> {
    let handle = field_u64(req, "handle")?;
    let mut guard = MODELS
        .lock()
        .map_err(|_| "internal: model registry lock poisoned".to_string())?;
    let existed = guard.get_or_insert_with(HashMap::new).remove(&handle).is_some();
    if !existed {
        return Err(format!("unknown model handle {handle}"));
    }
    Ok(json!({ "freed": true }))
}
