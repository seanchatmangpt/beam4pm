defmodule Beam4pm.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam4pm,
      version: "0.1.0",
      elixir: "~> 1.14",
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

  defp deps do
    []
  end
end
