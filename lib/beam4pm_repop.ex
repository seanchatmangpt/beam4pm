defmodule BeamPM.Repop.Session do
  @moduledoc """
  Opaque session handle for `BeamPM.Repop`: one wasmex Store + compiled
  Module + Instance + Memory view. Calls on one session serialize through
  its store; open one per consumer as needed (`BeamPM.Repop.open/0`).
  """

  @enforce_keys [:store, :module, :instance, :memory]
  defstruct [:store, :module, :instance, :memory]

  @type t :: %__MODULE__{
          store: Wasmex.Store.t(),
          module: Wasmex.Module.t(),
          instance: Wasmex.Instance.t(),
          memory: Wasmex.Memory.t()
        }
end

defmodule BeamPM.Repop do
  # Y8 SLA minimal-unblock (disclosed in the Y8 receipt): %Session{} here is
  # BeamPM.Repop.Session, defined above in this file; alias it explicitly.
  alias BeamPM.Repop.Session

  @moduledoc ~S"""
  Session-style wasmex host for the `repop` kernel, compiled to
  `wasm32-unknown-unknown` (`priv/repop/repop_kernel_wasm.wasm`, 901 B,
  zero imports) and executed via wasmex's low-level Store/Instance API.

  Template family: `BeamPM.Tract` (wasmex-hosted engine facade). The lighter
  session pattern is chosen deliberately: the repop kernel has no handles and
  no cross-call state to supervise (scratch is reset after every call), so a
  named GenServer would be structure without behaviour. A session is an
  opaque `%BeamPM.Repop.Session{}` opened with `open/0`; every call takes it
  explicitly and calls on one session serialize through that session's store.

  ## Wire contract (raw C-ABI, fixed-width integers, zero JSON)

  Exports used: `repop_abi_version/0 -> u32`, `repop_version/0 -> u32`
  (PACKED major<<16|minor<<8|patch -- decoded here, not read from memory),
  `repop_scratch_alloc(len u32) -> ptr` (0 on refusal; 0 is never a valid
  arena address), `repop_scratch_reset/0` (void; wasmex returns
  `{:ok, []}`), `repop_scratch_remaining/0 -> u32`, `repop_solve(intent_ptr,
  out_register_ptr) -> status`, `repop_cas_commit(slot, expected, value_ptr,
  out_version_ptr) -> status`, `repop_cas_read(slot, out_value_ptr,
  out_version_ptr) -> status`.

  Pointers delivered by wasmex are i64-signed renderings of wasm32 u32
  addresses (the packed-u64-signed-i64 law): normalize with
  `band(ptr, 0xFFFF_FFFF)` before use, and refuse a null (0) pointer rather
  than write at offset 0.

  ## Status vocabulary (typed, fail-closed)

  `0=OK, 1=ERR_BAD_INTENT, 2=ERR_NO_HYPERPLANE, 3=ERR_CAS_VERSION,
  4=ERR_CAS_ABSENT, 5=ERR_RECEIPT_INVALID, 6=ERR_OOM, 7=ERR_UNWIRED` --
  surfaced as `:ok`, `:err_bad_intent`, `:err_no_hyperplane`, `:err_cas_version`,
  `:err_cas_absent`, `:err_receipt_invalid`, `:err_oom`, `:err_unwired`.
  `:err_unwired` is the LANDED artifact's honest behaviour: validation is
  wired (real repop-abi codec inside the module), the P2/P3 kernel bodies are
  not. It means "capability absent", never success.

  ## Compile-time artifact pin

  The artifact's sha256 is read from the file at COMPILE TIME and asserted
  against the pinned literal below: a missing or drifted artifact fails the
  build, not the first call. Current pin:
  `3cc67f94d67927d3bed1c995a99538d9c0facb98a211ec4e911a134c21370e6b`
  (901 bytes; load receipt: repop
  `docs/jira/v26.11.9-integration/receipts/i3exp-wasmex-load.md`, Standing PASS).
  """

  import Bitwise

  alias BeamPM.Repop.Session

  @artifact_rel "priv/repop/repop_kernel_wasm.wasm"
  @pinned_sha "3cc67f94d67927d3bed1c995a99538d9c0facb98a211ec4e911a134c21370e6b"
  @pinned_size 901

  @abi_version 1
  @frame_size 64
  @call_timeout_ms 5_000

  @status_names %{
    1 => :err_bad_intent,
    2 => :err_no_hyperplane,
    3 => :err_cas_version,
    4 => :err_cas_absent,
    5 => :err_receipt_invalid,
    6 => :err_oom,
    7 => :err_unwired
  }

  @typedoc "Typed refusal/success status returned by the kernel exports."
  @type status ::
          :ok
          | :err_bad_intent
          | :err_no_hyperplane
          | :err_cas_version
          | :err_cas_absent
          | :err_receipt_invalid
          | :err_oom
          | :err_unwired
          | {:unknown_status, term()}

  @typedoc "Host-level failure (open/compile/instantiate/write/call failure)."
  @type host_err :: {:wasmex, term()}

  # ---------------------------------------------------------------------
  # Compile-time artifact pin
  # ---------------------------------------------------------------------

  # Y8 SLA minimal-unblock (lane Y8 receipt discloses this edit): module
  # attributes cannot appear in a module-body case guard; bind to variables.
  pinned_size = @pinned_size
  pinned_sha = @pinned_sha

  case File.read(Path.expand(@artifact_rel)) do
    {:ok, bytes} when byte_size(bytes) == pinned_size ->
      actual = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

      if actual == pinned_sha do
        :ok
      else
        raise CompileError,
          description:
            "repop wasm artifact sha drift: pinned #{pinned_sha}, on disk #{actual} " <>
              "(#{byte_size(bytes)} bytes) -- rotate @pinned_sha with a new receipt " <>
              "or rebuild the kernel"
      end

    {:ok, bytes} ->
      raise CompileError,
        description:
          "repop wasm artifact size drift: pinned #{@pinned_size}, on disk " <>
            "#{byte_size(bytes)} bytes at #{@artifact_rel}"

    {:error, reason} ->
      raise CompileError,
        description:
          "repop wasm artifact missing at compile time: #{@artifact_rel} (#{inspect(reason)}) " <>
            "-- build the kernel before compiling beam4pm"
  end

  @doc "Absolute path of the pinned wasm artifact."
  @spec artifact_path() :: String.t()
  def artifact_path, do: Path.expand(@artifact_rel)

  @doc "Pinned sha256 (lowercase hex) asserted at compile time."
  @spec artifact_sha() :: String.t()
  def artifact_sha, do: @pinned_sha

  @doc "Pinned byte size asserted at compile time."
  @spec artifact_bytes() :: pos_integer()
  def artifact_bytes, do: @pinned_size

  # ---------------------------------------------------------------------
  # Session lifecycle
  # ---------------------------------------------------------------------

  @doc """
  Opens a session: compile + instantiate the artifact with EMPTY imports
  (the artifact has zero imports; no WASI is needed). Calls on one session
  serialize through its store; open one per process/consumer as needed.
  """
  @spec open() :: {:ok, Session.t()} | {:error, host_err()}
  def open do
    with {:ok, bytes} <- read_artifact(),
         {:ok, store} <- Wasmex.Store.new(),
         {:ok, module} <- Wasmex.Module.compile(store, bytes),
         {:ok, instance} <- Wasmex.Instance.new(store, module, %{}),
         {:ok, memory} <- Wasmex.Memory.from_instance(store, instance) do
      {:ok, %Session{store: store, module: module, instance: instance, memory: memory}}
    else
      {:error, reason} -> {:error, {:wasmex, reason}}
    end
  end

  defp read_artifact do
    case File.read(artifact_path()) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {:wasmex, {:artifact_read, reason}}}
    end
  end

  # ---------------------------------------------------------------------
  # Identity exports
  # ---------------------------------------------------------------------

  @doc "`repop_abi_version/0 -> u32`, decoded to the Elixir side."
  @spec abi_version(Session.t()) :: {:ok, pos_integer()} | {:error, host_err()}
  def abi_version(%Session{} = session) do
    case call_export(session, "repop_abi_version", []) do
      {:ok, [1]} ->
        {:ok, 1}

      {:ok, [other]} ->
        {:error, {:wasmex, {:abi_version_mismatch, expected: @abi_version, got: other}}}

      other ->
        other
    end
  end

  @doc """
  `repop_version/0` returns a PACKED u32 (major<<16|minor<<8|patch) --
  decoded, never read from memory. Pinned artifact: `{:ok, "0.1.0"}`.
  """
  @spec version(Session.t()) :: {:ok, String.t()} | {:error, host_err()}
  def version(%Session{} = session) do
    case call_export(session, "repop_version", []) do
      {:ok, [packed]} when is_integer(packed) and packed >= 0 ->
        {:ok, decode_packed_version(packed)}

      other ->
        other
    end
  end

  @doc "Decode a packed repop version u32 into \"major.minor.patch\"."
  @spec decode_packed_version(non_neg_integer()) :: String.t()
  def decode_packed_version(packed) when is_integer(packed) and packed >= 0 do
    "#{bsr(packed, 16)}.#{band(bsr(packed, 8), 0xFF)}.#{band(packed, 0xFF)}"
  end

  # ---------------------------------------------------------------------
  # repop_solve
  # ---------------------------------------------------------------------

  @doc ~S"""
  Solve a 64-byte repop-abi `IntentFrame`. The frame is copied into kernel
  scratch (`repop_scratch_alloc` + write), `repop_solve(intent_ptr,
  out_register_ptr)` is called with an out register allocated beside it, and
  scratch is reset best-effort afterwards (per-call scratch never
  accumulates).

  `{:ok, status}` carries the LANDED artifact's typed status:
  `:err_bad_intent` for a frame that fails real repop-abi decode inside the
  module, `:err_unwired` for a VALID frame (the P2 solver is not yet wired).
  `{:error, reason}` is a host-level failure only (bad frame size, alloc
  refusal, wasmex call error) -- never a kernel refusal, those are typed
  statuses.
  """
  @spec solve(Session.t(), binary()) ::
          {:ok, status()} | {:error, {:bad_frame_size, non_neg_integer()} | host_err()}
  def solve(%Session{} = session, intent_frame) when is_binary(intent_frame) do
    len = byte_size(intent_frame)

    if len == @frame_size do
      result =
        with {:ok, intent_ptr} <- scratch_alloc(session, @frame_size),
             :ok <- write_bytes(session, intent_ptr, intent_frame),
             {:ok, out_ptr} <- scratch_alloc(session, @frame_size),
             {:ok, [status]} <- call_export(session, "repop_solve", [intent_ptr, out_ptr]) do
          {:ok, status_name(status)}
        else
          other -> normalize_call_error(other)
        end

      # Per-call scratch never accumulates: reset best-effort on every path.
      _ = call_export(session, "repop_scratch_reset", [])
      result
    else
      {:error, {:bad_frame_size, len}}
    end
  end

  # ---------------------------------------------------------------------
  # CAS wrappers (P3 placeholders -- :err_unwired passthrough is honest)
  # ---------------------------------------------------------------------

  @doc ~S"""
  `repop_cas_commit(slot, expected, value_ptr, out_version_ptr) -> status`.
  The landed P3-prior placeholder returns `:err_unwired` for well-formed
  calls; the pointer arguments are caller-supplied scratch allocated here so
  the call exercises the real export surface. `{:error, {:bad_frame_size, n}}`
  is a host-side guard on the 64-byte frame law.
  """
  @spec cas_commit(Session.t(), non_neg_integer(), non_neg_integer(), binary()) ::
          {:ok, status()} | {:error, {:bad_frame_size, non_neg_integer()} | host_err()}
  def cas_commit(%Session{} = session, slot, expected, value)
      when is_integer(slot) and slot >= 0 and is_integer(expected) and expected >= 0 and
             is_binary(value) and byte_size(value) == @frame_size do
    result =
      with {:ok, value_ptr} <- scratch_alloc(session, @frame_size),
           :ok <- write_bytes(session, value_ptr, value),
           {:ok, out_version_ptr} <- scratch_alloc(session, @frame_size),
           {:ok, [status]} <-
             call_export(session, "repop_cas_commit", [slot, expected, value_ptr, out_version_ptr]) do
        {:ok, status_name(status)}
      else
        other -> normalize_call_error(other)
      end

    _ = call_export(session, "repop_scratch_reset", [])
    result
  end

  def cas_commit(%Session{} = _session, _slot, _expected, value),
    do: {:error, {:bad_frame_size, if(is_binary(value), do: byte_size(value), else: 0)}}

  @doc ~S"""
  `repop_cas_read(slot, out_value_ptr, out_version_ptr) -> status`. Landed
  placeholder returns `:err_unwired` (P3 CAS registry not yet wired).
  """
  @spec cas_read(Session.t(), non_neg_integer()) :: {:ok, status()} | {:error, host_err()}
  def cas_read(%Session{} = session, slot) when is_integer(slot) and slot >= 0 do
    result =
      with {:ok, out_value_ptr} <- scratch_alloc(session, @frame_size),
           {:ok, out_version_ptr} <- scratch_alloc(session, @frame_size),
           {:ok, [status]} <- call_export(session, "repop_cas_read", [slot, out_value_ptr, out_version_ptr]) do
        {:ok, status_name(status)}
      else
        other -> normalize_call_error(other)
      end

    _ = call_export(session, "repop_scratch_reset", [])
    result
  end

  # ---------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------

  @doc false
  @spec status_name(term()) :: status()
  def status_name(0), do: :ok
  def status_name(n) when is_integer(n) and n in 1..7, do: Map.fetch!(@status_names, n)
  def status_name(other), do: {:unknown_status, other}

  defp call_export(%Session{} = session, name, args) do
    Wasmex.Utils.native_request(fn from ->
      Wasmex.Instance.call_exported_function(
        session.store,
        session.instance,
        name,
        args,
        from,
        @call_timeout_ms
      )
    end)
  end

  # Scratch alloc: the guest returns 0 on refusal (0 is never a valid arena
  # address). Normalize the wasmex-delivered pointer per the
  # packed-u64-signed-i64 law (u32 address in an i64 slot), refuse null --
  # never write at offset 0.
  defp scratch_alloc(%Session{} = session, len) do
    case call_export(session, "repop_scratch_alloc", [len]) do
      {:ok, [0]} ->
        {:error, {:wasmex, :scratch_alloc_refused}}

      {:ok, [ptr]} when is_integer(ptr) and ptr > 0 ->
        {:ok, band(ptr, 0xFFFF_FFFF)}

      other ->
        other
    end
  end

  defp write_bytes(%Session{} = session, ptr, bytes) do
    case Wasmex.Memory.write_binary(session.store, session.memory, ptr, bytes) do
      :ok -> :ok
      {:error, reason} -> {:error, {:wasmex, {:write_failed, reason}}}
    end
  end

  defp normalize_call_error({:ok, [status]}), do: {:ok, status_name(status)}
  defp normalize_call_error({:error, _} = err), do: err
  defp normalize_call_error(other), do: {:error, {:wasmex, other}}
end
