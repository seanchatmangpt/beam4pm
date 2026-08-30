defmodule BeamPM.Rust4PM do
  @moduledoc """
  BEAM-side wrapper over the ONE process-mining engine: rust4pm
  (`process_mining = "=0.6.2"`) compiled to `wasm32-wasip1` and hosted in
  this VM via wasmex. All process-mining computation (XES import, variant
  projection, DFG discovery, alpha+++ discovery, PNML import, alignments,
  fitness, pm4py-ported stats ops) happens INSIDE the wasm module at
  `native/rust4pm-wasm/`; this module (and the Erlang/Gleam facades over
  it) only frames JSON requests and unpacks JSON responses. No algorithm
  is reimplemented on the BEAM side — a real wasm collaborator, Chicago
  discipline, same as the rf1/rf2 oracle bridges.

  ## Wire contract (linear-memory JSON ABI, proven by the rust4pm spike)

  The wasm module exports three functions:

    * `r4pm_alloc(len) -> ptr` — allocate a guest buffer for the request.
    * `r4pm_call(ptr, len) -> packed_u64` — dispatch one JSON request;
      the return packs the response buffer as `(out_ptr << 32) | out_len`.
    * `r4pm_dealloc(ptr, len)` — free the RESPONSE buffer after reading.

  Per-call sequence (implemented by the private `call/2` below):

  1. `JSON.encode!` the request map (stdlib `JSON`, house style — no Jason).
  2. `r4pm_alloc(len)` (exit-guarded, per-op timeout: its own execution is
     microseconds, but a concurrent long op holds the single store-executor
     queue, so the budget covers queueing). The returned i32 pointer is
     normalized (`band 0xFFFF_FFFF`) and a null pointer is refused as
     `{:error, {:wasmex, :guest_alloc_failed}}` — never written to.
  3. `Wasmex.Memory.write_binary(store, memory, ptr, data)` (byte offset);
     on failure the request buffer is best-effort freed before erroring.
  4. `Wasmex.call_function(pid, "r4pm_call", [ptr, len], timeout)` — the
     per-op timeout drives a real wasmtime epoch interrupt. On expiry (or
     any other call exit) this module STOPS AND DISCARDS the engine and
     returns `{:error, {:wasmex, {:engine_restarted, _}}}`: the guest
     builds with `panic="abort"` on the no-threads wasm std, so a trap
     mid-compute may abandon guest state that cannot be safely reused —
     every handle is invalidated and the next `start/0` builds a fresh
     instance. (Never pass `:infinity`; a runaway alignment would wedge
     the single store-executor queue.)
  5. Normalize the packed return: wasmex delivers the wasm `u64`
     reinterpreted as a SIGNED i64, so `Bitwise.band(packed,
     0xFFFF_FFFF_FFFF_FFFF)` first (exact under Elixir bignum semantics;
     only matters if guest memory exceeds 2 GiB, but it is one line), then
     `bsr`/`band` to split ptr/len.
  6. `Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)`.
  7. `r4pm_dealloc(out_ptr, out_len)` — the host owns the response buffer.
  8. `JSON.decode!`; `%{"error" => msg}` becomes `{:error, {:engine, msg}}`,
     anything else `{:ok, decoded_map}` (string-keyed, as decoded).

  Memory-ownership rule inherited from the crate's contract: `r4pm_call`
  CONSUMES and frees the request buffer itself — the host must never call
  `r4pm_dealloc` on the request pointer after `r4pm_call` (double free).
  Only the response buffer is deallocated host-side (step 7).

  ## Ops

  One public function per engine op — see each function's doc for the
  request shape it sends:

  `import_xes`, `import_xes_gz`, `log_stats`, `top_n_variants`,
  `discover_dfg`, `discover_alphappp`, `import_pnml`, `align_variants`,
  `align_trace`, `compute_fitness`, `activities_to_alphabet`,
  `activity_position`, `free_log`, `free_net`, and the OCEL-construction
  set (`ocel_new`, `ocel_add_event_type`/`ocel_add_object_type`,
  `ocel_add_object`/`ocel_add_event`, `ocel_stats`, `ocel_to_json`,
  `xes_to_ocel`, `free_ocel` — the rust4pm docs site's documented
  "Building a Linked OCEL" examples) (plus the `*_path` file
  conveniences, which `File.read!` host-side).

  Handles (`log` and `net`) are plain integers scoped to the engine
  process's wasm linear memory. `config`/`options` maps are passed to the
  engine VERBATIM (they deserialize via serde into `AlphaPPPConfig` /
  `AlignmentOptions` inside wasm); defaulting, validation, and the
  UNSUPPORTED guard for pm4py's discounted-A*-exponent cost model
  (`"exponent"`/`"discount"`/`"discount_exponent"` keys) all live
  engine-side — this wrapper never filters, injects, or fakes options.
  process_mining 0.6.2 has only the per-move-kind `CostFunction`; a
  discounted cost model is honestly refused by the engine, never emulated.

  ## Process model and crash semantics

  ONE named Wasmex GenServer (`BeamPM.Rust4PM.Engine`) serves all callers:
  the Wasmex GenServer never blocks during wasm execution (the NIF replies
  to callers directly), and the underlying store executor serializes ops
  one at a time in submission order, so concurrent BEAM callers are safe —
  each holds distinct guest buffers and every step above is atomic on the
  store. The one real cost of the singleton: a long-running alignment
  head-of-line-blocks the store queue; the per-op timeout bounds that.

  A supervisor/`start/0` restart produces a FRESH store: all previously
  returned log/net handles are invalid and callers must re-import. No
  `Wasmex.StoreLimits` is set (unbounded guest memory — the 29MB
  InternationalDeclarations import is spike-proven). WASI options are the
  defaults (`%Wasmex.Wasi.WasiOptions{}`): the ABI passes XES/PNML content
  by value, so no preopens are needed. Note `discover_alphappp` `println!`s
  progress lines to the default WASI stdout inside the guest; that is
  harmless noise here (rf2 precedent) — attach a `Wasmex.Pipe` as stdout
  if it ever needs silencing.

  Degradation when the wasm artifact is absent is a NAMED reason, not a
  fake: see `wasm_built?/0` / `wasm_missing_reason/0` (the tests use them
  for a named skip — a deliberate, documented divergence from rf1's raise).
  """

  import Bitwise

  @engine_name BeamPM.Rust4PM.Engine
  @pt_key {__MODULE__, :engine_handles}

  @wasm_rel "native/rust4pm-wasm/target/wasm32-wasip1/release/rust4pm_wasm.wasm"

  # Heavy ops: XES import (29MB spike-proven at ~1.2s, but leave headroom),
  # discovery, alignment, fitness. Cheap ops: handle-local queries + frees.
  @heavy_timeout 120_000
  @cheap_timeout 30_000

  @typedoc "Decoded string-keyed JSON response from the engine."
  @type resp :: map()

  @typedoc """
  `{:engine, msg}` = the wasm engine returned `{"error": msg}` (including
  the UNSUPPORTED discounted-cost refusal and unknown-handle errors);
  `{:wasmex, term}` = a host-level failure (engine not started, wasmex
  call/alloc/write failure, or a call timeout/exit).
  """
  @type err :: {:engine, String.t()} | {:wasmex, term()}

  @type result :: {:ok, resp()} | {:error, err()}

  # ---------------------------------------------------------------------
  # Engine lifecycle
  # ---------------------------------------------------------------------

  @doc "Repo-root-relative wasm artifact path, expanded (rf1 oracle_bin idiom)."
  @spec wasm_path() :: String.t()
  def wasm_path, do: Path.expand(@wasm_rel)

  @doc "Whether the wasm engine artifact has been built."
  @spec wasm_built?() :: boolean()
  def wasm_built?, do: File.exists?(wasm_path())

  @doc "Named reason used by the tests' skip tag when the wasm artifact is absent."
  @spec wasm_missing_reason() :: String.t()
  def wasm_missing_reason do
    "rust4pm_wasm.wasm not built at #{wasm_path()} -- run " <>
      "scripts/rust4pm_wasm_build.sh first, and run mix test from the project root"
  end

  @doc """
  Starts (or reuses) the one named engine instance. Idempotent:
  `{:error, {:already_started, pid}}` is normalized to `{:ok, pid}`.

  Restarting after a crash yields a fresh store — every handle previously
  returned by import/discover ops is invalid afterwards; re-import.
  """
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    case start_link_raw() do
      {:ok, pid} ->
        _ = handles!(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      other ->
        other
    end
  end

  @doc """
  Raw `Wasmex.start_link/1` under the engine name — the `child_spec/1`
  start function for use in a supervision tree (Wasmex exports no
  child_spec of its own). Prefer `start/0` for direct/test use.
  """
  @spec start_link_raw() :: {:ok, pid()} | {:error, term()}
  def start_link_raw do
    Wasmex.start_link(%{
      bytes: File.read!(wasm_path()),
      wasi: %Wasmex.Wasi.WasiOptions{},
      name: @engine_name
    })
  end

  @doc "Supervision-tree shim (not auto-installed; beam4pm has no Application module)."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: @engine_name,
      start: {__MODULE__, :start_link_raw, []},
      restart: :permanent,
      type: :worker
    }
  end

  # ---------------------------------------------------------------------
  # Ops — imports
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"import_xes","content":...}` — imports an entire XES document
  (UTF-8 binary, passed by value) and returns `{:ok, %{"handle" => n}}`.
  """
  @spec import_xes(binary(), keyword()) :: result()
  def import_xes(xes_content, opts \\ []) when is_binary(xes_content) do
    call(%{"op" => "import_xes", "content" => xes_content}, timeout(opts, @heavy_timeout))
  end

  @doc "`File.read!/1` host-side, then `import_xes/2` (raises if the path is absent)."
  @spec import_xes_path(Path.t(), keyword()) :: result()
  def import_xes_path(path, opts \\ []) do
    import_xes(File.read!(path), opts)
  end

  @doc """
  `{"op":"import_xes_gz","content_b64":...}` — gzip'd XES bytes,
  base64-encoded host-side (JSON strings cannot carry raw gzip bytes).
  """
  @spec import_xes_gz(binary(), keyword()) :: result()
  def import_xes_gz(gz_bytes, opts \\ []) when is_binary(gz_bytes) do
    call(
      %{"op" => "import_xes_gz", "content_b64" => Base.encode64(gz_bytes)},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc """
  `{"op":"import_pnml","content":...}` — imports a PNML document (UTF-8,
  by value; no WASI preopen) and returns
  `{:ok, %{"net_handle" => n, "summary" => %{...}}}`. A PNML without
  markings imports but later fails alignment with the engine's verbatim
  `NoInitialMarking`/`NoFinalMarking` error — reported honestly in
  `summary["has_initial_marking"]`/`summary["num_final_markings"]`.
  """
  @spec import_pnml(binary(), keyword()) :: result()
  def import_pnml(pnml_content, opts \\ []) when is_binary(pnml_content) do
    call(%{"op" => "import_pnml", "content" => pnml_content}, timeout(opts, @heavy_timeout))
  end

  @doc "`File.read!/1` host-side, then `import_pnml/2` (raises if the path is absent)."
  @spec import_pnml_path(Path.t(), keyword()) :: result()
  def import_pnml_path(path, opts \\ []) do
    import_pnml(File.read!(path), opts)
  end

  # ---------------------------------------------------------------------
  # Ops — log queries
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"log_stats","handle":n}` — `num_cases`/`num_variants`/
  `num_activities`/`activities` (sorted)/`top_variant`/`top_variant_count`.
  Field superset of the rf1 oracle wire (differential anchor).
  """
  @spec log_stats(non_neg_integer(), keyword()) :: result()
  def log_stats(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "log_stats", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"top_n_variants\",\"handle\":n,\"n\":n}` — descending-count variant list."
  @spec top_n_variants(non_neg_integer(), non_neg_integer(), keyword()) :: result()
  def top_n_variants(handle, n, opts \\ []) when is_integer(handle) and is_integer(n) do
    call(%{"op" => "top_n_variants", "handle" => handle, "n" => n}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"discover_dfg","handle":n}` — edges sorted by `(source, target)`,
  the identical sort to the rf1 oracle (element-for-element comparable).
  """
  @spec discover_dfg(non_neg_integer(), keyword()) :: result()
  def discover_dfg(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "discover_dfg", "handle" => handle}, timeout(opts, @heavy_timeout))
  end

  @doc """
  `{"op":"activities_to_alphabet","handle":n}` — pm4py
  `activities_to_alphabet` port: activities ranked by descending total
  event count (ties pinned to first-occurrence order in the log — a
  documented determinism pin over pandas' unstable tie order), mapped to
  bijective base-26 letters (`A..Z, AA, AB, ...`).
  """
  @spec activities_to_alphabet(non_neg_integer(), keyword()) :: result()
  def activities_to_alphabet(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "activities_to_alphabet", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"activity_position","handle":n,"activity":a}` — pm4py
  `get_activity_position_summary` port: full histogram of the activity's
  0-based within-trace indexes as ascending `[index, count]` pairs.
  Unknown activity returns empty positions (pm4py returns `{}`) — not an
  error.
  """
  @spec activity_position(non_neg_integer(), String.t(), keyword()) :: result()
  def activity_position(handle, activity, opts \\ [])
      when is_integer(handle) and is_binary(activity) do
    call(
      %{"op" => "activity_position", "handle" => handle, "activity" => activity},
      timeout(opts, @cheap_timeout)
    )
  end

  # ---------------------------------------------------------------------
  # Ops — discovery + conformance
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"discover_alphappp","handle":n[,"config":...]}` — alpha+++
  discovery. `config == nil` omits the key entirely (engine uses
  `AlphaPPPConfig::default()`); a map is passed verbatim and must carry
  all 7 serde fields. Returns `{:ok, %{"net_handle" => n, "summary" =>
  %{...}}}`; the discovered net always carries initial+final markings, so
  its handle feeds the alignment ops directly.
  """
  @spec discover_alphappp(non_neg_integer(), map() | nil, keyword()) :: result()
  def discover_alphappp(handle, config \\ nil, opts \\ []) when is_integer(handle) do
    %{"op" => "discover_alphappp", "handle" => handle}
    |> put_optional("config", config)
    |> call(timeout(opts, @heavy_timeout))
  end

  @doc """
  `{"op":"align_variants","log_handle":l,"net_handle":n[,"options":...]}`
  — per-variant optimal alignments (pm4py-style move pairs, computed
  engine-side). `options == nil` omits the key (engine default:
  `max_states: 5_000_000`, rf2's load-bearing quirk); a map passes
  verbatim, including any discounted-cost keys the engine will refuse as
  UNSUPPORTED.
  """
  @spec align_variants(non_neg_integer(), non_neg_integer(), map() | nil, keyword()) :: result()
  def align_variants(log_handle, net_handle, options \\ nil, opts \\ [])
      when is_integer(log_handle) and is_integer(net_handle) do
    %{"op" => "align_variants", "log_handle" => log_handle, "net_handle" => net_handle}
    |> put_optional("options", options)
    |> call(timeout(opts, @heavy_timeout))
  end

  @doc """
  `{"op":"align_trace","net_handle":n,"trace":[...][,"options":...]}` —
  aligns ONE plain activity-name trace against an imported/discovered net
  (the direct port surface for pm4py's `alignment_discounted_a_star.py`
  workflow, using the engine's standard optimal alignments; the discount
  exponent is UNSUPPORTED and refused engine-side, never faked).
  """
  @spec align_trace(non_neg_integer(), [String.t()], map() | nil, keyword()) :: result()
  def align_trace(net_handle, trace, options \\ nil, opts \\ [])
      when is_integer(net_handle) and is_list(trace) do
    %{"op" => "align_trace", "net_handle" => net_handle, "trace" => trace}
    |> put_optional("options", options)
    |> call(timeout(opts, @heavy_timeout))
  end

  @doc """
  `{"op":"compute_fitness","log_handle":l,"net_handle":n[,"options":...]}`
  — alignment-based fitness aggregates, field-compatible with the rf2
  oracle wire (differential anchor). Crate behavior surfaced verbatim: one
  failed variant fails the whole op with the serde-serialized error.
  """
  @spec compute_fitness(non_neg_integer(), non_neg_integer(), map() | nil, keyword()) :: result()
  def compute_fitness(log_handle, net_handle, options \\ nil, opts \\ [])
      when is_integer(log_handle) and is_integer(net_handle) do
    %{"op" => "compute_fitness", "log_handle" => log_handle, "net_handle" => net_handle}
    |> put_optional("options", options)
    |> call(timeout(opts, @heavy_timeout))
  end

  # ---------------------------------------------------------------------
  # Ops — handle release
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"free_log","handle":n}` — drops the log engine-side (the Rust
  value returns to the wasm allocator; linear memory itself never shrinks).
  """
  @spec free_log(non_neg_integer(), keyword()) :: result()
  def free_log(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "free_log", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"free_net\",\"handle\":n}` — drops the Petri net engine-side."
  @spec free_net(non_neg_integer(), keyword()) :: result()
  def free_net(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "free_net", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  # ---------------------------------------------------------------------
  # OCEL construction — the rust4pm docs site's own documented examples
  # ("Building a Linked OCEL"): declare event/object types, add events and
  # objects with E2O/O2O relations, inspect stats, export OCEL 2.0 JSON.
  # `xes_to_ocel/3` is the canonical-dataset variant: one object per XES
  # case, one OCEL event per XES event with an E2O to its case object.
  # ---------------------------------------------------------------------

  @doc "Create a new empty OCEL; returns `{:ok, %{\"ocel_handle\" => h}}`."
  def ocel_new(opts \\ []) do
    call(%{"op" => "ocel_new"}, timeout(opts, @cheap_timeout))
  end

  @doc "Declare an event type. `attributes`: list of %{\"name\" => _, \"type\" => _}."
  def ocel_add_event_type(ocel, name, attributes \\ [], opts \\ [])
      when is_integer(ocel) and is_binary(name) do
    call(
      %{"op" => "ocel_add_event_type", "ocel_handle" => ocel, "name" => name, "attributes" => attributes},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "Declare an object type. Same attribute shape as `ocel_add_event_type/4`."
  def ocel_add_object_type(ocel, name, attributes \\ [], opts \\ [])
      when is_integer(ocel) and is_binary(name) do
    call(
      %{"op" => "ocel_add_object_type", "ocel_handle" => ocel, "name" => name, "attributes" => attributes},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "Add an object. `o2o`: list of `[target_object_id, qualifier]` pairs."
  def ocel_add_object(ocel, id, type, o2o \\ [], opts \\ [])
      when is_integer(ocel) and is_binary(id) and is_binary(type) do
    call(
      %{"op" => "ocel_add_object", "ocel_handle" => ocel, "id" => id, "type" => type, "o2o" => o2o},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "Add an event (`time` RFC3339). `e2o`: `[object_id, qualifier]` pairs."
  def ocel_add_event(ocel, id, type, time, e2o \\ [], opts \\ [])
      when is_integer(ocel) and is_binary(id) and is_binary(type) and is_binary(time) do
    call(
      %{
        "op" => "ocel_add_event",
        "ocel_handle" => ocel,
        "id" => id,
        "type" => type,
        "time" => time,
        "e2o" => e2o
      },
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "Counts per event/object type plus totals."
  def ocel_stats(ocel, opts \\ []) when is_integer(ocel) do
    call(%{"op" => "ocel_stats", "ocel_handle" => ocel}, timeout(opts, @cheap_timeout))
  end

  @doc "Export the OCEL 2.0 JSON document (the crate's own serde shape)."
  def ocel_to_json(ocel, opts \\ []) when is_integer(ocel) do
    call(%{"op" => "ocel_to_json", "ocel_handle" => ocel}, timeout(opts, @cheap_timeout))
  end

  @doc """
  Build an OCEL from an imported XES log handle: object type
  `case_object_type` gets one object per case; every XES event becomes an
  OCEL event with one E2O (qualifier `qualifier`) to its case object.
  """
  def xes_to_ocel(log_handle, case_object_type, qualifier, opts \\ [])
      when is_integer(log_handle) and is_binary(case_object_type) and is_binary(qualifier) do
    call(
      %{
        "op" => "xes_to_ocel",
        "handle" => log_handle,
        "case_object_type" => case_object_type,
        "qualifier" => qualifier
      },
      timeout(opts, @heavy_timeout)
    )
  end

  @doc "Import an OCEL 2.0 JSON document (the crate's `import_ocel_json_slice`)."
  def import_ocel_json(json_content, opts \\ []) when is_binary(json_content) do
    call(
      %{"op" => "import_ocel_json", "content" => json_content},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc """
  Export the OCEL as OCEL 2.0 XML (the crate's `export_ocel_xml`). Returns
  `{:ok, %{"content_b64" => ...}}`; decode with `Base.decode64!/1`.
  """
  def ocel_to_xml(ocel, opts \\ []) when is_integer(ocel) do
    call(%{"op" => "ocel_to_xml", "ocel_handle" => ocel}, timeout(opts, @heavy_timeout))
  end

  @doc "Import an OCEL 2.0 XML document (the crate's `import_ocel_xml_slice`)."
  def import_ocel_xml(xml_bytes, opts \\ []) when is_binary(xml_bytes) do
    call(
      %{"op" => "import_ocel_xml", "content_b64" => Base.encode64(xml_bytes)},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc """
  Object-centric DFG for one object type (`get_dfg_of_object_type` over
  `SlimLinkedOCEL`): adjacent activity pairs per object's timestamp-ordered
  trace, sorted by count desc then (from, to) — the crate's own ordering.
  """
  def ocel_dfg_of_object_type(ocel, object_type, opts \\ [])
      when is_integer(ocel) and is_binary(object_type) do
    call(
      %{"op" => "ocel_dfg_of_object_type", "ocel_handle" => ocel, "object_type" => object_type},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc """
  Object-centric variants for one object type (`get_variants_of_object_type`
  over `SlimLinkedOCEL`), sorted by count desc then trace — the crate's own
  ordering. `n` (optional) truncates the rendered list; `num_variants` is
  always the full count.
  """
  def ocel_variants_of_object_type(ocel, object_type, opts \\ [])
      when is_integer(ocel) and is_binary(object_type) do
    base = %{
      "op" => "ocel_variants_of_object_type",
      "ocel_handle" => ocel,
      "object_type" => object_type
    }

    req =
      case Keyword.get(opts, :n) do
        nil -> base
        n when is_integer(n) and n > 0 -> Map.put(base, "n", n)
      end

    call(req, timeout(opts, @heavy_timeout))
  end

  @doc "Free an OCEL handle."
  def free_ocel(ocel, opts \\ []) when is_integer(ocel) do
    call(%{"op" => "free_ocel", "ocel_handle" => ocel}, timeout(opts, @cheap_timeout))
  end

  # ---------------------------------------------------------------------
  # Core private call — the wire sequence documented in the moduledoc
  # ---------------------------------------------------------------------

  defp call(req, timeout) when is_map(req) do
    data = JSON.encode!(req)
    len = byte_size(data)

    with {:ok, {pid, store, memory}} <- engine(),
         # Q1-F3: alloc goes through the same exit-guarded path as r4pm_call,
         # with the OP's timeout — its wasm execution is microseconds, but a
         # concurrent long op holds the store executor, and the default 5s
         # GenServer timeout would crash this caller instead of erroring.
         {:ok, [raw_ptr]} <- call_export(pid, "r4pm_alloc", [len], timeout),
         # Q1-F4: normalize the i32-as-signed pointer exactly like the packed
         # response word; a guest buffer above 2GiB otherwise arrives negative.
         ptr = band(raw_ptr, 0xFFFF_FFFF),
         # Q1-F2: a null pointer means guest allocation failure — writing the
         # payload at offset 0 would corrupt guest memory, so refuse instead.
         :ok <- if(ptr == 0, do: {:error, :guest_alloc_failed}, else: :ok),
         :ok <- write_request(pid, store, memory, ptr, len, data),
         {:ok, [packed]} <- call_export(pid, "r4pm_call", [ptr, len], timeout) do
      # r4pm_call has consumed (and freed) the request buffer at `ptr` —
      # deallocating it here would be a double free. Only the response
      # buffer below is host-owned.
      read_response(pid, store, memory, packed, timeout)
    else
      {:error, {:call_exit, _} = reason} ->
        # Q1-F1: a timeout/trap may have interrupted the guest mid-compute.
        # Under panic="abort" the guest cannot unwind, so any handle that was
        # checked out of a registry at that moment is gone, and (in general)
        # a trapped instance's allocator state is not trustworthy. Restart
        # the engine: converts "possibly wedged" into the documented
        # "restart invalidates all handles" contract.
        restart_engine()
        {:error, {:wasmex, {:engine_restarted, reason}}}

      {:error, reason} ->
        {:error, {:wasmex, reason}}
    end
  end

  # Q1-F3: one guarded gateway for every export call — GenServer.call
  # timeouts and noproc races surface as {:error, {:call_exit, _}} rather
  # than crashing the caller, honoring the module's @type err contract.
  defp call_export(pid, export, args, timeout) do
    Wasmex.call_function(pid, export, args, timeout)
  catch
    :exit, reason -> {:error, {:call_exit, reason}}
  end

  # Q1-F5: if the request write fails, the request buffer was NOT consumed
  # by r4pm_call — free it before surfacing the error (best-effort; a
  # failed dealloc here is a leak, not a crash).
  defp write_request(pid, store, memory, ptr, len, data) do
    case Wasmex.Memory.write_binary(store, memory, ptr, data) do
      :ok ->
        :ok

      {:error, _} = err ->
        _ = call_export(pid, "r4pm_dealloc", [ptr, len], @cheap_timeout)
        err
    end
  end

  defp read_response(pid, store, memory, packed, timeout) do
    # wasmex returns the wasm u64 reinterpreted as SIGNED i64; band with
    # 2^64-1 recovers the exact unsigned bit pattern (Elixir bignums treat
    # negatives as infinite two's complement, so this is exact).
    packed = band(packed, 0xFFFF_FFFF_FFFF_FFFF)
    out_ptr = bsr(packed, 32)
    out_len = band(packed, 0xFFFF_FFFF)

    out = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)
    # Q1-F3: a failed response-dealloc is a logged-shape leak, never a crash
    # (the bytes are already read; correctness is unaffected).
    _ = call_export(pid, "r4pm_dealloc", [out_ptr, out_len], timeout)

    case JSON.decode!(out) do
      %{"error" => msg} -> {:error, {:engine, msg}}
      decoded -> {:ok, decoded}
    end
  end

  # Q1-F1: stop the (possibly trap-wedged) engine and drop the cached
  # handles so the next call gets {:error, {:engine_not_started, _}} until
  # start/0 builds a fresh instance.
  defp restart_engine do
    case Process.whereis(@engine_name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :kill)
    end
  catch
    :exit, _ -> :ok
  end

  defp engine do
    case Process.whereis(@engine_name) do
      nil ->
        {:error, {:engine_not_started, "call BeamPM.Rust4PM.start/0 first"}}

      pid ->
        {:ok, handles!(pid)}
    end
  end

  # store/memory are stable per-instance handles: fetch once per engine pid
  # and cache in :persistent_term. Keying the cache by pid keeps it correct
  # across a supervisor restart (fresh pid -> fresh store/memory refetch).
  defp handles!(pid) do
    case :persistent_term.get(@pt_key, nil) do
      {^pid, _store, _memory} = cached ->
        cached

      _stale_or_missing ->
        {:ok, store} = Wasmex.store(pid)
        {:ok, memory} = Wasmex.memory(pid)
        entry = {pid, store, memory}
        :persistent_term.put(@pt_key, entry)
        entry
    end
  end

  defp put_optional(req, _key, nil), do: req
  defp put_optional(req, key, value), do: Map.put(req, key, value)

  defp timeout(opts, default), do: Keyword.get(opts, :timeout, default)
end
