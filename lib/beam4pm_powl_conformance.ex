defmodule BeamPM.PowlConformance do
  @moduledoc """
  Closes the "discover a reference model from real OCEL traces, then check a
  new real trace for conformance against it" loop, combining Step 4's
  `BeamPM.Rust4PM.ocel_discover_powl/2` (real object-centric POWL discovery
  via flattening) with the already-real alignment ops
  (`discover_alphappp/1`, `align_trace/2`, `compute_fitness/2`).

  Disclosed, real limitation (not a fake shortcut): the rust4pm engine has no
  POWL -> Petri-net conversion op, so `align_trace`/`compute_fitness` cannot
  run directly against a `discover_powl`/`ocel_discover_powl` result. This
  module therefore does two real things over the SAME real flattened
  reference variant traces (`ocel_variants_of_object_type`, itself the exact
  flattening `ocel_discover_powl` uses internally):

    1. `ocel_discover_powl/2` -- the real, human-readable reference POWL
       model (informational / disclosed reference, per the task).
    2. `discover_alphappp/1` over a real XES log built from those same
       flattened variant traces -- a real, independently-discovered,
       alignment-capable Petri net over the identical reference behavior,
       used for the actual `align_trace`/`compute_fitness` conformance
       check, since only Petri nets are alignable in this engine.

  Not ggen-generated: hand-written orchestration over already-real engine
  ops (same convention as `BeamPM.PowlDiscovery`/`BeamPM.Ocel`).
  """

  alias BeamPM.Rust4PM

  # Alpha+++'s own Rust `Default` config (`balance_thresh: 0.2,
  # fitness_thresh: 0.75, replay_thresh: 0.0,
  # log_repair_skip_df_thresh_rel: 2.0, log_repair_loop_df_thresh_rel: 2.0,
  # absolute_df_clean_thresh: 10, relative_df_clean_thresh: 0.1` --
  # native/rust4pm-wasm's vendored process_mining crate, full.rs), with only
  # `absolute_df_clean_thresh` lowered from 10 to 1. That field cleans a
  # directly-follows edge as "noise" below its absolute observed count; the
  # default of 10 is tuned for real-world log volumes and, observed
  # directly while developing this module, silently cleans away every real
  # edge in a handful-of-traces reference log, producing a degenerate
  # 0-place net that trivially aligns ANY trace at cost 0. The engine's
  # `discover_alphappp` op requires every field when `config` is non-nil
  # (no partial-override merge), so the other 6 fields are restated here
  # verbatim from the crate's own `Default`, not invented.
  @small_log_alphappp_config %{
    "balance_thresh" => 0.2,
    "fitness_thresh" => 0.75,
    "replay_thresh" => 0.0,
    "log_repair_skip_df_thresh_rel" => 2.0,
    "log_repair_loop_df_thresh_rel" => 2.0,
    "absolute_df_clean_thresh" => 1,
    "relative_df_clean_thresh" => 0.1
  }

  @typedoc "Result of checking one candidate trace against a reference OCEL log's discovered behavior."
  @type conformance_result :: %{
          reference_powl: map(),
          num_reference_traces: non_neg_integer(),
          net_summary: map(),
          alignment: map(),
          fitness: map(),
          deviations: [[String.t()]],
          conforms: boolean()
        }

  @doc """
  Discovers a reference model from `reference_ocel_handle`'s real
  `object_type` traces, then checks `test_trace_activities` (a plain list of
  activity-name strings -- e.g. a flattened OCEL trace for one object)
  against it. Returns real fitness + the real list of deviating alignment
  moves (log-only or model-only steps), never a boolean.
  """
  @spec check_conformance(non_neg_integer(), String.t(), [String.t()]) ::
          {:ok, conformance_result()} | {:error, term()}
  def check_conformance(reference_ocel_handle, object_type, test_trace_activities)
      when is_integer(reference_ocel_handle) and is_binary(object_type) and
             is_list(test_trace_activities) do
    with {:ok, %{"powl" => reference_powl, "num_traces" => num_ref_traces}} <-
           Rust4PM.ocel_discover_powl(reference_ocel_handle, object_type),
         {:ok, %{"variants" => variants}} <-
           Rust4PM.ocel_variants_of_object_type(reference_ocel_handle, object_type),
         xes <- variants_to_xes(variants),
         {:ok, %{"handle" => ref_log_handle}} <- Rust4PM.import_xes(xes),
         # Alpha+++'s default `absolute_df_clean_thresh` (10) is tuned for
         # real-world log volumes; a small in-test/in-process reference log
         # (a handful of traces) would have every directly-follows edge
         # cleaned away as "noise" under that default, producing a
         # degenerate 0-place net that trivially aligns any trace at cost 0
         # -- observed directly while developing this module. `thresh: 1`
         # (never filter a df edge actually observed) is the honest choice
         # for a reference log this small; a production caller with a
         # larger reference population should pass its own `config`.
         {:ok, %{"net_handle" => net_handle, "summary" => net_summary}} <-
           Rust4PM.discover_alphappp(ref_log_handle, @small_log_alphappp_config),
         {:ok, %{"moves" => moves, "cost" => cost, "states_visited" => states_visited}} <-
           Rust4PM.align_trace(net_handle, test_trace_activities),
         test_xes <- variants_to_xes([%{"activities" => test_trace_activities, "count" => 1}]),
         {:ok, %{"handle" => test_log_handle}} <- Rust4PM.import_xes(test_xes),
         {:ok, fitness} <- Rust4PM.compute_fitness(test_log_handle, net_handle) do
      deviations =
        Enum.filter(moves, fn [log_side, model_side] ->
          log_side == ">>" or model_side == ">>"
        end)

      _ = Rust4PM.free_log(ref_log_handle)
      _ = Rust4PM.free_log(test_log_handle)
      _ = Rust4PM.free_net(net_handle)

      {:ok,
       %{
         reference_powl: reference_powl,
         num_reference_traces: num_ref_traces,
         net_summary: net_summary,
         alignment: %{"moves" => moves, "cost" => cost, "states_visited" => states_visited},
         fitness: fitness,
         deviations: deviations,
         conforms: cost == 0
       }}
    end
  end

  # Builds a real, minimal, valid XES 1.0 log from rust4pm's own
  # `{"activities" => [...], "count" => n}` variant shape (one XES <trace>
  # per real replicate, so discover_alphappp/compute_fitness see the real
  # observed frequencies, not a deduplicated variant list).
  @spec variants_to_xes([map()]) :: String.t()
  defp variants_to_xes(variants) do
    traces =
      variants
      |> Enum.flat_map(fn %{"activities" => activities} = v ->
        List.duplicate(activities, Map.get(v, "count", 1))
      end)
      |> Enum.with_index()

    trace_xml =
      Enum.map_join(traces, "\n", fn {activities, case_idx} ->
        events =
          Enum.map_join(activities, "\n", fn activity ->
            ~s(<event><string key="concept:name" value="#{xml_escape(activity)}"/></event>)
          end)

        """
        <trace>
        <string key="concept:name" value="case-#{case_idx}"/>
        #{events}
        </trace>
        """
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <log xes.version="1.0" xes.features="nested-attributes" openxes.version="1.0RC7">
    <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>
    <classifier name="Activity" keys="concept:name"/>
    #{trace_xml}
    </log>
    """
  end

  defp xml_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
