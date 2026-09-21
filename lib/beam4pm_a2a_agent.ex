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
  # During that bounded bootstrap window the Ash domain is absent or not yet a
  # complete Spark DSL, so compiling the host project must not ask AshA2A to
  # inspect it. The gate owns both sentinels: /tmp covers host-side Igniter and
  # the repository-root sentinel crosses the pinned GGen container mount. A
  # normal checkout has neither and therefore compiles the real agent.
  bootstrap? =
    File.exists?("/tmp/beam4pm-a2a-gate-bootstrap") or
      File.exists?(".beam4pm-a2a-gate-bootstrap")

  if bootstrap? do
    # Use the protocol's own zero-skill agent implementation so application
    # supervision and registry discovery exercise the real OTP/A2A contracts
    # during destructive manufacture without claiming any domain capability.
    Code.eval_quoted(
      quote do
        use A2A.Agent,
          name: "beam4pm_regeneration_bootstrap",
          description: "Zero-skill agent available only during deterministic regeneration",
          version: "bootstrap",
          skills: []

        @impl A2A.Agent
        def handle_message(_message, _context),
          do: {:error, %{code: :regeneration_in_progress}}
      end,
      [],
      __ENV__
    )
  else
    # `use` is a macro and ordinary conditional syntax may expand it before
    # the module-body condition executes. Evaluate the real-agent definition
    # only after the bootstrap sentinel decision so the destructive
    # regeneration window cannot inspect an incomplete Ash domain.
    Code.eval_quoted(
      quote do
        Code.ensure_compiled!(BeamPM.Ash.Domain)
        use AshA2A.Agent,
          resource_or_domain: BeamPM.Ash.Domain,
          name: "beam4pm_a2a_agent"
      end,
      [],
      __ENV__
    )
  end
end
