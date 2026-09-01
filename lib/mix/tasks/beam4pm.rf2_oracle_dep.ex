defmodule Mix.Tasks.Beam4pm.Rf2OracleDep do
  @moduledoc """
  Adds the RF2_ORACLE_BIN-adjacent Rust NIF/port dependency to `mix.exs`
  programmatically, via `Igniter.Project.Deps.add_dep`.

  This is the deferred `MixProject.update`/`Deps.add_dep` path identified by
  the `scripts/rf2_conformance_sync.sh` audit (B4PM-1709): today that script
  runs two full-file `mix ggen_igniter.sync` EEx regenerations of
  `lib/beam4pm_rf2_conformance.ex` and its test, driven by `rf2_spec.rq`
  against `ontology.ttl`; it does not, and per the audit's own "Do not
  adopt... for this script's actual two ggen_igniter.sync steps" finding,
  should not, call any `Igniter.Project.*` codemod itself. This task is the
  additive, separately-invoked automation the audit named as the one
  plausible future fit: programmatic `mix.exs` dependency management for the
  Rust NIF/port that would back `RF2_ORACLE_BIN` if that oracle is ever
  wired in-process instead of shelled out to
  `native/rf2-conformance-oracle`'s release binary.

  ## Precondition this task depends on (defect #1, `docs/jira/v26.8.31/03-known-defects-and-mitigations.md`)

  `Igniter.Project.Deps.add_dep/2,3` crashes with an uncaught
  `CaseClauseError` (`deps.ex:60`'s `case` has no clause for the bare `nil`
  that `get_dep/2`'s `with...else` fallback, `deps.ex:261-262`, returns) when
  the target `mix.exs` inlines `deps: [...]` directly in `project/0` instead
  of declaring a separate `defp deps do [...] end` function. `~/beam4pm/mix.exs`
  as of this story declares the separate-function convention:

  ```elixir
  defp deps do
    [
      {:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime: false},
      {:ash, "~> 3.0"},
      {:ash_ai, "~> 0.8"},
      {:wasmex, "~> 0.15"}
    ]
  end
  ```

  -- so this task's `add_dep` call does not trigger defect #1 against the
  real project file. Re-verify this shape (`grep -n "defp deps do" mix.exs`)
  before relying on this task again: a hand-edit that inlines `deps:` back
  into `project/0` is a legitimate manufacturing-input edit per this repo's
  source-authority doctrine and would silently reintroduce the crash.

  ## Version pin (defect #2, B4PM-1703 pattern)

  If `--pin-version` is given, this task also patches `mix.exs`'s top-level
  `version:` key via `Igniter.Project.MixProject.update/4`, using the
  verified `{:code, inspect(new_version)}` form (never the library's own
  undocumented-breaking `{:code, new_version}` bare-string example) -- the
  same `inspect/1`-wrapped workaround B4PM-1703 established for beam4pm's
  real two-dot semver strings.

  ## Usage

      mix beam4pm.rf2_oracle_dep
      mix beam4pm.rf2_oracle_dep --dep rustler --version "~> 0.35"
      mix beam4pm.rf2_oracle_dep --pin-version 0.1.1
  """

  use Igniter.Mix.Task

  @shortdoc "Adds the RF2_ORACLE_BIN-adjacent dep to mix.exs via Igniter.Project.Deps.add_dep"

  @default_dep_name :rustler
  @default_dep_version "~> 0.35"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      schema: [
        dep: :string,
        version: :string,
        pin_version: :string
      ],
      defaults: [
        dep: to_string(@default_dep_name),
        version: @default_dep_version
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    dep_name = igniter.args.options[:dep] |> to_string() |> String.to_atom()
    dep_version = igniter.args.options[:version]

    igniter =
      Igniter.Project.Deps.add_dep(igniter, {dep_name, dep_version}, error?: false)

    case igniter.args.options[:pin_version] do
      nil ->
        igniter

      pin ->
        Igniter.Project.MixProject.update(igniter, :project, [:version], fn _zipper ->
          {:ok, {:code, inspect(pin)}}
        end)
    end
  end
end
