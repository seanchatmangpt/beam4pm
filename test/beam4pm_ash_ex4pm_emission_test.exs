defmodule BeamPM.AshEx4pmEmissionTest do
  @moduledoc """
  Adoption-seam qualification for the v26.10.1 ash_ex4pm upgrade
  (docs/jira/v26.10.1/RESOLUTIONS.md R3-AMENDED, R14).

  Two layers, one per lawful state of the Ash projection:

    1. ALWAYS-ON (runs today): identity + law-side wiring guards.
       The dependency identities are pinned exactly (mix.lock: ash_ex4pm
       26.10.1 pinning ex4pm 26.10.1 -- CalVer's third component carries
       contract changes), and the ggen pack facts that OWN the resource
       wiring are present: the beam4pm_ash_resource template renders
       `extensions: [AshEx4pm]` + the create-only `ex4pm` block
       (vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/
       templates/beam4pm_ash_resource.ex.eex), the pack ontology carries
       the `bpm:ocelTypeExpr` scalar ladder, and ash_fields.rq projects
       `?ocel_type_expr` (unbound = rendered skip comment, never silent).

    2. LIVE EMISSION (dormant until the projection is wired): the tests
       below run against BeamPM.Ash.Resources.* while none of them carries
       compiled AshEx4pm state; each ASSERTS the dormant state itself, so
       the day the Ash-leg regeneration lands these assertions fail and
       force this file onto its live bodies.

  WHY LAYER 2 IS DORMANT -- the standing seam this file guards: the Ash-leg
  projection (lib/beam4pm_ash/resources/, 647 rendered files) is FROZEN at
  HEAD by a pre-existing reconciliation deadlock, surfaced 2026-10-01
  during this upgrade: the admitted root ontology graph yields 677
  bpm:RecordType rows (30 aloop_* records admitted after the last
  successful sync) while the projection + .ggen_igniter manifest hold 647,
  and ggen_igniter 26.9.15's ReconcileReactor runs a terminal
  `mix compile --warnings-as-errors` after EVERY actuation and rolls the
  actuation back on failure -- so neither order (resources-then-domain nor
  domain-then-resources) can pass its intermediate verify on record
  growth. Evidence: /tmp/w1_regen_main.log, /tmp/regen-coord.log. The fix
  (growth-aware reconciliation in ggen_igniter, or an atomic multi-recipe
  script step) is upstream of this repo. When it lands and
  scripts/igniter_sync.sh re-renders, layer 2's dormant assertions fail
  loudly and the live bodies below take over.

  async: false: `Ex4pm.Evidence.Store` is a named GenServer singleton
  (deps/ex4pm/lib/ex4pm/evidence.ex:78-105) shared by the whole VM.
  """

  use ExUnit.Case, async: false

  @agent_id "ash_ex4pm"
  @pack_dir "vendor/ggen-marketplace/packs/beam4pm-process-model-pack"
  @resource_template Path.join(@pack_dir, "igniter/templates/beam4pm_ash_resource.ex.eex")
  @pack_ontology Path.join(@pack_dir, "ontology.ttl")
  @ash_fields_query Path.join(@pack_dir, "igniter/queries/ash_fields.rq")

  # -- layer 1: identity + law-side wiring (always on) -----------------------

  # Real cleanup: the creates below land real rows in the resource's shared
  # ETS table; leaving them would leak into BeamPM.Ash.ResourcesGeneratedTest's
  # read-all round-trip (same VM, same table). Mirrors the roundtrip suite's
  # own Ash.DataLayer.Ets.stop/1 reset.
  setup do
    on_exit(fn ->
      # Also the OcelEvent resource: the R3 read-silence leg creates one.
      Enum.each(
        [BeamPM.Ash.Resources.BrceActuationRequest, BeamPM.Ash.Resources.OcelEvent],
        &:erlang.apply(Ash.DataLayer.Ets, :stop, [&1])
      )
      :ok
    end)
    :ok
  end

  @tag :ash_ex4pm_emission
  test "dependency identities are pinned exactly at 26.10.1" do
    assert to_string(Application.spec(:ash_ex4pm, :vsn)) == "26.10.1"
    assert to_string(Application.spec(:ex4pm, :vsn)) == "26.10.1"
  end

  @tag :ash_ex4pm_emission
  test "the pack template renders the AshEx4pm wiring (law side)" do
    template = File.read!(@resource_template)

    # Render-line anchor (adversarial-probe fix): the template's own
    # COMMENT names the extension too, so a whole-file =~ passes even with
    # the render line deleted. The finder skips comment lines and must
    # bind the actual render line.
    render_line =
      template
      |> String.split("\n")
      |> Enum.find(fn line ->
        String.contains?(line, "extensions: [AshEx4pm]") and
          not String.starts_with?(String.trim_leading(line), "#")
      end)

    refute is_nil(render_line),
           "the resource template must RENDER extensions: [AshEx4pm] " <>
             "(comment-line mentions do not count)"

    # ~S: the template's own EEx/Elixir interpolation must match literally.
    assert template =~ ~S(activity :#{this_name}_created, on: :create),
           "the resource template must render the create-only activity"

    # Non-scalar attributes are skipped with a NAMED comment at render
    # time, never silently dropped (RESOLUTIONS.md R3).
    assert template =~ "skipped field",
           "the resource template must name skipped (non-scalar) fields"

    # R2: the RENDERED use-block line carries no `notifiers:` entry --
    # AshEx4pm.Transformers.Persist auto-registers the notifier, and the
    # template's own explanatory COMMENT legitimately names the literal,
    # so the refute targets the render line, not the whole file.
    refute String.contains?(render_line, "notifiers"),
           "R2: the rendered use block must not carry an explicit notifiers entry"
  end

  @tag :ash_ex4pm_emission
  test "the pack ontology carries the bpm:ocelTypeExpr scalar ladder" do
    ontology = File.read!(@pack_ontology)

    assert ontology =~ "bpm:ocelTypeExpr"

    # The scalar field types exist as individuals AND carry the mapping.
    for scalar <- ~w(string integer float boolean datetime atom) do
      assert ontology =~ "bpm:FieldType_#{scalar} a bpm:FieldType",
             "expected a FieldType individual for #{scalar}"

      assert ontology =~ "bpm:ocelTypeExpr \":#{scalar}\"",
             "expected #{scalar} to carry its bpm:ocelTypeExpr mapping"
    end

    # The query projects the ladder as a WEAK optional: an unbound
    # ocel_type_expr renders the skip comment rather than refusing.
    # Structural match, not the word -- prose alone must not satisfy
    # this (adversarial-probe fix).
    query = File.read!(@ash_fields_query)
    assert query =~ "ocel_type_expr"

    assert query =~ "OPTIONAL { ?ft bpm:ocelTypeExpr ?ocel_type_expr . }",
           "the ladder must join through a WEAK optional triple pattern"
  end

  @tag :ash_ex4pm_emission
  test "ex4pm's evidence store is alive under beam4pm's boot (R6 division)" do
    # config :ex4pm, wasm_host: false disables ex4pm's OWN wasm hosts only;
    # the store -- the sink for AshEx4pm.Notifier emission -- must be up.
    assert match?(pid when is_pid(pid), Process.whereis(Ex4pm.Evidence.Store))
  end

  # -- layer 2: live emission (dormant until the projection is wired) --------

  defp wired? do
    AshEx4pm.Info.compiled?(BeamPM.Ash.Resources.OcelEvent)
  rescue
    _ -> false
  end

  # While the Ash-leg projection is frozen (R14), every live test asserts
  # the dormant state itself: when the regeneration lands, these fail and
  # force this file onto the live bodies below.
  defp assert_dormant!(test_label) do
    refute wired?(),
           "#{test_label}: expected the Ash-leg projection to still be frozen per R14 -- " <>
             "the regeneration has landed, update this suite to its live bodies"
  end

  @tag :ash_ex4pm_emission
  test "introspection: ocel_event is compiled with the R3 create activity" do
    if wired?() do
      resource = BeamPM.Ash.Resources.OcelEvent

      assert AshEx4pm.Info.compiled?(resource),
             "expected #{inspect(resource)} to carry compiled AshEx4pm state"

      activities = AshEx4pm.Info.activities(resource)
      assert is_list(activities) and activities != []

      activity = Enum.find(activities, &(&1.name == :ocel_event_created))

      refute is_nil(activity), "expected :ocel_event_created in #{inspect(activities)}"
      assert activity.on == :create
      assert activity.object_type == :ocel_event

      compiled = AshEx4pm.Info.compiled(resource)
      assert compiled[:object_types][:ocel_event]
    else
      assert_dormant!("introspection")
    end
  end

  @tag :ash_ex4pm_emission
  test "a real create on an all-scalar resource ingests an envelope into the evidence store" do
    if wired?() do
      resource = BeamPM.Ash.Resources.BrceActuationRequest

      assert AshEx4pm.Info.compiled?(resource)

      activity = resource |> AshEx4pm.Info.activities() |> Enum.find(&(&1.on == :create))
      refute is_nil(activity)

      unique = System.unique_integer([:positive])

      attrs = %{
        tenant_id: "emit-test-tenant-#{unique}",
        request_id: "emit-test-request-#{unique}",
        authority_hash: "emit-test-authority-#{unique}"
      }

      before = store_snapshot()
      t0 = nanos()

      record = Ash.create!(Ash.Changeset.for_create(resource, :create, attrs))

      t1 = nanos()
      after_set = store_snapshot()
      assert map_size(after_set) > map_size(before)

      [outcome | _] = new_emit_receipts = new_emit_receipts(before, t0, t1)
      assert length(new_emit_receipts) >= 1

      assert outcome.phase == :outcome
      assert outcome.standing == :alive
      assert outcome.operation == {:ingest, :batch}
      assert outcome.metadata[:agent_id] == @agent_id

      assert Ex4pm.Evidence.Store.get_by_subject(outcome.subject_hash)
             |> Enum.any?(&(&1.hash == outcome.hash))

      envelope =
        AshEx4pm.Notifier.build_envelope(activity, build_notification(resource, record))

      assert envelope["schema"] == "ash_ex4pm/1"
      assert [%{"activity" => "brce_actuation_request_created"}] = envelope["events"]

      assert {:ok, object} = Map.fetch(envelope["objects"], record_id(record))
      assert object["type"] == "brce_actuation_request"
      assert object["attributes"]["tenant_id"] == attrs.tenant_id
    else
      assert_dormant!("create-emits")
    end
  end

  @tag :ash_ex4pm_emission
  test "a read does not emit (create-only per R3)" do
    if wired?() do
      resource = BeamPM.Ash.Resources.BrceActuationRequest
      unique = System.unique_integer([:positive])

      Ash.create!(resource, %{
        tenant_id: "read-silent-tenant-#{unique}",
        request_id: "read-silent-request-#{unique}",
        authority_hash: "read-silent-authority-#{unique}"
      })

      before = store_snapshot()
      t0 = nanos()

      assert Ash.read!(resource) != []

      t1 = nanos()

      assert new_emit_receipts_any_phase(before, t0, t1) == [],
             "a :read must not ingest any envelope -- no compiled activity declares on: :read"
    else
      assert_dormant!("read-silent")
    end
  end

  @tag :ash_ex4pm_emission
  test "a resource with a non-scalar attribute still emits, map attribute skipped" do
    if wired?() do
      resource = BeamPM.Ash.Resources.OcelEvent

      assert AshEx4pm.Info.compiled?(resource)

      activity = resource |> AshEx4pm.Info.activities() |> Enum.find(&(&1.on == :create))
      refute is_nil(activity)

      compiled_object_type = AshEx4pm.Info.compiled(resource)[:object_types][:ocel_event]
      assert compiled_object_type

      declared_names = Keyword.keys(compiled_object_type.attributes)
      refute :attributes in declared_names, ":map attribute must be skipped, not declared"

      unique = System.unique_integer([:positive])

      attrs = %{
        event_id: "emit-test-event-#{unique}",
        event_type: "emit-test-activity-#{unique}",
        event_time: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        attributes: %{"map-typed" => "payload that must never reach the envelope"}
      }

      before = store_snapshot()
      t0 = nanos()

      record = Ash.create!(resource, attrs)

      t1 = nanos()

      [outcome | _] = new_emit_receipts(before, t0, t1)
      assert outcome.metadata[:agent_id] == @agent_id

      envelope =
        AshEx4pm.Notifier.build_envelope(activity, build_notification(resource, record))

      assert [%{"activity" => "ocel_event_created"}] = envelope["events"]

      assert {:ok, object} = Map.fetch(envelope["objects"], record_id(record))
      assert object["type"] == "ocel_event"
      object_attrs = object["attributes"] || %{}

      refute Map.has_key?(object_attrs, "attributes"),
             "the :map attribute must never appear in the emitted object attributes"

      emitted_names = MapSet.new(Map.keys(object_attrs))
      declared_string_names = MapSet.new(declared_names, &to_string/1)
      assert MapSet.subset?(emitted_names, declared_string_names)
    else
      assert_dormant!("map-skip")
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp store_snapshot do
    Ex4pm.Evidence.Store.all() |> Map.new(&{&1.hash, &1})
  end

  defp new_emit_receipts(before, t0, t1) do
    Ex4pm.Evidence.Store.all()
    |> Enum.reject(&Map.has_key?(before, &1.hash))
    |> Enum.filter(fn r ->
      r.phase == :outcome and r.standing == :alive and
        r.operation == {:ingest, :batch} and
        is_map(r.metadata) and r.metadata[:agent_id] == @agent_id and
        is_integer(r.metadata[:sequence]) and r.metadata[:sequence] in t0..t1
    end)
  end

  defp new_emit_receipts_any_phase(before, t0, t1) do
    Ex4pm.Evidence.Store.all()
    |> Enum.reject(&Map.has_key?(before, &1.hash))
    |> Enum.filter(fn r ->
      r.operation == {:ingest, :batch} and
        is_map(r.metadata) and r.metadata[:agent_id] == @agent_id and
        is_integer(r.metadata[:sequence]) and r.metadata[:sequence] in t0..t1
    end)
  end

  defp nanos, do: System.os_time(:nanosecond)

  defp build_notification(resource, record) do
    changeset = Ash.Changeset.for_create(resource, :create, %{})

    %Ash.Notifier.Notification{
      resource: resource,
      action: Ash.Resource.Info.action(resource, :create),
      data: record,
      changeset: changeset
    }
  end

  defp record_id(record), do: to_string(record.id)
end
