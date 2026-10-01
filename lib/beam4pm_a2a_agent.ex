defmodule BeamPM.A2AAgent do
  @moduledoc """
  Agent-facing A2A entry point over the `BeamPM.Ash.Domain` capability
  index. Under ash_a2a 26.9.17 (the v26.9.12+ all-public-actions default),
  EVERY public Ash action on a resource extended by `BeamPM.Ash.Domain` is
  an A2A skill automatically -- the card currently advertises 1194 skills
  (597 `:read` -> `:observe`, 597 `:create` -> `:change`; `:change` skills
  additionally require authority per RFC-SA2A-001 S29). The domain's two
  curated `a2a do skill` blocks (`read_ocel_events`,
  `read_conformance_results` -- the SAME 2 resources already curated as
  AshAi tools) survive as display-name overrides only; they no longer limit
  what is exposed.

  Hand-authored, not ggen-generated: per `docs/jira/v26.8.29/
  03-architecture-and-ggen-manufacturing.md`'s source-authority policy,
  supervision-tree-adjacent wiring is a manufacturing input (like
  `beam4pm_application.ex` itself), never generated output.

  This is additive alongside ex4pm, which is now a real dependency of this
  repo (`{:ash_ex4pm, "~> 26.10"}` -- hex ex4pm 26.10.1, which removed the
  former `Ex4pm.Engine.Beam4pm` HTTP route-table client), not an external
  client. It never routes beam4pm's own internals (EngineOp dispatch, the
  OCEL/OTel evidence chain, `BeamPM.ReceiptChain`) through A2A/JSON-RPC.
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
