defmodule BeamPM.DfcmCmcaParityTest do
  use ExUnit.Case, async: false

  alias BeamPM.Dfcm

  # Q16.16 fixed-point least significant bit: 1/65536. The certified CMCA
  # measure (vendored bcinr allocator, pinned commit 2ae60cf0) computes in
  # Q16.16; renormalized fractions must satisfy budget exactness within one
  # quantum.
  @q16_16_epsilon 1.52587890625e-05

  # All-dims-equal candidates: no Pareto domination, so every branch stays in
  # the nondominated set and reaches the allocator.
  defp synthetic_problem(count) do
    options =
      for i <- 1..count do
        %{
          id: "synth_#{String.pad_leading(Integer.to_string(i), 2, "0")}",
          goal_progress: 5,
          information_gain: 0,
          reuse: 3,
          reversibility: :reversible,
          irreversible_loss: 0,
          consequence: 0,
          verification_cost: 0
        }
      end

    %{options: options}
  end

  defp sum_fractions(allocations) do
    Enum.reduce(allocations, 0.0, &(&1["allocated_fraction"] + &2))
  end

  test "real CLI path allocates the A/B/C benchmark through the certified cmca allocator" do
    assert Dfcm.autofde_cli_available?()

    result = Dfcm.allocate_options(Dfcm.benchmark())

    assert result["allocator"] == "cmca"
    assert result.authority_ceiling == :select
    refute Map.has_key?(result, :do)

    allocations = result["allocations"]
    assert Enum.map(allocations, & &1["branch_id"]) == ["A", "B", "C"]
    assert Enum.all?(allocations, &(&1["standing"] == "ADMITTED"))
    assert Enum.all?(allocations, &(&1["allocated_fraction"] > 0.0))
  end

  test "budget-exactness: allocated fractions sum to 1.0 within the Q16.16 quantum" do
    for count <- [1, 2, 3, 5, 8] do
      result = Dfcm.allocate_options(synthetic_problem(count))

      assert result["allocator"] == "cmca"
      assert length(result["allocations"]) == count
      assert_in_delta sum_fractions(result["allocations"]), 1.0, @q16_16_epsilon
    end
  end

  test "budget mapping: plan id and discrete budget opts reach the cmca CLI" do
    result =
      Dfcm.allocate_options(Dfcm.benchmark(), %{
        plan_id: "p7_budget_map",
        total_ticks: 1_000,
        memory_bytes: 2_048
      })

    assert result["allocator"] == "cmca"
    assert result["plan_id"] == "p7_budget_map"

    total_ticks = Enum.reduce(result["allocations"], 0, &(&1["allocated_ticks"] + &2))
    assert total_ticks >= 0 and total_ticks <= 1_000
  end

  test "determinism: identical input twice yields an identical plan" do
    problem = Dfcm.benchmark()
    first = Dfcm.allocate_options(problem)
    second = Dfcm.allocate_options(problem)

    assert first == second
  end

  # CMCA zero-allocation law (autofde-lab cmca/cascade.py, observed runs
  # 2026-09-18): a candidate receives allocated_fraction == 0.0 ONLY when its
  # raw measured share falls below the pruning threshold (default 0.01), and
  # such a candidate is REPORTED with standing "PRUNED" (zero ticks, memory,
  # depth) -- never silently dropped. If every raw share fell below the
  # threshold, anti-starvation keeps exactly the top-measured candidate at
  # full renormalized mass. Outside this law no surviving candidate gets 0.0.
  test "zero-allocation law: admitted candidates carry positive share, zero only when PRUNED" do
    for problem <- [Dfcm.benchmark(), synthetic_problem(8)] do
      result = Dfcm.allocate_options(problem)

      assert result["allocator"] == "cmca"

      for allocation <- result["allocations"] do
        if allocation["allocated_fraction"] == 0.0 do
          assert allocation["standing"] == "PRUNED"
          assert allocation["allocated_ticks"] == 0
        else
          assert allocation["standing"] == "ADMITTED"
          assert allocation["allocated_fraction"] > 0.0
        end
      end
    end
  end

  # CMCA cardinality law: the compiled allocator shape is N = 8 (upstream
  # CMCA-108). More than 8 surviving candidates is a typed refusal
  # (BcinrCardinalityRefusal, CLI exit 1), never truncation -- and the bridge
  # must NOT silently substitute the uniform fallback for a real refusal.
  test "cardinality law: a 25-branch budget is refused, not truncated" do
    result = Dfcm.allocate_options(synthetic_problem(25))

    assert result.status == :refused
    assert elem(result.reason, 0) == :cmca_allocate_failed

    # The captured CLI failure carries the lab's typed refusal as evidence.
    assert {:cli_failed, 1, output} = elem(result.reason, 1)
    assert output =~ "BcinrCardinalityRefusal"

    assert result.allocations == []
    assert result.authority_ceiling == :select
  end

  test "allocation parity on the same benchmark budget: cmca vs uniform shares" do
    # Pinned to vendored bcinr commit 2ae60cf0: observed plan gives C
    # (entropy 10, salience 10) a strictly larger share than A/B (entropy 8,
    # salience 8), while the old uniform fallback gave every survivor 1/3.
    result = Dfcm.allocate_options(Dfcm.benchmark())
    by_id = Map.new(result["allocations"], &{&1["branch_id"], &1["allocated_fraction"]})

    assert by_id["C"] > by_id["A"]
    assert by_id["C"] > by_id["B"]
    assert_in_delta by_id["A"], by_id["B"], 1.0e-9

    uniform_share = 1.0 / 3
    assert_in_delta sum_fractions(result["allocations"]), uniform_share * 3, @q16_16_epsilon
  end

  test "absent-CLI fallback: uniform option-preserving shares stay green" do
    Application.put_env(:beam4pm, :autofde_cli_path, "/nonexistent/autofde-p7-absent")
    refute Dfcm.autofde_cli_available?()

    on_exit(fn -> Application.delete_env(:beam4pm, :autofde_cli_path) end)

    result = Dfcm.allocate_options(Dfcm.benchmark())

    assert result["allocator"] == "uniform_fallback"
    assert result.authority_ceiling == :select
    assert length(result["allocations"]) == 3
    assert Enum.all?(result["allocations"], &(&1["standing"] == "ADMITTED"))

    assert Enum.all?(
             result["allocations"],
             &(&1["allocated_fraction"] == 1.0 / 3)
           )

    assert_in_delta sum_fractions(result["allocations"]), 1.0, 1.0e-12
  end
end
