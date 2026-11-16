defmodule BeamPM.A2ARouterHttpTest do
  @moduledoc """
  HTTP-level test through the real `BeamPM.A2ARouter` (Plug.Router) in front of
  the real `BeamPM.A2AAgent` booted by :ash_a2a's application. No doubles.
  """
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @opts BeamPM.A2ARouter.init([])

  defp call(conn), do: BeamPM.A2ARouter.call(conn, @opts)

  test "GET /a2a/.well-known/agent-card.json serves the live card" do
    conn = call(conn(:get, "/a2a/.well-known/agent-card.json"))
    assert conn.status == 200
    card = JSON.decode!(conn.resp_body)
    assert card["name"] == "beam4pm_a2a_agent"
    assert is_list(card["skills"]) and card["skills"] != []

    domain_count =
      BeamPM.Ash.Domain
      |> Ash.Domain.Info.resources()
      |> Enum.reduce(0, fn r, acc -> acc + length(Ash.Resource.Info.public_actions(r)) end)

    assert length(card["skills"]) == domain_count
  end

  test "POST /a2a message/send round trip completes a public skill" do
    body =
      JSON.encode!(%{
        "jsonrpc" => "2.0",
        "id" => "t-1",
        "method" => "message/send",
        "params" => %{
          "message" => %{
            "messageId" => "msg-http-#{System.unique_integer([:positive])}",
            "role" => "user",
            "parts" => [%{"kind" => "data", "data" => %{}}],
            "metadata" => %{"skill" => "BeamPM.Ash.Resources.OcelEvent.read"}
          }
        }
      })

    conn =
      conn(:post, "/a2a", body)
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 200
    resp = JSON.decode!(conn.resp_body)
    assert resp["id"] == "t-1"
    assert get_in(resp, ["result", "task", "status", "state"]) == "TASK_STATE_COMPLETED",
           inspect(resp)
  end

  test "unknown path returns 404" do
    conn = call(conn(:get, "/nope"))
    assert conn.status == 404
    assert conn.resp_body == "not found"
  end
end
