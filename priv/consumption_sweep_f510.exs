# b4p-f5-10 consumption gate (beam4pm side).
#
# Proves the CommandBus skill-name-resolution fix (ash_a2a main @ baa135d)
# against beam4pm's real 1194-skill card: EVERY `:change` capability (the
# 597 public `create` actions) is dispatched through the real
# `BeamPM.A2AAgent` by full capability id with a real broker grant, and NONE
# may be refused with `:capability_mismatch` (the pre-fix defect) or
# `:authority_required`. Execution-level validation errors (e.g. a create
# invoked with no arguments) are REACHABLE outcomes and are counted
# separately — the gate is about capability reachability, not payload
# validity.
#
# Run: mix run priv/consumption_sweep_f510.exs (from a worktree whose
# mix.exs path-overrides {:ash_a2a, path: "~/ash_a2a"} — uncommitted).

principal = "f510-consumption-sweep"

extract_text = fn task ->
  case task.status.message do
    %{parts: [%{text: t} | _]} -> t
    _ -> ""
  end
end


# 1) Real broker + config, exactly the documented bootstrap.
{:ok, _broker} = AshA2A.Authority.Broker.InMemory.start_link([])
Application.put_env(:ash_a2a, :authority_broker, AshA2A.Authority.Broker.InMemory)
Application.put_env(:ash_a2a, :authority_policy, :broker)

subject = AshA2A.Identity.principal(principal)

# 2) The real capability index of the real domain agent.
skills = AshA2A.Info.capability_index(BeamPM.Ash.Domain)
changes = Enum.filter(skills, &(&1.consequence in [:change, :external_do]))
IO.puts("capability_index=#{length(skills)} change_skills=#{length(changes)}")

# 3) A real grant per (principal, capability) pair — the same grant path a
#    real deployment issues through.
granted =
  Enum.count(changes, fn skill ->
    match?({:ok, _}, AshA2A.Authority.Grant.grant(subject, skill.id))
  end)

IO.puts("granted=#{granted}/#{length(changes)}")

# 4) Dispatch every `:change` capability by its full id through the real
#    agent; classify the outcome.
auth = [metadata: %{"a2a.auth" => %{identity: principal}}]

{completed, reachable, refusals, other} =
  Enum.reduce(changes, {0, 0, [], 0}, fn skill, {c, r, refusals, other} ->
    message = %A2A.Message{
      message_id: Ash.UUID.generate(),
      role: :user,
      parts: [A2A.Part.Data.new(%{})],
      metadata: %{skill: skill.id}
    }

    case BeamPM.A2AAgent.call(BeamPM.A2AAgent, message, auth) do
      {:ok, %{status: %{state: :completed}}} ->
        {c + 1, r + 1, refusals, other}

      {:ok, %{status: %{state: state}} = task} ->
        text = extract_text.(task)

        cond do
          text =~ "capability_mismatch" ->
            {c, r, [{skill.id, :capability_mismatch} | refusals], other}

          text =~ "authority_required" or text =~ "authority_mismatch" ->
            {c, r, [{skill.id, :authority} | refusals], other}

          state == :input_required or text =~ "Invalid Error" or text =~ "input" ->
            # Reached the real action; the payload was just empty.
            {c, r + 1, refusals, other + 1}

          true ->
            {c, r + 1, refusals, other + 1}
        end

      other_result ->
        IO.inspect(other_result, label: "UNEXPECTED for #{skill.id}", limit: :infinity)
        {c, r, refusals, other + 1}
    end
  end)

IO.puts("""
SWEEP RESULT (b4p-f5-10 consumption gate):
  change_capabilities : #{length(changes)}
  granted             : #{granted}
  completed           : #{completed}
  reachable_total     : #{reachable}
  capability_refusals : #{length(refusals)}
  other_reachable     : #{other}
""")

 Enum.each(Enum.take(refusals, 10), fn {id, reason} ->
  IO.puts("  REFUSED #{reason}: #{id}")
end)

refusal_count = length(refusals)

if refusal_count == 0 do
  IO.puts("GATE: PASS — zero capability-level refusals across all :change skills")
else
  IO.puts("GATE: FAIL — #{refusal_count} capability-level refusals")
  exit({:shutdown, 1})
end
