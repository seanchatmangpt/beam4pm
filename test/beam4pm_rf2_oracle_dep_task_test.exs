defmodule Beam4pmRf2OracleDepTaskTest do
  @moduledoc """
  Chicago-style: exercises `Mix.Tasks.Beam4pm.Rf2OracleDep`'s real
  `Igniter.Project.Deps.add_dep` codemod against two real `%Igniter{}`
  states (`Igniter.Test.test_project/1`, an in-memory igniter, not a mock)
  -- one shaped like beam4pm's real `mix.exs` (separate `defp deps do
  [...] end`), one shaped like the inline-`deps:` fixture the
  `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` defect #1 audit
  names. Every assertion is on the real resulting igniter/source state
  (`assert_has_patch`, real `Rewrite.Source.get(:content)`, real
  `assert_raise`), never on "was this function called."
  """

  use ExUnit.Case, async: true

  @beam4pm_shape_mix_exs """
  defmodule Beam4pm.MixProject do
    use Mix.Project

    def project do
      [
        app: :beam4pm,
        version: "0.1.0",
        elixir: "~> 1.17",
        start_permanent: Mix.env() == :prod,
        deps: deps()
      ]
    end

    def application do
      [
        extra_applications: [:logger]
      ]
    end

    defp deps do
      [
        {:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime: false},
        {:ash, "~> 3.0"},
        {:ash_ai, "~> 0.8"},
        {:wasmex, "~> 0.15"}
      ]
    end
  end
  """

  # Inline-`deps:` shape, per `~/ex4pm/apps/ex4pm_contracts/mix.exs`'s real
  # convention (cited in defect #1's audit) -- `deps: [...]` declared
  # directly in `project/0` instead of via a separate `defp deps do`
  # function, which triggers `Igniter.Project.Deps.get_dep/2`'s bare-`nil`
  # fallback (`deps.ex:261-262`) and `add_dependency/4`'s uncaught
  # `CaseClauseError` (`deps.ex:60`).
  @inline_deps_mix_exs """
  defmodule Ex4pmContracts.MixProject do
    use Mix.Project

    def project do
      [
        app: :ex4pm_contracts,
        version: "0.1.0",
        elixir: "~> 1.17",
        deps: [
          {:jason, "~> 1.4"}
        ]
      ]
    end

    def application do
      [
        extra_applications: [:logger]
      ]
    end
  end
  """

  describe "precondition: real beam4pm mix.exs uses the non-inlined defp deps do [...] end shape" do
    test "the actual ~/beam4pm mix.exs on disk declares a separate defp deps do function" do
      real_mix_exs = File.read!(Path.join(File.cwd!(), "mix.exs"))

      assert real_mix_exs =~ ~r/defp deps do\s*\n\s*\[/
      refute real_mix_exs =~ ~r/def project do\s*\[\s*\n(?:.*\n)*?\s*deps:\s*\[/
    end
  end

  describe "Mix.Tasks.Beam4pm.Rf2OracleDep against the real beam4pm-shaped mix.exs (defect #1 does not trigger)" do
    test "add_dep adds the RF2_ORACLE_BIN-adjacent dependency to the defp deps do [...] end block" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => @beam4pm_shape_mix_exs})

      igniter =
        Igniter.Project.Deps.add_dep(igniter, {:rustler, "~> 0.35"}, error?: false)

      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)

      assert source =~ ~s({:rustler, "~> 0.35"})
      # the pre-existing separate-function convention survives untouched
      assert source =~ "defp deps do"
      assert source =~ ~s({:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime: false})
    end

    test "an accompanying version pin uses the inspect/1-wrapped MixProject.update pattern (B4PM-1703)" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => @beam4pm_shape_mix_exs})

      igniter =
        Igniter.Project.MixProject.update(igniter, :project, [:version], fn _zipper ->
          {:ok, {:code, inspect("0.1.1")}}
        end)

      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)

      assert source =~ ~s(version: "0.1.1",)
      refute source =~ ~s(version: "0.1.0",)
    end
  end

  describe "regression: defect #1 reproduces against an inline-deps: fixture mix.exs" do
    test "the same Igniter.Project.Deps.add_dep call raises CaseClauseError against inline deps: [...]" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => @inline_deps_mix_exs})

      assert_raise CaseClauseError, ~r/no case clause matching:\s*nil/, fn ->
        Igniter.Project.Deps.add_dep(igniter, {:rustler, "~> 0.35"}, error?: false)
      end
    end
  end
end
