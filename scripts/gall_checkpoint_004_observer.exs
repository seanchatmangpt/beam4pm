defmodule BeamPM.Gall.Observer004 do
  @moduledoc """
  GALL-004 independent observer qualification rail.

  The observer consumes three external artifacts:
    * a GALL-003 command handoff;
    * a post-state read from an independent system-of-record;
    * an OCEL-shaped event bundle.

  It never calls AshA2A.CommandBus and never actuates. A successful actuator
  reply is explicitly rejected as an independent post-state source.
  """

  @required_activities ~w(receipt_prepared do_attempted post_state_observed)

  def run(command_path, post_state_path, ocel_path, out_path) do
    with {:ok, command} <- decode(command_path),
         {:ok, post_state} <- decode(post_state_path),
         {:ok, ocel} <- decode(ocel_path),
         :ok <- valid_command(command),
         :ok <- independent_post_state(command, post_state),
         {:ok, ordering} <- validate_ocel(command, post_state, ocel) do
      receipt = %{
        "schema" => "beam4pm.gall.observer/v26.9.18",
        "standing" => "ALIVE",
        "gall_003_receipt_digest" => command["handoff_digest"],
        "producer_sha" => command["producer_sha"],
        "work_order_digest" => command["work_order_digest"],
        "semantic_subject_digest" => digest(command["semantic_subject"]),
        "capability_id" => command["capability_id"],
        "command_fingerprint" => command["command_fingerprint"],
        "independent_observer_id" => "BeamPM.Gall.Observer004",
        "post_state_digest" => post_state["post_state_digest"],
        "post_state_source" => post_state["source_type"],
        "ocel_digest" => digest(ocel),
        "ordering_witnesses" => ordering,
        "occurrence_count" => post_state["occurrence_count"],
        "falsifiers_attempted" => [
          "actuator_self_report_only",
          "identity_mismatch",
          "missing_prepared_event",
          "double_consequence"
        ],
        "authority" => "none"
      }

      receipt = Map.put(receipt, "observer_receipt_digest", digest(receipt))
      File.write!(out_path, Jason.encode!(receipt, pretty: true))
      {:ok, receipt}
    end
  end

  def self_test do
    root =
      Path.join(System.tmp_dir!(), "beam4pm-gall004-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    command = %{
      "handoff_digest" => sha("handoff"),
      "capability_id" => "Example.Resource.change",
      "command_id" => "cmd-1",
      "command_fingerprint" => sha("command"),
      "producer_sha" => String.duplicate("a", 40),
      "work_order_digest" => sha("work-order"),
      "pre_state_digest" => sha("pre-state"),
      "manufacturer_subject_digest" => sha("manufacturer"),
      "semantic_subject" => %{
        "graph_digest" => sha("graph"),
        "projection_digest" => sha("projection"),
        "manufacturer_digest" => sha("manufacturer")
      },
      "consequence" => "change"
    }

    post_state = %{
      "capability_id" => command["capability_id"],
      "command_fingerprint" => command["command_fingerprint"],
      "semantic_subject_digest" => digest(command["semantic_subject"]),
      "consequence_identity" => "row:42",
      "post_state_digest" => sha("post-state-changed"),
      "occurrence_count" => 1,
      "source_type" => "database_read",
      "source_locator" => "fixture://independent-db"
    }

    ocel = %{
      "events" => [
        event("receipt_prepared", 10, command),
        event("do_attempted", 20, command),
        event("do_acknowledged", 30, command),
        event("post_state_observed", 40, command)
      ]
    }

    paths = write_fixture(root, command, post_state, ocel)
    out = Path.join(root, "observer-receipt.json")
    {:ok, receipt} = run(paths.command, paths.post, paths.ocel, out)
    assert!(receipt["standing"] == "ALIVE", "positive witness must be ALIVE")

    bad_post = Map.put(post_state, "source_type", "actuator_reply")
    bad_paths = write_fixture(root <> "-self-report", command, bad_post, ocel)

    assert_match(
      {:error, {:refused_observer, :post_state_not_independent}},
      run(bad_paths.command, bad_paths.post, bad_paths.ocel, out <> ".bad1")
    )

    double_post = Map.put(post_state, "occurrence_count", 2)
    double_paths = write_fixture(root <> "-double", command, double_post, ocel)

    assert_match(
      {:error, {:refused_observer, :double_consequence}},
      run(double_paths.command, double_paths.post, double_paths.ocel, out <> ".bad2")
    )

    unchanged_post = Map.put(post_state, "post_state_digest", command["pre_state_digest"])
    unchanged_paths = write_fixture(root <> "-unchanged", command, unchanged_post, ocel)

    assert_match(
      {:error, {:refused_observer, :post_state_unchanged}},
      run(unchanged_paths.command, unchanged_paths.post, unchanged_paths.ocel, out <> ".bad3")
    )

    missing_prepared = %{"events" => Enum.drop(ocel["events"], 1)}
    missing_paths = write_fixture(root <> "-missing", command, post_state, missing_prepared)

    assert_match(
      {:error, {:refused_observer, {:missing_activity, "receipt_prepared"}}},
      run(missing_paths.command, missing_paths.post, missing_paths.ocel, out <> ".bad3")
    )

    File.rm_rf!(root)
    File.rm_rf!(root <> "-self-report")
    File.rm_rf!(root <> "-double")
    File.rm_rf!(root <> "-missing")
    File.rm_rf!(root <> "-unchanged")
    :ok
  end

  defp valid_command(command) do
    cond do
      not sha256?(command["handoff_digest"]) ->
        {:error, {:refused_observer, :gall_003_receipt_digest}}

      not git_sha?(command["producer_sha"]) ->
        {:error, {:refused_observer, :producer_sha}}

      not sha256?(command["work_order_digest"]) ->
        {:error, {:refused_observer, :work_order_digest}}

      not sha256?(command["pre_state_digest"]) ->
        {:error, {:refused_observer, :pre_state_digest}}

      not is_binary(command["capability_id"]) ->
        {:error, {:refused_observer, :capability_id}}

      not sha256?(command["command_fingerprint"]) ->
        {:error, {:refused_observer, :command_fingerprint}}

      command["consequence"] not in ["change", "external_do", :change, :external_do] ->
        {:error, {:refused_observer, :non_consequence_subject}}

      not is_map(command["semantic_subject"]) ->
        {:error, {:refused_observer, :semantic_subject}}

      true ->
        :ok
    end
  end

  defp independent_post_state(command, post) do
    expected_semantic = digest(command["semantic_subject"])

    cond do
      post["source_type"] in [nil, "actuator_reply", "command_bus_reply"] ->
        {:error, {:refused_observer, :post_state_not_independent}}

      post["capability_id"] != command["capability_id"] ->
        {:error, {:refused_observer, :capability_mismatch}}

      post["command_fingerprint"] != command["command_fingerprint"] ->
        {:error, {:refused_observer, :command_fingerprint_mismatch}}

      post["semantic_subject_digest"] != expected_semantic ->
        {:error, {:refused_observer, :semantic_subject_mismatch}}

      post["occurrence_count"] != 1 ->
        {:error, {:refused_observer, :double_consequence}}

      not sha256?(post["post_state_digest"]) ->
        {:error, {:refused_observer, :post_state_digest}}

      post["post_state_digest"] == command["pre_state_digest"] ->
        {:error, {:refused_observer, :post_state_unchanged}}

      true ->
        :ok
    end
  end

  defp validate_ocel(command, _post, %{"events" => events}) when is_list(events) do
    events = Enum.map(events, &normalize_event/1)
    by_activity = Map.new(events, &{&1["activity"], &1})

    with :ok <- required_activities(by_activity),
         :ok <- identities(command, events),
         {:ok, prepared} <- sequence(by_activity["receipt_prepared"]),
         {:ok, attempted} <- sequence(by_activity["do_attempted"]),
         {:ok, observed} <- sequence(by_activity["post_state_observed"]),
         true <- prepared < attempted and attempted < observed do
      {:ok,
       [
         %{"before" => "receipt_prepared", "after" => "do_attempted"},
         %{"before" => "do_attempted", "after" => "post_state_observed"}
       ]}
    else
      false -> {:error, {:refused_observer, :ordering_violation}}
      {:error, reason} -> {:error, {:refused_observer, reason}}
    end
  end

  defp validate_ocel(_command, _post, _),
    do: {:error, {:refused_observer, :invalid_ocel}}

  defp required_activities(by_activity) do
    case Enum.find(@required_activities, &(not Map.has_key?(by_activity, &1))) do
      nil -> :ok
      missing -> {:error, {:missing_activity, missing}}
    end
  end

  defp identities(command, events) do
    if Enum.all?(events, fn event ->
         event["command_id"] == command["command_id"] and
           event["capability_id"] == command["capability_id"] and
           command["command_id"] in event["related_object_ids"]
       end) do
      :ok
    else
      {:error, :ocel_identity_mismatch}
    end
  end

  # Accept both the compact qualification fixture and standard OCEL-style
  # event keys. Standard OCEL relationship objectId is normalized to the
  # internal object identity without changing the semantic subject.
  defp normalize_event(event) when is_map(event) do
    attrs =
      case event["attributes"] do
        map when is_map(map) -> map
        list when is_list(list) -> Map.new(list, fn item -> {item["name"], item["value"]} end)
        _ -> %{}
      end

    relationships = event["relationships"] || []

    %{
      "activity" =>
        event["activity"] || event["event_type"] || event["eventType"] || event["type"],
      "sequence" => event["sequence"] || attrs["sequence"],
      "command_id" => event["command_id"] || attrs["command_id"],
      "capability_id" => event["capability_id"] || attrs["capability_id"],
      "related_object_ids" =>
        Enum.flat_map(relationships, fn
          %{"objectId" => id} when is_binary(id) -> [id]
          %{"object_id" => id} when is_binary(id) -> [id]
          _ -> []
        end)
    }
  end

  defp sequence(%{"sequence" => sequence}) when is_integer(sequence), do: {:ok, sequence}
  defp sequence(_), do: {:error, :sequence_missing}

  defp decode(path) do
    case File.read(path) do
      {:ok, bytes} ->
        case Jason.decode(bytes) do
          {:ok, value} -> {:ok, value}
          {:error, reason} -> {:error, {:refused_observer, {:invalid_json, path, reason}}}
        end

      {:error, reason} ->
        {:error, {:refused_observer, {:unreadable, path, reason}}}
    end
  end

  defp digest(value) do
    value
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&("sha256:" <> (:crypto.hash(:sha256, &1) |> Base.encode16(case: :lower))))
  end

  defp canonical(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonical(item)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  defp sha(value),
    do: "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))

  defp sha256?("sha256:" <> hex), do: byte_size(hex) == 64 and hex =~ ~r/^[0-9a-f]+$/
  defp sha256?(_), do: false

  defp git_sha?(hex) when is_binary(hex), do: byte_size(hex) == 40 and hex =~ ~r/^[0-9a-f]+$/
  defp git_sha?(_), do: false

  defp event(activity, sequence, command) do
    %{
      "event_type" => activity,
      "attributes" => %{
        "sequence" => sequence,
        "command_id" => command["command_id"],
        "capability_id" => command["capability_id"]
      },
      "relationships" => [
        %{"qualifier" => "command", "objectId" => command["command_id"]}
      ]
    }
  end

  defp write_fixture(root, command, post, ocel) do
    File.mkdir_p!(root)
    command_path = Path.join(root, "gall-003-receipt.json")
    post_path = Path.join(root, "post-state.json")
    ocel_path = Path.join(root, "events.ocel.json")
    File.write!(command_path, Jason.encode!(command))
    File.write!(post_path, Jason.encode!(post))
    File.write!(ocel_path, Jason.encode!(ocel))
    %{command: command_path, post: post_path, ocel: ocel_path}
  end

  defp assert!(true, _message), do: :ok
  defp assert!(false, message), do: raise(message)

  defp assert_match(expected, actual) do
    if expected == actual do
      :ok
    else
      raise("GALL-004 self-test mismatch: expected #{inspect(expected)}, got #{inspect(actual)}")
    end
  end
end

case System.argv() do
  ["--self-test"] ->
    BeamPM.Gall.Observer004.self_test()
    IO.puts("GALL-004 self-test: PASS")

  [command, post_state, ocel, out] ->
    case BeamPM.Gall.Observer004.run(command, post_state, ocel, out) do
      {:ok, receipt} ->
        IO.puts(Jason.encode!(receipt))
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, inspect(reason))
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "usage: mix run scripts/gall_checkpoint_004_observer.exs -- --self-test")
    IO.puts(:stderr, "   or: mix run scripts/gall_checkpoint_004_observer.exs -- GALL003.json POST.json OCEL.json OUT.json")
    System.halt(2)
end
