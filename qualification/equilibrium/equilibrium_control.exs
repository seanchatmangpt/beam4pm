defmodule BeamPM.Equilibrium.Control do
  @authority_rank %{observe: 0, select: 1, construct: 2, do: 3}

  def canonical(term) when is_map(term) do
    term |> Enum.map(fn {k,v} -> {to_string(k), canonical(v)} end)
    |> Enum.sort_by(&elem(&1,0)) |> Map.new()
  end
  def canonical(term) when is_list(term), do: Enum.map(term, &canonical/1)
  def canonical(term) when is_tuple(term), do: term |> Tuple.to_list() |> canonical()
  def canonical(term) when is_atom(term), do: Atom.to_string(term)
  def canonical(term), do: term

  def digest(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(canonical(term), [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  def admit(command, graph) do
    with :ok <- exact_subject(command, graph),
         :ok <- member(command.role, graph.roles, :unknown_role),
         :ok <- member(command.policy, graph.policies, :unknown_policy),
         :ok <- member(command.capability, graph.capabilities, :capability_not_projected),
         :ok <- authority(command, graph),
         :ok <- bounded(command),
         :ok <- epoch(command, graph) do
      {:ok, receipt(:admit, command, graph, %{standing: :admitted})}
    else
      {:error, reason} -> {:error, receipt(:refuse, command, graph, %{standing: :refused, reason: reason})}
    end
  end

  def select(command, candidates, graph) do
    with {:ok, admission} <- admit(command, graph) do
      lawful = Enum.filter(candidates, &lawful?(&1, command, graph))
      case lawful do
        [] -> {:error, receipt(:refuse, command, graph, %{standing: :refused, reason: :no_lawful_candidate})}
        _ ->
          chosen = Enum.min_by(lawful, &{Map.get(&1,:cost,0), -Map.get(&1,:reversibility,0), to_string(&1.id)})
          {:ok, %{kind: :select, candidate: chosen, authority_ceiling: command.authority_ceiling,
                  admission_receipt: admission.id,
                  receipt: receipt(:select, command, graph, %{candidate: chosen.id})}}
      end
    end
  end

  def construct(command, selection, graph) do
    if rank(command.authority_ceiling) < rank(:construct) do
      {:error, receipt(:refuse, command, graph, %{standing: :refused, reason: :construct_exceeds_authority})}
    else
      artifact = %{subject: command.subject, capability: command.capability,
        selected_candidate: selection.candidate.id, epoch: command.epoch,
        authority_ceiling: command.authority_ceiling}
      {:ok, artifact, receipt(:construct, command, graph, %{artifact_digest: digest(artifact)})}
    end
  end

  def enqueue(queue, work, limit) do
    cond do
      length(queue) >= limit -> {:error, :backpressure}
      Enum.any?(queue, &(&1.id == work.id)) -> {:ok, queue, :duplicate}
      true -> {:ok, queue ++ [Map.put(work, :state, :ready)], :enqueued}
    end
  end

  def claim(queue, provider, now, lease_ms) do
    case Enum.find_index(queue, &(&1.state == :ready)) do
      nil -> {:error, :empty}
      i ->
        work = Enum.at(queue, i)
        claimed = work |> Map.put(:state,:claimed) |> Map.put(:provider,provider)
          |> Map.put(:lease_until,now+lease_ms) |> Map.update(:attempt,1,&(&1+1))
        {:ok, List.replace_at(queue,i,claimed), claimed}
    end
  end

  def reclaim(queue, now) do
    Enum.map(queue, fn
      %{state: :claimed, lease_until: until} = w when until <= now ->
        w |> Map.put(:state,:ready) |> Map.drop([:provider,:lease_until])
      w -> w
    end)
  end

  def provider_extinction(queue, provider, now) do
    queue |> Enum.map(fn
      %{state: :claimed, provider: ^provider}=w -> Map.put(w,:lease_until,now)
      w -> w
    end) |> reclaim(now)
  end

  def reconcile(queue, completed) do
    ids = MapSet.new(Enum.map(completed,& &1.work_id))
    Enum.map(queue, fn w -> if MapSet.member?(ids,w.id), do: Map.put(w,:state,:completed), else: w end)
  end

  def replay(receipts) do
    ordered=Enum.sort_by(receipts,&{Map.get(&1,:seq,0),&1.id})
    %{receipt_count:length(ordered),chain_digest:digest(Enum.map(ordered,& &1.id))}
  end

  defp lawful?(c,command,graph) do
    c.subject == command.subject and c.capability == command.capability and
      c.planner in graph.planners and Map.get(c,:standing,:unknown)==:admitted and
      rank(Map.get(c,:authority,:observe)) <= rank(command.authority_ceiling)
  end
  defp exact_subject(c,g), do: if(c.subject==g.subject,do: :ok,else: {:error,:subject_mismatch})
  defp member(v,xs,r), do: if(v in xs,do: :ok,else: {:error,r})
  defp bounded(c), do: if(is_integer(c.max_steps) and c.max_steps>0 and c.max_steps<=10_000,do: :ok,else: {:error,:unbounded})
  defp epoch(c,g), do: if(c.epoch==g.epoch,do: :ok,else: {:error,:stale_epoch})
  defp authority(c,g) do
    ceiling=Map.get(g.authority,c.role,:observe)
    if rank(c.authority_ceiling)<=rank(ceiling) and c.authority_ceiling != :do,
      do: :ok, else: {:error,:authority_laundering}
  end
  defp rank(a), do: Map.get(@authority_rank,a,99)
  defp receipt(kind,c,g,consequence) do
    body=%{kind:kind,subject:c.subject,capability:c.capability,role:c.role,policy:c.policy,
      epoch:c.epoch,authority_ceiling:c.authority_ceiling,consequence:consequence,graph_digest:digest(g)}
    Map.put(body,:id,digest(body))
  end
end
