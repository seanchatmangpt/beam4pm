defmodule BeamPM.A2AAgent do
  @moduledoc """
  Agent-facing A2A entry point over the curated `BeamPM.Ash.Domain` a2a
  skills (`read_ocel_events`, `read_conformance_results` -- the SAME 2
  resources already curated as AshAi tools).

  Hand-authored, not ggen-generated: per `docs/jira/v26.8.29/
  03-architecture-and-ggen-manufacturing.md`'s source-authority policy,
  supervision-tree-adjacent wiring is a manufacturing input (like
  `beam4pm_application.ex` itself), never generated output.

  This is additive: it does NOT replace ex4pm's existing
  `Ex4pm.Engine.Beam4pm` HTTP route-table client, and it never routes
  beam4pm's own internals (EngineOp dispatch, the OCEL/OTel evidence chain,
  `BeamPM.ReceiptChain`) through A2A/JSON-RPC -- only the two curated
  read-only Ash actions are exposed as A2A skills.
  """
  # GATE M2 deletes every manufactured projection before either engine runs.
  # During that bounded bootstrap window the canonical Ash domain source does
  # not exist yet, so compiling the host project must not ask AshA2A to inspect
  # a domain that cannot have been manufactured. A normal checkout always has
  # the projection and therefore compiles the real agent. This is derived from
  # exact source ownership, not an environment variable or caller-local flag.
  if File.exists?("lib/beam4pm_ash.ex") do
    Code.ensure_compiled!(BeamPM.Ash.Domain)
    use AshA2A.Agent, resource_or_domain: BeamPM.Ash.Domain, name: "beam4pm_a2a_agent"
  else
    @doc false
    def __bootstrap_stub__, do: :ok
  end
end
