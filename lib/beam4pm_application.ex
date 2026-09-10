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
  """
  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:beam4pm, :ocel_ingest_port, 4210)

    children = [
      {Bandit, plug: BeamPM.OcelIngest.Router, port: port}
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
end
