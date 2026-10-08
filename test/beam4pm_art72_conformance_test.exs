defmodule BeamPM.Art72ConformanceTest do
  @moduledoc """
  Lane W511: EU AI Act Art. 72 post-market monitoring (dissertation
  Definition 7.2) token-replay fitness + typed drift decision.

  Synthetic sequential Petri net `start -> t_a -> t_b -> t_c -> end`
  (one token each arc, initial {start:1}, final {end:1}). Every expected
  C value below is hand-derived from

      C = 1/2 (1 - m/c) + 1/2 (1 - r/p)

  under the replay convention documented in `BeamPM.Art72Conformance`.
  """
  use ExUnit.Case, async: true

  alias BeamPM.Art72Conformance

  # Sequential net: start --t_a--> p1 --t_b--> p2 --t_c--> end
  @net Art72Conformance.net(
         %{
           "t_a" => %{input: %{"start" => 1}, output: %{"p1" => 1}},
           "t_b" => %{input: %{"p1" => 1}, output: %{"p2" => 1}},
           "t_c" => %{input: %{"p2" => 1}, output: %{"end" => 1}}
         },
         %{"start" => 1},
         %{"end" => 1}
       )

  describe "replay_trace/2 token sums" do
    test "perfectly-fitting trace: m=0, r=0" do
      stats = Art72Conformance.replay_trace(@net, ["t_a", "t_b", "t_c"])
      assert stats == %{consumed: 3, produced: 3, missing: 0, remaining: 0}
    end

    test "skipped final transition ([t_a, t_b]): m=1 (end deficit), r=1 (p2 excess)" do
      stats = Art72Conformance.replay_trace(@net, ["t_a", "t_b"])
      assert stats == %{consumed: 3, produced: 3, missing: 1, remaining: 1}
    end

    test "underfed transition ([t_a, t_c]): missing charged mid-replay + p1 excess" do
      stats = Art72Conformance.replay_trace(@net, ["t_a", "t_c"])
      assert stats == %{consumed: 2, produced: 3, missing: 1, remaining: 1}
    end
  end

  describe "Definition 7.2 fitness" do
    test "perfect log => C = 1.0" do
      {c, _stats} = Art72Conformance.log_fitness(@net, [["t_a", "t_b", "t_c"]])
      assert c == 1.0
    end

    test "trace skipping t_c => C = 2/3 (exact formula value)" do
      # c=3, m=1 => 1 - 1/3 ; p=3, r=1 => 1 - 1/3 ; C = 2/3
      {c, _stats} = Art72Conformance.log_fitness(@net, [["t_a", "t_b"]])
      # formula-computed float: 1 - 1/3 (bit-exact form of 2/3 under IEEE)
      assert c == 1 - 1 / 3
      assert_in_delta c, 2 / 3, 1.0e-12
    end

    test "underfed trace [t_a, t_c] => C = 7/12" do
      # term1 = 1 - 1/2 ; term2 = 1 - 1/3 ; C = 7/12
      {c, _stats} = Art72Conformance.log_fitness(@net, [["t_a", "t_c"]])
      assert c == 7 / 12
    end

    test "mixed log (perfect + skipping) => C = 5/6 (token-sum aggregation)" do
      # c=6, m=1 ; p=6, r=1 => C = 5/6
      {c, stats} = Art72Conformance.log_fitness(@net, [["t_a", "t_b", "t_c"], ["t_a", "t_b"]])
      assert c == 5 / 6
      assert stats == %{consumed: 6, produced: 6, missing: 1, remaining: 1}
    end

    test "empty log => C = 1.0 by convention" do
      {c, _stats} = Art72Conformance.log_fitness(@net, [])
      assert c == 1.0
    end
  end

  describe "drift_decision/2 (pure typed decision)" do
    test "C below 1 - epsilon => :DRIFT" do
      assert Art72Conformance.drift_decision(5 / 6, 0.1) == :DRIFT
      assert Art72Conformance.drift_decision(2 / 3, 0.1) == :DRIFT
    end

    test "C at or above threshold => :NO_DRIFT" do
      assert Art72Conformance.drift_decision(1.0, 0.1) == :NO_DRIFT
      # exact boundary is not drifted (strict <)
      assert Art72Conformance.drift_decision(0.9, 0.1) == :NO_DRIFT
    end
  end
end
