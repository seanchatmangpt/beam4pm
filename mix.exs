defmodule Beam4pm.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam4pm,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: ["generated/elixir/test"],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # generated/elixir/lib and generated/elixir/test are ggen-manufactured
  # output (see generated/README.md). Including generated/elixir/test only
  # in the :test elixirc_paths is the standard Mix mechanism for `mix test`
  # to pick up test-support modules that live outside the conventional
  # top-level test/ directory.
  defp elixirc_paths(:test), do: ["generated/elixir/lib", "generated/elixir/test"]
  defp elixirc_paths(_), do: ["generated/elixir/lib"]

  # :ggen_igniter is a manufacturing-time tool only (`mix ggen_igniter.sync`,
  # see scripts/igniter_sync.sh) -- never a runtime dependency of generated
  # code. Compiling it requires a working Rust/cargo toolchain (its default
  # oxigraph query engine is a Rustler NIF). :ash IS a real runtime
  # dependency of the manufactured generated/elixir/lib/beam4pm_ash.ex.
  defp deps do
    [
      {:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime: false},
      {:ash, "~> 3.0"}
    ]
  end
end
