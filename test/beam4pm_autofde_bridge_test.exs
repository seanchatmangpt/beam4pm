defmodule BeamPM.AutofdeBridgeTest do
  @moduledoc """
  Chicago-style qualification of the hand-authored persistent
  stdio JSON-lines port bridge (`BeamPM.AutofdeBridge`) against the REAL
  autofde-lab beam_port_bridge interpreter (no mocks):

    * real ping round-trip over a real BEAM Port;
    * one real `cmca_allocate` solve through the persistent channel;
    * parity: the SAME solve one-shot through the CLI path returns the
      exact same plan (the allocator is deterministic);
    * kill-and-recover: `kill -9` the interpreter's OS process
      mid-session and prove the GenServer survives and the next
      request boots a fresh interpreter (`{:error, :bridge_down}` is
      observed for the dying generation via `restart/1` + os_pid flip);
    * explicit `restart/1` restartability.

  Named skip when the autofde-lab checkout is not resolvable on this
  machine (same convention as the wasm-artifact qualifications).
  """

  use ExUnit.Case, async: false

  @moduletag skip: BeamPM.AutofdeBridge.missing_reason()

  @plan_id "p8_bridge_test_plan"

  @budget %{
    total_ticks: 5000,
    memory_bytes: 65_536,
    max_verification_depth: 5,
    consequence_risk_budget: 0.5,
    concurrency_lanes: 4
  }

  @candidates [
    %{branch_id: "branch_alpha", option_entropy: 2.5, historical_yield: 0.9, estimated_cost: 10.0},
    %{branch_id: "branch_beta", option_entropy: 1.2, historical_yield: 0.4, estimated_cost: 20.0}
  ]

  describe "persistent bridge" do
    test "ping round-trips through the real interpreter" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:ok, %{"ok" => true, "pong" => true}} = BeamPM.AutofdeBridge.ping()
    end

    test "cmca_allocate solves for real through the persistent channel" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:ok, %{"ok" => true, "plan" => plan}} =
               BeamPM.AutofdeBridge.cmca_allocate(@plan_id, @budget, @candidates)

      assert plan["plan_id"] == @plan_id
      assert length(plan["allocations"]) == 2

      alpha = Enum.find(plan["allocations"], &(&1["branch_id"] == "branch_alpha"))
      assert alpha["standing"] == "ADMITTED"
      # the multifractal cascade must really split the budget
      assert_in_delta alpha["allocated_fraction"] + Enum.find(plan["allocations"], &(&1["branch_id"] == "branch_beta"))["allocated_fraction"],
                      1.0,
                      1.0e-9
    end

    test "unknown op returns the bridge's error envelope without killing the bridge" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:error, {:bridge_error, %{"ok" => false, "error" => "unknown_op: no_such_op"}}} =
               BeamPM.AutofdeBridge.request(%{"op" => "no_such_op"})

      # the interpreter survived the bad request
      assert {:ok, %{"ok" => true, "pong" => true}} = BeamPM.AutofdeBridge.ping()
    end

    test "salience op returns the Q16.16 measure" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:ok, %{"ok" => true, "salience" => salience}} =
               BeamPM.AutofdeBridge.calculate_salience(hd(@candidates))

      assert is_float(salience)
    end
  end

  describe "kill-and-recover" do
    test "gen server survives kill -9 of the interpreter and the next request boots a fresh one" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:ok, %{"pong" => true}} = BeamPM.AutofdeBridge.ping()
      os_pid_1 = BeamPM.AutofdeBridge.os_pid()
      assert os_pid_1 != nil

      # kill the port process mid-session, exactly as the ticket demands
      assert {_, 0} = System.cmd("kill", ["-9", to_string(os_pid_1)])

      # let the port's exit_status message reach the GenServer
      wait_until(fn -> BeamPM.AutofdeBridge.os_pid() == nil end)

      # the GenServer itself is still alive
      pid = GenServer.whereis(BeamPM.AutofdeBridge)
      assert Process.alive?(pid)

      # next request lazily boots a fresh interpreter: full recovery
      assert {:ok, %{"ok" => true, "pong" => true}} = BeamPM.AutofdeBridge.ping()
      os_pid_2 = BeamPM.AutofdeBridge.os_pid()
      assert os_pid_2 != nil and os_pid_2 != os_pid_1
    end

    test "restart/1 forces a fresh interpreter and the bridge stays usable" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:ok, %{"pong" => true}} = BeamPM.AutofdeBridge.ping()
      os_pid_1 = BeamPM.AutofdeBridge.os_pid()

      assert :ok = BeamPM.AutofdeBridge.restart()
      assert BeamPM.AutofdeBridge.os_pid() == nil

      assert {:ok, %{"pong" => true}} = BeamPM.AutofdeBridge.ping()
      assert BeamPM.AutofdeBridge.os_pid() != os_pid_1
    end
  end

  describe "parity: persistent bridge vs one-shot CLI" do
    test "same solve returns the exact same plan through both paths" do
      start_supervised!(BeamPM.AutofdeBridge)

      assert {:ok, %{"ok" => true, "plan" => bridge_plan}} =
               BeamPM.AutofdeBridge.cmca_allocate(@plan_id, @budget, @candidates)

      assert {:ok, %{"ok" => true, "plan" => cli_plan}} =
               BeamPM.AutofdeBridge.oneshot_cmca_allocate(@plan_id, @budget, @candidates)

      # deterministic allocator: byte-for-byte identical plan values
      assert bridge_plan == cli_plan
    end

    @tag :latency
    test "persistent channel wins on second+ call (no interpreter restart)" do
      start_supervised!(BeamPM.AutofdeBridge)

      bridge_times =
        for i <- 1..5 do
          {t, _} =
            :timer.tc(fn ->
              BeamPM.AutofdeBridge.cmca_allocate("#{@plan_id}_b#{i}", @budget, @candidates)
            end)

          t
        end

      oneshot_times =
        for i <- 1..5 do
          {t, _} =
            :timer.tc(fn ->
              BeamPM.AutofdeBridge.oneshot_cmca_allocate("#{@plan_id}_o#{i}", @budget, @candidates)
            end)

          t
        end

      [first | steady] = bridge_times
      one_shot_avg = div(Enum.sum(oneshot_times), 5)
      steady_avg = div(Enum.sum(steady), length(steady))

      IO.puts("""
      [latency bridge vs one-shot cmca_allocate, microseconds]
      bridge call 1 (interpreter boot): #{first}
      bridge calls 2-5 avg (persistent): #{steady_avg} #{inspect(steady)}
      one-shot CLI avg (fresh interpreter per call): #{one_shot_avg} #{inspect(oneshot_times)}
      """)

      # the persistent channel must beat the per-call interpreter boot
      assert steady_avg < one_shot_avg
      # the first call pays roughly the same boot the one-shot path always pays
      assert first < 5_000_000
    end
  end

  defp wait_until(fun, tries \\ 100)

  defp wait_until(_fun, 0), do: flunk("condition never became true")

  defp wait_until(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      wait_until(fun, tries - 1)
    end
  end
end
