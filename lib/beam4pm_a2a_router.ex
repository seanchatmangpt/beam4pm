defmodule BeamPM.A2ARouter.Mount do
  @moduledoc false
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    opts = AshA2A.Protocol.Plug.init(agent: BeamPM.A2AAgent, base_url: BeamPM.A2ARouter.base_url())
    AshA2A.Protocol.Plug.call(conn, opts)
  end
end

defmodule BeamPM.A2ARouter do
  @moduledoc """
  Thin `Plug.Router` forwarding `/a2a` to `AshA2A.Protocol.Plug` (agent card discovery +
  JSON-RPC dispatch), so the agent-facing A2A HTTP listener is reachable at
  a real, named mount path rather than the plug's own root.

  Hand-authored, not ggen-generated (supervision/HTTP-mount wiring, same
  class of manufacturing input as `beam4pm_application.ex`).
  """
  use Plug.Router

  # base_url is resolved per request from runtime config (never compile_env), so a
  # port-0 test listener or a release env override is reflected in the agent card.
  @doc false
  def base_url do
    Application.get_env(:beam4pm, :a2a_base_url) ||
      "http://localhost:#{Application.get_env(:beam4pm, :a2a_public_port) || Application.get_env(:beam4pm, :a2a_port, 4211)}/a2a"
  end

  plug(:match)
  plug(:dispatch)

  forward("/a2a", to: BeamPM.A2ARouter.Mount)

  match(_, do: send_resp(conn, 404, "not found"))
end
