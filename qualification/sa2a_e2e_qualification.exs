# Run: MIX_ENV=test mix run --no-start qualification/sa2a_e2e_qualification.exs  (exit 0 iff 6/6 pass)
# SA2A end-to-end qualification against beam4pm's real A2A agent + real ETS-backed
# Ash resources, consuming hex ash_a2a. State-based (Chicago): no doubles.
#
#   Q1 granted change actuates      -> :completed AND the row exists in ETS
#   Q2 same message_id replayed     -> no duplicate row (replay-safe)
#   Q3 un-granted principal         -> refused, no row written
#   Q4 bare ambiguous `create`      -> typed refusal, no row written
#   Q5 observe (read) skill         -> :completed, returns the Q1 row
#   Q6 HTTP wire: card + send       -> completed over Bandit /a2a

# Boot posture: the repo's own test posture (config/test.exs) — ash_a2a 26.10.8
# SecurityProfile.Boot refuses strict-profile violations at Application start,
# so this dev qualification script selects :legacy_compat (violations logged,
# not fatal) before the app starts. The broker/policy under test are read
# per-call, not at boot.
Application.put_env(:ash_a2a, :security_profile, :legacy_compat)

# Real durable broker (AshA2A.Authority.Broker.Ekv), standalone-startable —
# no cluster required. AshA2A.Application itself supervises the broker's
# real single-node EKV instance (authority_broker_children/0), so the
# {module, opts} form carries our fresh per-run data_dir; a fresh dir keeps
# deterministic grant token_ids off stale entries from earlier runs.
broker_data_dir =
  Path.join(System.tmp_dir!(), "beam4pm_sa2a_qual_broker_ekv_#{System.unique_integer([:positive])}")

Application.put_env(:ash_a2a, :authority_broker, {AshA2A.Authority.Broker.Ekv, data_dir: broker_data_dir})
Application.put_env(:ash_a2a, :authority_policy, :broker)

# Q6 exercises the real HTTP wire, and Q1/Q5 need the engine workers: start
# the host app — it depends on :ash_a2a, so this boots ash_a2a first (agent
# supervisor) AFTER the engine is up. 4211 is the dev default
# (BeamPM.Application); the test-env compile keeps ash_a2a's profile
# legacy_compat while this port env is read at runtime, so pinning it here
# is the lawful dev posture.
Application.put_env(:beam4pm, :a2a_port, 4211)
{:ok, _} = Application.ensure_all_started(:beam4pm)

resource = BeamPM.Ash.Resources.EventType
cap = "BeamPM.Ash.Resources.EventType.create"
granted_principal = "sa2a-qual-granted"
stranger = "sa2a-qual-stranger"

{:ok, _} = AshA2A.Authority.Grant.grant(AshA2A.Identity.principal(granted_principal), cap)

auth = fn p -> [metadata: %{"a2a.auth" => %{identity: p}}] end

msg = fn skill, data, id ->
  %AshA2A.Protocol.Message{
    message_id: id,
    role: :user,
    parts: [AshA2A.Protocol.Part.Data.new(data)],
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
mid = AshA2A.Protocol.ID.generate("msg")
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
    msg.(cap, %{payload | "type_name" => "sa2a_qual_stranger"}, AshA2A.Protocol.ID.generate("msg")),
    auth.(stranger))
stranger_rows = resource |> Ash.read!() |> Enum.count(&(&1.type_name == "sa2a_qual_stranger"))
results = check.(results, "Q3 un-granted principal refused, nothing written",
  t3.status.state != :completed and stranger_rows == 0,
  "state=#{t3.status.state} rows=#{stranger_rows} text=#{String.slice(text.(t3), 0, 120)}")

# Q4 bare ambiguous name
{:ok, t4} =
  BeamPM.A2AAgent.call(BeamPM.A2AAgent,
    msg.("create", %{payload | "type_name" => "sa2a_qual_ambiguous"}, AshA2A.Protocol.ID.generate("msg")),
    auth.(granted_principal))
amb_rows = resource |> Ash.read!() |> Enum.count(&(&1.type_name == "sa2a_qual_ambiguous"))
results = check.(results, "Q4 ambiguous bare name refused typed, nothing written",
  t4.status.state != :completed and amb_rows == 0,
  "state=#{t4.status.state} rows=#{amb_rows} text=#{String.slice(text.(t4), 0, 120)}")

