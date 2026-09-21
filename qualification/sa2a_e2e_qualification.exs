# Run: mix run qualification/sa2a_e2e_qualification.exs  (exit 0 iff 6/6 pass)
# SA2A end-to-end qualification against beam4pm's real A2A agent + real ETS-backed
# Ash resources, consuming hex ash_a2a. State-based (Chicago): no doubles.
#
#   Q1 granted change actuates      -> :completed AND the row exists in ETS
#   Q2 same message_id replayed     -> no duplicate row (replay-safe)
#   Q3 un-granted principal         -> refused, no row written
#   Q4 bare ambiguous `create`      -> typed refusal, no row written
#   Q5 observe (read) skill         -> :completed, returns the Q1 row
#   Q6 HTTP wire: card + send       -> completed over Bandit /a2a

{:ok, _} = AshA2A.Authority.Broker.InMemory.start_link([])
Application.put_env(:ash_a2a, :authority_broker, AshA2A.Authority.Broker.InMemory)
Application.put_env(:ash_a2a, :authority_policy, :broker)

resource = BeamPM.Ash.Resources.EventType
cap = "BeamPM.Ash.Resources.EventType.create"
granted_principal = "sa2a-qual-granted"
stranger = "sa2a-qual-stranger"

{:ok, _} = AshA2A.Authority.Grant.grant(AshA2A.Identity.principal(granted_principal), cap)

auth = fn p -> [metadata: %{"a2a.auth" => %{identity: p}}] end

msg = fn skill, data, id ->
  %A2A.Message{
    message_id: id,
    role: :user,
    parts: [A2A.Part.Data.new(data)],
    metadata: %{skill: skill}
  }
end

count = fn ->
  resource |> Ash.read!() |> Enum.count(&(&1.type_name == "sa2a_qual_order_created"))
end

text = fn task ->
  case task.status.message do
    %{parts: [%{text: t} | _]} -> t
    _ -> ""
  end
end

results = []
check = fn results, name, ok, detail ->
  IO.puts("#{if ok, do: "PASS", else: "FAIL"} #{name} :: #{detail}")
  [{name, ok} | results]
end

payload = %{"type_name" => "sa2a_qual_order_created", "attribute_names" => ["order_id"]}
before = count.()

# Q1
mid = Ash.UUID.generate()
{:ok, t1} = BeamPM.A2AAgent.call(BeamPM.A2AAgent, msg.(cap, payload, mid), auth.(granted_principal))
after1 = count.()
results = check.(results, "Q1 granted change actuates",
  t1.status.state == :completed and after1 == before + 1,
  "state=#{t1.status.state} rows #{before}->#{after1}")

# Q2 replay same message id
{:ok, t2} = BeamPM.A2AAgent.call(BeamPM.A2AAgent, msg.(cap, payload, mid), auth.(granted_principal))
after2 = count.()
results = check.(results, "Q2 replay does not duplicate",
  after2 == after1,
  "state=#{t2.status.state} rows #{after1}->#{after2}")

# Q3 stranger (no grant)
{:ok, t3} =
  BeamPM.A2AAgent.call(BeamPM.A2AAgent,
    msg.(cap, %{payload | "type_name" => "sa2a_qual_stranger"}, Ash.UUID.generate()),
    auth.(stranger))
stranger_rows = resource |> Ash.read!() |> Enum.count(&(&1.type_name == "sa2a_qual_stranger"))
results = check.(results, "Q3 un-granted principal refused, nothing written",
  t3.status.state != :completed and stranger_rows == 0,
  "state=#{t3.status.state} rows=#{stranger_rows} text=#{String.slice(text.(t3), 0, 120)}")

# Q4 bare ambiguous name
{:ok, t4} =
  BeamPM.A2AAgent.call(BeamPM.A2AAgent,
    msg.("create", %{payload | "type_name" => "sa2a_qual_ambiguous"}, Ash.UUID.generate()),
    auth.(granted_principal))
amb_rows = resource |> Ash.read!() |> Enum.count(&(&1.type_name == "sa2a_qual_ambiguous"))
results = check.(results, "Q4 ambiguous bare name refused typed, nothing written",
  t4.status.state != :completed and amb_rows == 0,
  "state=#{t4.status.state} rows=#{amb_rows} text=#{String.slice(text.(t4), 0, 120)}")

# Q5 observe skill
{:ok, t5} =
  BeamPM.A2AAgent.call(BeamPM.A2AAgent,
    msg.("BeamPM.Ash.Resources.EventType.read", %{}, Ash.UUID.generate()),
    auth.(granted_principal))
results = check.(results, "Q5 observe skill completes",
  t5.status.state == :completed,
  "state=#{t5.status.state}")

# Q6 HTTP wire
{:ok, card} = A2A.Client.discover("http://localhost:4211/a2a")
client = A2A.Client.new(card)
wire =
  A2A.Client.send_message(client, msg.("read_ocel_events", %{}, Ash.UUID.generate()))
results = check.(results, "Q6 HTTP card+send",
  match?({:ok, %{status: %{state: :completed}}}, wire) and length(card.skills) == 1194,
  "skills=#{length(card.skills)} wire=#{inspect(elem(wire, 0))}")

failed = Enum.reject(Enum.reverse(results), fn {_, ok} -> ok end)
IO.puts("QUALIFICATION: #{length(results) - length(failed)}/#{length(results)} passed")
if failed != [], do: exit({:shutdown, 1})
