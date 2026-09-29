defmodule BeamPM.GraphlawParityTest do
  @moduledoc """
  GraphLaw cross-hash + verdict parity flip ledger (v26.9.18 b4p-p10).

  The GraphLaw "triangle" resolves as a DUO plus an engine pin:

    (a) corner 1 -- lab CLI direct: `<lab>/.venv/bin/python3 -m autofde_lab.cli
        sa2a graphlaw ...` invoked from this test via System.cmd (no trampoline);

    (b) corner 2 -- beam4pm seam: `BeamPM.Dfcm.graphlaw_hash/1,
        graphlaw_validate/2, graphlaw_hooks/2` shelling out through the
        hand-authored `priv/bin/autofde` bash trampoline (which execs the SAME
        lab CLI in the SAME venv);

    (c) corner 3 -- there is NO in-repo beam4pm graphlaw engine (grep of lib/
        for graphlaw/praxis at 36b0ed9 finds none). The engine actually lives
        upstream in the praxis repo as the content-addressed WASM artifact
        `crates/praxis-graphlaw-wasm/pkg/praxis_graphlaw_wasm_bg.wasm`, which
        autofde-lab's `sa2a/admission/graphlaw_bridge.py` loads under a pinned
        SHA-256/size/import-set discipline. Corner 3 is pinned here by the
        artifact's identity (see `@praxis_wasm_sha256`), so a praxis rebuild
        trips this file the same way a verdict/digest flip does.

  Pins recorded (BLAKE3 graph hashes + verdicts + stage codes) are the
  f5-06-style flip ledger for GraphLaw: any praxis-graphlaw-wasm rebuild,
  lab bridge change, or beam4pm trampoline drift trips these assertions.
  Re-derive or escalate per b4p-f5-06 disposition rules; empty flip rows are
  forbidden, "no flip" is a row.

  Environment: requires `~/autofde-lab` with `.venv` (family contract, same as
  `BeamPM.DfcmTest`). In worktrees where `../autofde-lab` is not a sibling of
  the checkout, set `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab` (the trampoline
  and this test use the same resolution rule). Run with `mix test --no-start`
  if the app's Bandit port is held by another checkout.

  Known transport ceiling (observed 2026-09-18, both corners): the lab CLI
  decides "content vs file path" via `Path(ttl).exists()`. Inline content
  whose slash-delimited longest run exceeds NAME_MAX (255) or whose total
  exceeds PATH_MAX (1024) makes that stat raise ENAMETOOLONG, which pathlib
  does not ignore, so the CLI crashes (exit 1) BEFORE reaching the engine;
  beyond ~1MiB total (macOS ARG_MAX), even the subprocess spawn refuses
  (E2BIG). Net effect: the bridge corner (always inline) can only carry TTL
  under ~1024 bytes, while the direct corner can pass a file path of any
  size. The repo-root `ontology.ttl` (~1.5MiB admitted graph) therefore has
  NO digest obtainable through either corner; this test pins that ceiling
  instead of a digest, and pins a deterministic bounded slice of the admitted
  graph for digest parity.
  """

  use ExUnit.Case, async: true

  alias BeamPM.Dfcm

  @fixture_dir Path.expand("fixtures/graphlaw_parity", __DIR__)
  @ontology_path Path.expand("../ontology.ttl", __DIR__)
  @praxis_wasm_path "/Users/sac/praxis/crates/praxis-graphlaw-wasm/pkg/praxis_graphlaw_wasm_bg.wasm"

  # --- Flip-ledger pins (observed 2026-09-18, corners 1 and 2 identical) ---

  @digest_pins %{
    "shacl_violation.ttl" => "6ee218170924e7e7d2f3ec50a471a329907a46ed6ca6be467effeb7a39499056",
    "shacl_conforms.ttl" => "9ff19b2a1e300cceb252ca51b75c1ee816657edb97bfab931be0e8758bc5dcf1",
    "n3_denial.ttl" => "c640e44ec580f156cfa000f6ccaec4a93b8892783273f2876b03ef22af1e9782",
    "hooks_base.ttl" => "78f5fb7a846c2a98cdeabc9d49604d4476ea314b8afe69e71471155c7d18976c",
    "hooks_event.ttl" => "280589c103300dd48373f290a845ed15fcdd49358ad170e6e744925fd167df26"
  }

  # Deterministic bounded slice of the admitted graph: the first bpm: @prefix
  # line plus the bpm:ocel_event_rt RecordType block (through its first " ."
  # terminator). Kept under the lab CLI's inline-content stat-heuristic limit
  # (~1024 bytes, see transport-ceiling note below). Verified graph-canonical:
  # a 21KB variant with duplicated prefix lines hashes to the SAME digest.
  @ontology_slice_digest "e8f9df49477b311447b75a7075c4eb30e115b8b10dbdfccb592ff4048cd7b046"

  # Third-corner identity: praxis-graphlaw-wasm artifact pin. Mirrors
  # autofde-lab sa2a/admission/graphlaw_bridge.py EXPECTED_ARTIFACT_SHA256 /
  # EXPECTED_ARTIFACT_SIZE (verified byte-for-byte via shasum 2026-09-18).
  @praxis_wasm_sha256 "187688d9e7e33a575713d6911d75687adb38713ed37412e211af263dfcbe0c28"
  @praxis_wasm_size 3_249_361

  setup_all do
    lab_root =
      System.get_env("AUTOFDE_LAB_ROOT") || Path.expand("../autofde-lab", File.cwd!())

    python = Path.join(lab_root, ".venv/bin/python3")
    env = [{"PYTHONPATH", Path.join(lab_root, "src")}]
    %{python: python, env: env}
  end

  # --- Corner 1 helpers: direct lab CLI, no trampoline ---

  defp direct_cli(python, env, args) do
    case System.cmd(python, ["-m", "autofde_lab.cli" | args], env: env, stderr_to_stdout: false) do
      {out, 0} -> {:ok, JSON.decode!(out)}
      {_err, code} -> {:error, {:cli_failed, code}}
    end
  rescue
    e in ErlangError -> {:error, {:exec_refused, e.reason}}
  end

  test "graphlaw hash: both corners agree and all corpus digests match the pins", %{
    python: python,
    env: env
  } do
    for {file, pin} <- @digest_pins do
      content = File.read!(Path.join(@fixture_dir, file))

      assert {:ok, via_bridge} = Dfcm.graphlaw_hash(content)
      assert {:ok, %{"graph_hash" => via_direct}} =
               direct_cli(python, env, ["sa2a", "graphlaw", "hash", "--ttl", content])

      assert via_bridge == via_direct,
             "#{file}: trampoline #{via_bridge} != direct #{via_direct}"

      assert via_bridge == pin,
             "FLIP: #{file} digest moved #{pin} -> #{via_bridge} (engine/seam bump; re-derive or escalate per b4p-f5-06)"
    end
  end

  test "admitted-graph slice: deterministic ontology slice hashes to its pin on both corners", %{
    python: python,
    env: env
  } do
    slice = ontology_slice()
    assert slice =~ "bpm:ocel_event_rt a bpm:RecordType ;"
    assert slice =~ "@prefix bpm:"

    assert {:ok, via_bridge} = Dfcm.graphlaw_hash(slice)

    assert {:ok, %{"graph_hash" => via_direct}} =
             direct_cli(python, env, ["sa2a", "graphlaw", "hash", "--ttl", slice])

    assert via_bridge == via_direct
    assert via_bridge == @ontology_slice_digest,
           "FLIP: admitted-graph slice digest moved (ontology.ttl edit or engine bump; re-derive the slice pin or escalate per b4p-f5-06)"
  end

  test "graphlaw validate --shacl: violation and control verdicts match on both corners and match pins",
       %{python: python, env: env} do
    shapes = File.read!(Path.join(@fixture_dir, "shacl_shapes.ttl"))

    expectations = %{
      # file => {conforms, shacl_status, shacl_detail, graph_hash_pin}
      "shacl_violation.ttl" =>
        {false, "REFUSED", "Report: 1 violations",
         @digest_pins["shacl_violation.ttl"]},
      "shacl_conforms.ttl" =>
        {true, "ADMITTED", "Report: 0 violations", @digest_pins["shacl_conforms.ttl"]}
    }

    for {file, {conforms, status, detail, hash_pin}} <- expectations do
      content = File.read!(Path.join(@fixture_dir, file))

      # NOTE: the lab CLI resolves file paths for --ttl/--event-ttl only;
      # --shacl accepts inline content only (both corners inline it).
      assert {:ok, via_bridge} = Dfcm.graphlaw_validate(content, shacl: shapes)

      assert {:ok, via_direct} =
               direct_cli(python, env, [
                 "sa2a",
                 "graphlaw",
                 "validate",
                 "--ttl",
                 content,
                 "--shacl",
                 shapes
               ])

      for res <- [via_bridge, via_direct] do
        assert res["conforms"] == conforms
        assert res["replay_status"] == "ADMITTED"
        shacl = Enum.find(res["dialects"], &(&1["dialect"] == "SHACL"))
        assert shacl["status"] == status
        assert shacl["detail"] == detail
        assert res["graph_hash"] == hash_pin
      end

      # Full structural parity between corners (stage codes included).
      assert drop_raw(via_bridge) == drop_raw(via_direct)
    end
  end

  test "graphlaw N3 denial: verdict and stage code match on both corners and match pin", %{
    python: python,
    env: env
  } do
    content = File.read!(Path.join(@fixture_dir, "n3_denial.ttl"))

    assert {:ok, via_bridge} = Dfcm.graphlaw_validate(content)
    assert {:ok, via_direct} = direct_cli(python, env, ["sa2a", "graphlaw", "validate", "--ttl", content])

    for res <- [via_bridge, via_direct] do
      refute res["conforms"]
      n3 = Enum.find(res["dialects"], &(&1["dialect"] == "N3_DENIAL"))
      assert n3["status"] == "REFUSED"
      assert n3["detail"] == "Found 1 denial violations"
      assert n3["triples_out"] == 1
      assert res["graph_hash"] == @digest_pins["n3_denial.ttl"]
    end

    assert drop_raw(via_bridge) == drop_raw(via_direct)
  end

  test "graphlaw hooks: transition verdict matches on both corners and matches pin", %{
    python: python,
    env: env
  } do
    base = File.read!(Path.join(@fixture_dir, "hooks_base.ttl"))
    event = File.read!(Path.join(@fixture_dir, "hooks_event.ttl"))

    assert {:ok, via_bridge} = Dfcm.graphlaw_hooks(base, event)

    assert {:ok, %{"result" => via_direct}} =
             direct_cli(python, env, [
               "sa2a",
               "graphlaw",
               "hooks",
               "--ttl",
               base,
               "--event-ttl",
               event
             ])

    # Full-result pin (AFDE-2612 upstream note: the WASM hook registry stays
    # empty -- verdicts/schedule/receipts [] with status ADMITTED is the
    # pinned honest verdict, not a wiring success claim).
    pinned = %{"status" => "ADMITTED", "verdicts" => [], "schedule" => [], "receipts" => []}

    assert via_bridge == pinned
    assert via_direct == pinned
  end

  test "third corner pin: praxis-graphlaw-wasm artifact identity is unchanged" do
    assert File.exists?(@praxis_wasm_path),
           "third-corner artifact missing at #{@praxis_wasm_path} -- family contract broken"

    bytes = File.read!(@praxis_wasm_path)
    assert byte_size(bytes) == @praxis_wasm_size

    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    assert digest == @praxis_wasm_sha256,
           "FLIP: praxis-graphlaw-wasm artifact rebuilt (#{digest}) -- lab pin and all digest pins above must be re-derived together"
  end

  test "transport ceiling: repo-root admitted ontology yields no digest through either corner",
       %{python: python, env: env} do
    ontology = File.read!(@ontology_path)
    assert byte_size(ontology) > 1_000_000, "premise: ontology.ttl exceeds inline-argv transport"

    # Corner 2 (bridge): refused before reaching the engine.
    refute match?({:ok, _}, Dfcm.graphlaw_hash(ontology))

    # Corner 1 (direct CLI): same refusal class at the same Node-spawn layer.
    refute match?({:ok, _}, direct_cli(python, env, ["sa2a", "graphlaw", "hash", "--ttl", ontology]))
  end

  # --- helpers ---

  defp drop_raw(%{"raw_response" => _} = res), do: Map.drop(res, ["raw_response"])
  defp drop_raw(res), do: res

  defp ontology_slice do
    lines = File.read!(@ontology_path) |> String.split("\n")

    # The admitted graph re-declares "@prefix bpm:" many times; the canonical
    # graph hash is insensitive to that, so the slice keeps one prefix line.
    prefix = Enum.find(lines, &String.starts_with?(&1, "@prefix bpm: "))

    {block_lines, rest} =
      lines
      |> Enum.drop_while(&(not String.starts_with?(&1, "bpm:ocel_event_rt a bpm:RecordType ;")))
      |> Enum.split_while(&(not String.ends_with?(&1, " .")))

    case rest do
      # trailing "" element -> Enum.join emits the final newline.
      [terminator | _] -> Enum.join([prefix, "" | block_lines] ++ [terminator, ""], "\n")
      [] -> Enum.join([prefix, "" | block_lines] ++ [""], "\n")
    end
  end
end