# Q5 observe skill
{:ok, t5} =
  BeamPM.A2AAgent.call(BeamPM.A2AAgent,
    msg.("BeamPM.Ash.Resources.EventType.read", %{}, AshA2A.Protocol.ID.generate("msg")),
    auth.(granted_principal))
results = check.(results, "Q5 observe skill completes",
  t5.status.state == :completed,
  "state=#{t5.status.state}")

# Q6 HTTP wire.
# NAMED GAP (2026-11-08, lane V8-ELX-BROKER-e): the wire path is broken at the
# pinned combination ash_a2a@99280b85 + a2a 0.3.0, INDEPENDENT of the broker
# under test: `A2A.Plug` passes the decoded wire `%A2A.Message{}` straight
# through to `AshA2A.Agent.__dispatch__/4`, which only matches
# `%AshA2A.Protocol.Message{}` (agent.ex:349-353) -> typed `:invalid_message`
# failure; the failed `AshA2A.Protocol.Task` then hits
# `A2A.JSONRPC.encode_send_result/2` (a2a jsonrpc.ex:338), which has no
# clause for AshA2A task structs -> FunctionClauseError -> empty 200 body.
# No wire->protocol conversion exists in either dep. Q1-Q5 prove the broker
# swap in-process; Q6 stays asserting (never fake-passed) until the transport
# conversion lands in ash_a2a.
{:ok, card} = A2A.Client.discover("http://localhost:4211/a2a")
# The card's advertised url is a compile_env default (compiled under test env
# with a2a_port 0), so the client targets the real listener URL directly;
# the discovered card is still the thing whose skill count is guarded.
client = A2A.Client.new("http://localhost:4211/a2a")
wire =
  A2A.Client.send_message(client, %A2A.Message{
    message_id: AshA2A.Protocol.ID.generate("msg"),
    role: :user,
    parts: [A2A.Part.Data.new(%{})],
    metadata: %{skill: "read_ocel_events"}
  })

# The expected skill count is derived from the domain, never hardcoded: the
# card is built by `use AshA2A.Agent, resource_or_domain: BeamPM.Ash.Domain`
# from exactly the capability-index enumeration (every public action of every
# domain resource, AshA2A.CapabilityIndex.Compiler.compile/3), so any merged
# PR that grows the domain keeps this guard true. The old literal 1194 broke
# on the first such growth (domain now spans 647 resources).
domain_skill_count =
  BeamPM.Ash.Domain
  |> Ash.Domain.Info.resources()
  |> Enum.reduce(0, fn resource, acc ->
    acc + length(Ash.Resource.Info.public_actions(resource))
  end)

results = check.(results, "Q6 HTTP card+send",
  match?({:ok, %{status: %{state: :completed}}}, wire) and length(card.skills) == domain_skill_count,
  "skills=#{length(card.skills)} domain=#{domain_skill_count} wire=#{inspect(elem(wire, 0))}")

failed = Enum.reject(Enum.reverse(results), fn {_, ok} -> ok end)
IO.puts("QUALIFICATION: #{length(results) - length(failed)}/#{length(results)} passed")

# Durable receipt bound to the exact subject (BEAM4PM-26922-03): the guard
# records the HEAD/tree it just qualified so a later reader can check the
# receipt against the admitted subject instead of trusting a log line.
if failed == [] do
  {subject_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: File.cwd!())
  {subject_tree, 0} = System.cmd("git", ["rev-parse", "HEAD^{tree}"], cd: File.cwd!())
  now = DateTime.utc_now() |> DateTime.to_iso8601()
  receipt_dir = Path.join(["docs/jira/v26.9.22/receipts"])
  File.mkdir_p!(receipt_dir)
  receipt_path = Path.join(receipt_dir, "sa2a-e2e-latest.json")

  File.write!(receipt_path,
    Jason.encode!(
      %{
        "receipt" => "sa2a-e2e-qualification",
        "subject_sha" => String.trim(subject_sha),
        "subject_tree" => String.trim(subject_tree),
        "verifier" => "mix run qualification/sa2a_e2e_qualification.exs",
        "checks" => length(results),
        "failed" => 0,
        "recorded_at" => now
      },
      pretty: true
    ) <> "\n"
  )

  IO.puts("receipt: #{receipt_path}")
end

if failed != [], do: exit({:shutdown, 1})
