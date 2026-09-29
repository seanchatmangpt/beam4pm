defmodule BeamPM.Application do
  @moduledoc """
  Top-level OTP application for beam4pm's runtime.

  Starts `BeamPM.OcelIngest.Router` (`lib/beam4pm_ocel_ingest.ex`, generated
  by ggen_igniter from the admitted `bpmi:AdmittedIngestRoute` graph) behind
  a real Bandit HTTP listener -- beam4pm's own independent network-facing
  ingestion capability, not a dependency on ex4pm.

  Not itself ggen-generated: per `docs/jira/v26.8.29/
  03-architecture-and-ggen-manufacturing.md`'s source authority policy,
  supervision-tree wiring is a manufacturing input (like `mix.exs`), never
  generated output.

  Also mounts the agent-facing A2A HTTP listener (`A2A.Plug`/Bandit on its
  own port, at `/a2a`, in front of `BeamPM.A2AAgent`) ADDITIVELY, alongside
  the OCEL ingest listener above -- it does not replace or touch it, and it
  does not replace ex4pm's existing `Ex4pm.Engine.Beam4pm` HTTP route-table
  client. `BeamPM.A2AAgent` itself is booted by `:ash_a2a`'s own Application
  callback (`config :ash_a2a, :agents, [BeamPM.A2AAgent]` in
  `config/config.exs`), not here -- starting its `A2A.AgentSupervisor` a
  second time in this tree would double-register the agent name and crash
  boot. See `BeamPM.A2AAgent`'s moduledoc for the curated-skill boundary.
  """
  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:beam4pm, :ocel_ingest_port, 4210)
    a2a_port = Application.get_env(:beam4pm, :a2a_port, 4211)

    children =
      engine_supervisor() ++
        [
          {Bandit, plug: BeamPM.OcelIngest.Router, port: port},
          Supervisor.child_spec(
            {Bandit, plug: BeamPM.A2ARouter, port: a2a_port},
            id: :a2a_bandit
          )
        ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: BeamPM.Supervisor)

    # BeamPM.Evidence (lib/beam4pm_evidence.ex) -- attaches the real
    # [:beam4pm, :engine, engine, op] telemetry family (every generated
    # engine facade op) to both the OCEL ingest bridge and the OTel span
    # bridge. Supervision-tree wiring is a manufacturing input per this
    # module's own doc comment; this call, not a new generated template, is
    # the right place for it.
    :ok = BeamPM.Evidence.attach_all()

    result
  end

  # The graphlaw and ferroplan wasm engines run under their own supervisor
  # (permanent children, generous restart intensity so a killed engine is
  # rebuilt without taking the listeners down). Only engines whose artifact
  # exists (and, for graphlaw, whose sha256 pin verifies) are started: see
  # BeamPM.GraphlawAdmission.engine_children/0. With no engine artifact the
  # tree boots without them and admission calls fail closed.
  defp engine_supervisor do
    case BeamPM.GraphlawAdmission.engine_children() do
      [] ->
        []

      engines ->
        [
          %{
            id: BeamPM.EngineSupervisor,
            type: :supervisor,
            start:
              {Supervisor, :start_link,
               [engines, [strategy: :one_for_one, max_restarts: 100, max_seconds: 5, name: BeamPM.EngineSupervisor]]}
          }
        ]
    end
  end
end
