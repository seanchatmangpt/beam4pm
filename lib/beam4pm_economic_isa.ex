defmodule BeamPM.EconomicISA do
  @moduledoc """
  BEAM/OCEL projection of the canonical compact economic activity ABI.

  This module is a parity projection, not an independent semantic authority.
  The one-byte opcode identifies only the economic verb. Object identities,
  E2O/O2O relationships, values, provenance, and authority remain explicit
  OCEL facts outside the byte.

  `0x00` is UNKNOWN/NULL. `0xFF` is a lossless extended-semantic escape.
  Unassigned bytes are refused rather than acquiring beam4pm-local meanings.
  """

  alias BeamPM.Types.OcelEvent

  @unknown 0x00
  @escape 0xFF

  @registry %{
    0x00 => :unknown,
    0x01 => :quote,
    0x02 => :offer,
    0x03 => :bid,
    0x04 => :ask,
    0x05 => :discover,
    0x20 => :order,
    0x21 => :fill,
    0x22 => :sale,
    0x23 => :purchase,
    0x24 => :return,
    0x25 => :cancel,
    0x26 => :exchange,
    0x40 => :invoice,
    0x41 => :pay,
    0x42 => :settle,
    0x43 => :refund,
    0x44 => :authorize_payment,
    0x45 => :capture_payment,
    0x60 => :ship,
    0x61 => :deliver,
    0x62 => :receive,
    0x63 => :move,
    0x64 => :store,
    0x65 => :consume,
    0x80 => :sign,
    0x81 => :license,
    0x82 => :subscribe,
    0x83 => :renew,
    0x84 => :terminate,
    0x85 => :assign_right,
    0xA0 => :manufacture,
    0xA1 => :design,
    0xA2 => :produce,
    0xA3 => :provide_service,
    0xA4 => :prove,
    0xA5 => :inspect,
    0xA6 => :accept,
    0xC0 => :accrue,
    0xC1 => :recognize_revenue,
    0xC2 => :recognize_expense,
    0xC3 => :capitalize,
    0xC4 => :depreciate,
    0xC5 => :realize_value,
    0xC6 => :allocate,
    0xE0 => :observe,
    0xE1 => :authorize,
    0xE2 => :attest,
    0xE3 => :approve,
    0xE4 => :reject,
    0xE5 => :dispute,
    0xE6 => :resolve
  }

  @by_activity Map.new(@registry, fn {byte, activity} -> {activity, byte} end)

  @type activity :: atom()
  @type frame :: {:fixed, non_neg_integer(), activity()} | {:extended, String.t()}

  @spec registry() :: %{non_neg_integer() => activity()}
  def registry, do: @registry

  @spec unknown() :: 0
  def unknown, do: @unknown

  @spec escape() :: 255
  def escape, do: @escape

  @spec category(non_neg_integer()) ::
          :null
          | :market
          | :transaction
          | :payment_settlement
          | :logistics
          | :contract_rights
          | :production_service
          | :accounting_finance
          | :governance_authority
          | :extensions
          | :escape
          | {:error, :outside_byte_range}
  def category(0x00), do: :null
  def category(byte) when byte in 0x01..0x1F, do: :market
  def category(byte) when byte in 0x20..0x3F, do: :transaction
  def category(byte) when byte in 0x40..0x5F, do: :payment_settlement
  def category(byte) when byte in 0x60..0x7F, do: :logistics
  def category(byte) when byte in 0x80..0x9F, do: :contract_rights
  def category(byte) when byte in 0xA0..0xBF, do: :production_service
  def category(byte) when byte in 0xC0..0xDF, do: :accounting_finance
  def category(byte) when byte in 0xE0..0xEF, do: :governance_authority
  def category(byte) when byte in 0xF0..0xFE, do: :extensions
  def category(0xFF), do: :escape
  def category(_), do: {:error, :outside_byte_range}

  @spec lookup_byte(non_neg_integer()) :: {:ok, activity()} | {:error, term()}
  def lookup_byte(@escape), do: {:ok, :extended}

  def lookup_byte(byte) when is_integer(byte) and byte in 0..255 do
    case Map.fetch(@registry, byte) do
      {:ok, activity} -> {:ok, activity}
      :error -> {:error, {:unassigned_economic_opcode, byte}}
    end
  end

  def lookup_byte(byte), do: {:error, {:outside_byte_range, byte}}

  @spec lookup_activity(atom() | String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def lookup_activity(:extended), do: {:ok, @escape}

  def lookup_activity(activity) when is_binary(activity) do
    try do
      activity |> String.to_existing_atom() |> lookup_activity()
    rescue
      ArgumentError -> {:error, {:unknown_economic_activity, activity}}
    end
  end

  def lookup_activity(activity) when is_atom(activity) do
    case Map.fetch(@by_activity, activity) do
      {:ok, byte} -> {:ok, byte}
      :error -> {:error, {:unknown_economic_activity, activity}}
    end
  end

  @spec encode(activity() | String.t() | non_neg_integer() | {:extended, String.t()}) ::
          {:ok, binary()} | {:error, term()}
  def encode({:extended, semantic_id}) when is_binary(semantic_id) and byte_size(semantic_id) > 0,
    do: {:ok, <<@escape, semantic_id::binary>>}

  def encode({:extended, _}), do: {:error, :missing_extended_semantic_id}

  def encode(byte) when is_integer(byte) do
    with {:ok, activity} <- lookup_byte(byte),
         false <- activity == :extended do
      {:ok, <<byte>>}
    else
      true -> {:error, :missing_extended_semantic_id}
      {:error, _} = error -> error
    end
  end

  def encode(activity) when is_atom(activity) or is_binary(activity) do
    with {:ok, byte} <- lookup_activity(activity),
         false <- byte == @escape do
      {:ok, <<byte>>}
    else
      true -> {:error, :missing_extended_semantic_id}
      {:error, _} = error -> error
    end
  end

  @spec decode(binary()) :: {:ok, frame()} | {:error, term()}
  def decode(<<>>), do: {:error, :empty_economic_frame}
  def decode(<<@escape>>), do: {:error, :missing_extended_semantic_id}

  def decode(<<@escape, semantic_id::binary>>) do
    {:ok, {:extended, semantic_id}}
  end

  def decode(<<byte>>) do
    with {:ok, activity} <- lookup_byte(byte),
         false <- activity == :extended do
      {:ok, {:fixed, byte, activity}}
    else
      true -> {:error, :missing_extended_semantic_id}
      {:error, _} = error -> error
    end
  end

  def decode(<<_byte, _rest::binary>>), do: {:error, :trailing_bytes_on_fixed_economic_opcode}

  @doc """
  Project an economic activity into beam4pm's already-admitted OCEL event shape.

  The returned tuple preserves E2O relationships separately because
  `BeamPM.Types.OcelEvent` deliberately does not own relationship fields;
  beam4pm's OCEL wire convention represents them nested beside the event.

  This function manufactures an observation record only. It grants no DO
  authority and does not infer economic causality from the event occurrence.
  """
  @spec to_ocel_event(
          activity() | String.t() | non_neg_integer() | {:extended, String.t()},
          String.t(),
          String.t(),
          keyword()
        ) :: {:ok, OcelEvent.t(), list()} | {:error, term()}
  def to_ocel_event(activity, event_id, event_time, opts \\ [])
      when is_binary(event_id) and is_binary(event_time) and is_list(opts) do
    relationships = Keyword.get(opts, :relationships, [])

    with {:ok, encoded} <- encode(activity),
         {:ok, frame} <- decode(encoded),
         {:ok, event_type, byte, semantic_id} <- frame_identity(frame),
         attrs <- economic_attributes(byte, semantic_id, opts),
         {:ok, event} <-
           OcelEvent.new(%{
             event_id: event_id,
             event_type: event_type,
             event_time: event_time,
             attributes: attrs
           }) do
      {:ok, event, relationships}
    end
  end

  defp frame_identity({:fixed, byte, activity}),
    do: {:ok, Atom.to_string(activity), byte, nil}

  defp frame_identity({:extended, semantic_id}),
    do: {:ok, "extended", @escape, semantic_id}

  defp economic_attributes(byte, semantic_id, opts) do
    %{
      "economic:opcode" => byte,
      "economic:category" => category(byte) |> Atom.to_string()
    }
    |> maybe_put("economic:semantic_id", semantic_id)
    |> maybe_put("authority", Keyword.get(opts, :authority))
    |> maybe_put("provenance", Keyword.get(opts, :provenance))
    |> maybe_put("economic:value", Keyword.get(opts, :economic_value))
    |> Map.merge(Keyword.get(opts, :attributes, %{}))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
