defmodule BeamPM.OcelLogStore do
  @moduledoc """
  ETS-backed persistence for whole OCEL 2.0 logs accepted by
  `POST /api/ocel/ingest` (`BeamPM.OcelLogIngest`). One row per accepted
  log: `{log_id, log_map}` where `log_map` is the validated wire map
  (events/eventTypes/objectTypes/objects).

  Hand-authored (supervision/ETS wiring, same manufacturing-input class as
  `beam4pm_application.ex`). Owns a named public ETS table so the ingest
  router and any reader (vitest/playwright clients through the HTTP
  listener) see one store; the GenServer is only the table owner.
  """

  use GenServer

  @table :beam4pm_ocel_logs
  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, @server))
  end

  @doc "Persist a validated log. Returns the assigned log_id."
  @spec put(map()) :: String.t()
  def put(log_map) when is_map(log_map) do
    log_id = "ocel-log-" <> Integer.to_string(System.system_time(:native))
    :ets.insert(@table, {log_id, log_map})
    log_id
  end

  @doc "Fetch a previously persisted log by id."
  @spec get(String.t()) :: {:ok, map()} | :error
  def get(log_id) when is_binary(log_id) do
    case :ets.lookup(@table, log_id) do
      [{^log_id, log_map}] -> {:ok, log_map}
      [] -> :error
    end
  end

  @doc "Count of accepted logs (test isolation aid)."
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table, :size) || 0
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
