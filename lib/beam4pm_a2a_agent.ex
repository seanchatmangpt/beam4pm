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

  This is additive: it does NOT replace ex4pm's existing
  `Ex4pm.Engine.Beam4pm` HTTP route-table client, and it never routes
  beam4pm's own internals (EngineOp dispatch, the OCEL/OTel evidence chain,
  `BeamPM.ReceiptChain`) through A2A/JSON-RPC.
  """
  use AshA2A.Agent, resource_or_domain: BeamPM.Ash.Domain, name: "beam4pm_a2a_agent"
end
