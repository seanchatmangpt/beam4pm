defmodule BeamPM.GallSemanticWorkObserver do
  @moduledoc """
  Connector from the authority-free GALL work envelope into OCEL 2.0.

  This script surface is hand-authored by repository doctrine. It does not
  mutate generated BeamPM source, does not promote standing, and does not grant
  actuation authority. It only validates exact subject correspondence and emits
  an object-centric observation envelope.
  """

  @sha ~r/^[0-9a-f]{40}$/
  @digest ~r/^sha256:[0-9a-f]{64}$/
  @standing ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED REFUSED)

  @prov_entity "http://www.w3.org/ns/prov#Entity"
  @prov_activity "http://www.w3.org/ns/prov#Activity"
  @prov_used "http://www.w3.org/ns/prov#used"
  @prov_generated "http://www.w3.org/ns/prov#wasGeneratedBy"
  @dct_identifier "http://purl.org/dc/terms/identifier"

  def project(descriptor, receipt, observed_at)
      when is_map(descriptor) and is_map(receipt) and is_binary(observed_at) do
    with :ok <- require_equal(descriptor, "schema", "gall.work-order-execution/2"),
         :ok <- require_equal(descriptor, "authority", "NONE"),
         :ok <- require_string(descriptor, "work_order_iri"),
         :ok <- require_string(descriptor, "checkpoint_iri"),
         :ok <- require_match(descriptor, "graph_digest", @digest),
         :ok <- require_string(descriptor, "repository_identity"),
         :ok <- require_match(descriptor, "base_sha", @sha),
         :ok <- require_string(receipt, "receipt_iri"),
         :ok <- require_match(receipt, "receipt_digest", @digest),
         :ok <- require_match(receipt, "candidate_sha", @sha),
         :ok <- require_string(receipt, "standing"),
         :ok <- require_equal(receipt, "authority", "NONE"),
         :ok <- same_subject(descriptor, receipt),
         :ok <- valid_timestamp(observed_at) do
      work_order = descriptor["work_order_iri"]
      receipt_iri = receipt["receipt_iri"]
      event_id = "urn:beam4pm:observation:" <> String.replace_prefix(receipt["receipt_digest"], "sha256:", "")

      {:ok,
       %{
         "objectTypes" => [
           %{"name" => @prov_entity, "attributes" => []}
         ],
         "eventTypes" => [
           %{"name" => @prov_activity, "attributes" => []}
         ],
         "objects" => [
           %{
             "id" => work_order,
             "type" => @prov_entity,
             "attributes" => [
               attribute(@dct_identifier, work_order, observed_at),
               attribute("urn:beam4pm:graphDigest", descriptor["graph_digest"], observed_at),
               attribute("urn:beam4pm:repositoryIdentity", descriptor["repository_identity"], observed_at),
               attribute("urn:beam4pm:baseSha", descriptor["base_sha"], observed_at)
             ],
             "relationships" => []
           },
           %{
             "id" => receipt_iri,
             "type" => @prov_entity,
             "attributes" => [
               attribute(@dct_identifier, receipt_iri, observed_at),
               attribute("urn:beam4pm:receiptDigest", receipt["receipt_digest"], observed_at),
               attribute("urn:beam4pm:candidateSha", receipt["candidate_sha"], observed_at),
               attribute("urn:beam4pm:standing", receipt["standing"], observed_at)
             ],
             "relationships" => [
               %{"objectId" => work_order, "qualifier" => @prov_generated}
             ]
           }
         ],
         "events" => [
           %{
             "id" => event_id,
             "type" => @prov_activity,
             "time" => observed_at,
             "attributes" => [],
             "relationships" => [
               %{"objectId" => work_order, "qualifier" => @prov_used},
               %{"objectId" => receipt_iri, "qualifier" => @prov_used}
             ]
           }
         ]
       }}
    end
  end

  def project(_, _, _), do: {:error, {:refused_gall_observation, :invalid_input}}

  defp same_subject(descriptor, receipt) do
    fields = ~w(work_order_iri checkpoint_iri graph_digest repository_identity base_sha)

    case Enum.find(fields, fn field -> descriptor[field] != receipt[field] end) do
      nil ->
        if receipt["standing"] in @standing or String.starts_with?(receipt["standing"], "REFUSED_"),
          do: :ok,
          else: {:error, {:refused_gall_observation, {:invalid_standing, receipt["standing"]}}}

      field ->
        {:error,
         {:refused_gall_observation,
          {:subject_mismatch, field, descriptor[field], receipt[field]}}}
    end
  end

  defp attribute(name, value, time), do: %{"name" => name, "value" => value, "time" => time}

  defp valid_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> :ok
      _ -> {:error, {:refused_gall_observation, :invalid_observed_at}}
    end
  end

  defp require_string(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, {:refused_gall_observation, {:missing, key}}}
    end
  end

  defp require_match(map, key, regex) do
    case map[key] do
      value when is_binary(value) ->
        if Regex.match?(regex, value),
          do: :ok,
          else: {:error, {:refused_gall_observation, {:invalid, key}}}

      _ ->
        {:error, {:refused_gall_observation, {:invalid, key}}}
    end
  end

  defp require_equal(map, key, value) do
    if map[key] == value,
      do: :ok,
      else: {:error, {:refused_gall_observation, {:mismatch, key, map[key], value}}}
  end

  def self_test do
    digest = "sha256:" <> String.duplicate("a", 64)
    receipt_digest = "sha256:" <> String.duplicate("c", 64)
    base = String.duplicate("b", 40)

    descriptor = %{
      "schema" => "gall.work-order-execution/2",
      "work_order_iri" => "urn:gall:work-order:test:001",
      "checkpoint_iri" => "urn:gall:checkpoint:test:001",
      "graph_digest" => digest,
      "repository_identity" => "seanchatmangpt/beam4pm",
      "base_sha" => base,
      "authority" => "NONE"
    }

    receipt = %{
      "work_order_iri" => descriptor["work_order_iri"],
      "checkpoint_iri" => descriptor["checkpoint_iri"],
      "graph_digest" => digest,
      "repository_identity" => descriptor["repository_identity"],
      "base_sha" => base,
      "receipt_iri" => "urn:gall:receipt:test:001",
      "receipt_digest" => receipt_digest,
      "candidate_sha" => String.duplicate("d", 40),
      "standing" => "ALIVE",
      "authority" => "NONE"
    }

    {:ok, envelope} = project(descriptor, receipt, "2026-09-19T23:30:00Z")
    true = length(envelope["objects"]) == 2
    true = length(envelope["events"]) == 1

    moved = Map.put(receipt, "graph_digest", "sha256:" <> String.duplicate("e", 64))

    {:error, {:refused_gall_observation, {:subject_mismatch, "graph_digest", _, _}}} =
      project(descriptor, moved, "2026-09-19T23:30:00Z")

    :ok
  end
end

case System.argv() do
  ["--self-test"] ->
    :ok = BeamPM.GallSemanticWorkObserver.self_test()
    IO.puts("GALL semantic-work observer self-test: PASS")

  [descriptor_path, receipt_path, observed_at] ->
    descriptor_path |> File.read!() |> JSON.decode!()
    |> then(fn descriptor ->
      receipt = receipt_path |> File.read!() |> JSON.decode!()

      case BeamPM.GallSemanticWorkObserver.project(descriptor, receipt, observed_at) do
        {:ok, envelope} -> IO.puts(JSON.encode!(envelope))
        {:error, reason} -> raise "GALL observation refused: #{inspect(reason)}"
      end
    end)

  _ ->
    IO.puts(:stderr, "usage: mix run scripts/gall_semantic_work_observer.exs <descriptor.json> <receipt.json> <observed_at> | --self-test")
    System.halt(2)
end
