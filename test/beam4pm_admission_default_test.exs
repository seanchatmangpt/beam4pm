# Hand-authored qualification (not ggen-generated) -- see
# bap:hand_authored_test_admission_default in ontology.ttl.
defmodule BeamPM.AdmissionDefaultTest do
  @moduledoc """
  Chicago-style qualification of the fail-closed admission default
  (`config :beam4pm, :admission_mode`), the supervised graphlaw/ferroplan
  engines, the wasm sha256 pin and the `capabilities` ABI handshake, against
  the REAL graphlaw and ferroplan wasm modules. No mocks: the mode is switched
  with `Application.put_env` (documented configuration, restored in on_exit),
  the engine is stopped/killed through its real supervisor, and the wasm copy
  with a flipped byte is a real file.
  """

  use ExUnit.Case, async: false

  alias BeamPM.{DeviationAdmission, Ferroplan, Graphlaw, GraphlawAdmission, ReplanRouter}

  if not (BeamPM.Graphlaw.wasm_built?() and BeamPM.Ferroplan.wasm_built?()) do
    @moduletag skip: "graphlaw and ferroplan wasm artifacts are required"
  end

  @moduletag timeout: 120_000

  @at "urn:p:at"
  @link "urn:p:link"
  defp at(r), do: {"urn:r:#{r}", @at, "urn:p:true"}
  defp link(a, b), do: {"urn:r:#{a}", @link, "urn:r:#{b}"}

  defp model do
    %{"GO" => fn [a, b] -> %{pre: [at(a), link(a, b)], add: [at(b)], del: [at(a)]} end}
  end

  @domain """
  (define (domain rooms)
    (:requirements :strips :typing)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b))
      :effect (and (at ?b) (not (at ?a)))))
  """

  @problem """
  (define (problem three-room)
    (:domain rooms)
    (:objects a b c - room)
    (:init (at a) (link a b) (link b c))
    (:goal (at c)))
  """

  @retry_loop JSON.encode!(%{
                "states" => [%{"id" => "s0"}, %{"id" => "g", "facts" => ["done"]}],
                "initial_states" => ["s0"],
                "goal" => %{"facts" => ["done"]},
                "transitions" => [
                  %{"action" => "flip", "from" => "s0", "to" => "g", "probability_ppm" => 500_000},
                  %{"action" => "flip", "from" => "s0", "to" => "s0", "probability_ppm" => 500_000}
                ]
              })

  @deviant %{conforms: false, deviations: [["clean_house", ">>"]]}

  defp set_mode(mode) do
    prior = Application.fetch_env(:beam4pm, :admission_mode)
    Application.put_env(:beam4pm, :admission_mode, mode)

    on_exit(fn ->
      case prior do
        {:ok, v} -> Application.put_env(:beam4pm, :admission_mode, v)
        :error -> Application.delete_env(:beam4pm, :admission_mode)
      end
    end)
  end

  defp stop_graphlaw_engine do
    :ok = Supervisor.terminate_child(BeamPM.EngineSupervisor, BeamPM.Graphlaw.Engine)

    on_exit(fn ->
      case Supervisor.restart_child(BeamPM.EngineSupervisor, BeamPM.Graphlaw.Engine) do
        {:ok, _} -> :ok
        {:error, :running} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end)
  end

  defp wait_for_engine(old_pid, deadline_ms) do
    Enum.reduce_while(1..div(deadline_ms, 20), nil, fn _, _ ->
      case Process.whereis(BeamPM.Graphlaw.Engine) do
        pid when is_pid(pid) and pid != old_pid -> {:halt, pid}
        _ -> Process.sleep(20) && {:cont, nil}
      end
    end)
  end

  describe "mode/0" do
    test "default (no config) is :required; only :skip disables; garbage fails closed" do
      set_mode(:required)
      Application.delete_env(:beam4pm, :admission_mode)
      assert GraphlawAdmission.mode() == :required
      Application.put_env(:beam4pm, :admission_mode, :skip)
      assert GraphlawAdmission.mode() == :skip
      Application.put_env(:beam4pm, :admission_mode, :banana)
      assert GraphlawAdmission.mode() == :required
    end

    test "config/config.exs declares :required as the shipped default" do
      src = File.read!("config/config.exs")
      assert src =~ "config :beam4pm, :admission_mode, :required"
    end
  end

  describe "ReplanRouter.execute(:session_replan) default admission" do
    setup do
      {:ok, _} = Ferroplan.start()
      {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
      on_exit(fn -> Ferroplan.session_free(handle) end)
      %{handle: handle}
    end

    test "required: no :admission spec is refused; skip: same call is ok", %{handle: handle} do
      set_mode(:required)

      assert {:error, {:admission_missing, reason}} =
               ReplanRouter.execute(:session_replan, handle, %{})

      assert is_binary(reason)

      Application.put_env(:beam4pm, :admission_mode, :skip)
      assert {:ok, %{outcome: :solved}} = ReplanRouter.execute(:session_replan, handle, %{})
    end

    test "required: explicit admission: :skip opts out", %{handle: handle} do
      set_mode(:required)

      assert {:ok, %{outcome: :solved}} =
               ReplanRouter.execute(:session_replan, handle, %{admission: :skip})
    end

    test "required: a violated-world spec is refused, a true world admitted", %{handle: handle} do
      set_mode(:required)
      bad = %{state: [at("A"), link("A", "B")], model: model(), goal: [at("C")]}

      assert {:error, {:plan_refused, _}} =
               ReplanRouter.execute(:session_replan, handle, %{admission: bad})

      good = %{state: [at("A"), link("A", "B"), link("B", "C")], model: model(), goal: [at("C")]}
      assert {:ok, %{admission: %{receipts: [_ | _]}}} =
               ReplanRouter.execute(:session_replan, handle, %{admission: good})
    end

    test "required: engine down is admission_unavailable, not ok", %{handle: handle} do
      set_mode(:required)
      stop_graphlaw_engine()
      good = %{state: [at("A"), link("A", "B"), link("B", "C")], model: model(), goal: [at("C")]}

      assert {:error, {:admission_unavailable, {:wasmex, {:engine_not_started, _}}}} =
               ReplanRouter.execute(:session_replan, handle, %{admission: good})
    end
  end

  describe "ReplanRouter.load_policy/4 default court" do
    @preimage %{subject: "s", pack: "p", policy: "q", world: "w"}

    setup do
      {:ok, _} = Ferroplan.start()
      {:ok, synthesized} = Ferroplan.fond_policy("", @retry_loop)
      pre = %{@preimage | policy: ReplanRouter.policy_digest(synthesized)}
      %{st0: ReplanRouter.new(plan_id: "rooms-1", preimage: pre, run_id: "fond")}
    end

    test "required: the real policy is admitted by the court with no option", %{st0: st0} do
      set_mode(:required)
      assert {:ok, st} = ReplanRouter.load_policy(st0, @retry_loop)
      assert [%{"state" => "s0", "action" => "flip"}] = st.universal_plan["policy"]
    end

    test "required: court unreachable fails closed; graphlaw_court: false opts out", %{st0: st0} do
      set_mode(:required)
      stop_graphlaw_engine()

      assert {:error, {:admission_unavailable, {:wasmex, {:engine_not_started, _}}}} =
               ReplanRouter.load_policy(st0, @retry_loop)

      assert {:ok, _} = ReplanRouter.load_policy(st0, @retry_loop, nil, graphlaw_court: false)
    end

    test "skip: no court, engine down is irrelevant", %{st0: st0} do
      set_mode(:skip)
      stop_graphlaw_engine()
      assert {:ok, _} = ReplanRouter.load_policy(st0, @retry_loop)
    end
  end

  describe "DeviationAdmission default SHACL gate" do
    setup do
      path = Path.join(System.tmp_dir!(), "dev_default_#{System.unique_integer([:positive])}.ttl")
      File.write!(path, "@prefix bpm: <https://ggen.dev/ontology/beam-process-model#> .\n")
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "required: malformed deviation refused, file byte-identical, no option passed", %{path: path} do
      set_mode(:required)
      before = File.read!(path)

      assert {:error, {:deviation_refused, _}} =
               DeviationAdmission.admit_deviation(@deviant, "ref-1", "", path)

      assert File.read!(path) == before
    end

    test "required: well-formed admitted; graphlaw_gate: false appends the malformed one", %{path: path} do
      set_mode(:required)
      assert {:ok, name} = DeviationAdmission.admit_deviation(@deviant, "ref-1", "cand-1", path)
      assert File.read!(path) =~ name

      assert {:ok, name2} =
               DeviationAdmission.admit_deviation(@deviant, "ref-1", "", path, graphlaw_gate: false)

      assert File.read!(path) =~ name2
    end

    test "required: engine down refuses admission_unavailable, file byte-identical", %{path: path} do
      set_mode(:required)
      stop_graphlaw_engine()
      before = File.read!(path)

      assert {:error, {:admission_unavailable, _}} =
               DeviationAdmission.admit_deviation(@deviant, "ref-1", "cand-1", path)

      assert File.read!(path) == before
    end
  end

  describe "supervised engines" do
    test "both engines run under BeamPM.EngineSupervisor as permanent children" do
      children = Supervisor.which_children(BeamPM.EngineSupervisor)
      ids = Enum.map(children, &elem(&1, 0))
      assert BeamPM.Graphlaw.Engine in ids
      assert BeamPM.Ferroplan.Engine in ids
      assert is_pid(Process.whereis(BeamPM.Graphlaw.Engine))
    end

    test "killing the graphlaw engine: the next admission call succeeds within 2s, no manual start" do
      old = Process.whereis(BeamPM.Graphlaw.Engine)
      assert is_pid(old)
      Process.exit(old, :kill)

      new = wait_for_engine(old, 2_000)
      assert is_pid(new) and new != old

      assert {:ok, %{"receipts" => [_]}} =
               GraphlawAdmission.admit_plan(
                 [at("A"), link("A", "B")],
                 [%{name: "go A B", pre: [at("A"), link("A", "B")], add: [at("B")], del: [at("A")]}],
                 [at("B")]
               )
    end
  end

  describe "wasm pin, ABI handshake and readiness" do
    test "verify_artifact/0 accepts the installed wasm" do
      assert GraphlawAdmission.verify_artifact() == :ok
    end

    test "verify_artifact/1 refuses a one-byte-flipped copy" do
      bytes = File.read!(Graphlaw.wasm_path())
      mid = div(byte_size(bytes), 2)
      <<head::binary-size(mid), b, tail::binary>> = bytes
      copy = Path.join(System.tmp_dir!(), "gl_flipped_#{System.unique_integer([:positive])}.wasm")
      File.write!(copy, <<head::binary, Bitwise.bxor(b, 1), tail::binary>>)
      on_exit(fn -> File.rm(copy) end)

      assert {:error, {:pin_mismatch, %{expected: e, actual: a}}} =
               GraphlawAdmission.verify_artifact(copy)

      assert e != a
    end

    test "verify_artifact/2 refuses a missing pin and a missing artifact" do
      assert {:error, {:pin_missing, _}} =
               GraphlawAdmission.verify_artifact(Graphlaw.wasm_path(), "/nonexistent/pin.sha256")

      assert {:error, {:artifact_missing, _}} = GraphlawAdmission.verify_artifact("/nonexistent/x.wasm")
    end

    test "the real engine answers capabilities with the documented abi_version" do
      assert {:ok, %{"abi_version" => v}} = Graphlaw.capabilities()
      assert v == GraphlawAdmission.expected_abi_version()
      assert GraphlawAdmission.handshake() == :ok
    end

    test "ready?/0 is true when running, false when the engine is not running, no side effects" do
      assert GraphlawAdmission.ready?()
      stop_graphlaw_engine()
      refute GraphlawAdmission.ready?()
      assert Process.whereis(BeamPM.Graphlaw.Engine) == nil
    end

    test "engine_children/0 lists both engines when artifacts exist and the pin verifies" do
      ids = GraphlawAdmission.engine_children() |> Enum.map(& &1.id)
      assert ids == [BeamPM.Graphlaw.Engine, BeamPM.Ferroplan.Engine]
    end
  end
end
