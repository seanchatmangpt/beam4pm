# Real smoke test (not mix test/ExUnit) -- run with:
#   mix run qualification/a2a_smoke_test.exs
# Starts the real app, discovers the real AgentCard over HTTP, sends a real
# A2A message, and asserts on real returned data.

{:ok, card} = A2A.Client.discover("http://localhost:4211/a2a")
IO.puts("AGENT_CARD_NAME=#{card.name}")
IO.puts("AGENT_CARD_SKILLS=#{inspect(Enum.map(card.skills, & &1.id))}")

client = A2A.Client.new(card)

message = %{
  A2A.Message.new_user([A2A.Part.Data.new(%{})])
  | metadata: %{"skill" => "read_ocel_events"}
}

case A2A.Client.send_message(client, message) do
  {:ok, task} ->
    IO.puts("DISPATCH_STATE=#{task.status.state}")
    IO.puts("DISPATCH_RESULT=#{inspect(task)}")

  {:error, err} ->
    IO.puts("DISPATCH_ERROR=#{inspect(err)}")
end
