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

    children = [
      {Bandit, plug: BeamPM.OcelIngest.Router, port: port},
      Supervisor.child_spec(
        {Bandit, plug: BeamPM.A2ARouter, port: a2a_port},
        id: :a2a_bandit
      )
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BeamPM.Supervisor)
  end
end
