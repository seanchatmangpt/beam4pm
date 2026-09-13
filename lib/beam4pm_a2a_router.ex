defmodule BeamPM.A2ARouter do
  @moduledoc """
  Thin `Plug.Router` forwarding `/a2a` to `A2A.Plug` (agent card discovery +
  JSON-RPC dispatch), so the agent-facing A2A HTTP listener is reachable at
  a real, named mount path rather than the plug's own root.

  Hand-authored, not ggen-generated (supervision/HTTP-mount wiring, same
  class of manufacturing input as `beam4pm_application.ex`).
  """
  use Plug.Router

  @a2a_port Application.compile_env(:beam4pm, :a2a_port, 4211)
  @a2a_base_url Application.compile_env(
                  :beam4pm,
                  :a2a_base_url,
                  "http://localhost:#{@a2a_port}/a2a"
                )

  plug(:match)
  plug(:dispatch)

  forward("/a2a",
    to: A2A.Plug,
    init_opts: [agent: BeamPM.A2AAgent, base_url: @a2a_base_url]
  )

  match(_, do: send_resp(conn, 404, "not found"))
end
