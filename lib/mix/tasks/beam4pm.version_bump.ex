# Hand-authored mix task (manufacturing-tooling script, not ggen/ggen_igniter
# generated domain source -- analogous to scripts/*.sh). Implements story
# B4PM-1703: version-bump automation via Igniter.Project.MixProject.update/4,
# using the inspect/1-wrapped `{:code, inspect(new_version)}` workaround for
# defect #2 documented in docs/jira/v26.8.31/03-known-defects-and-mitigations.md
# (the library's own documented `{:code, new_version}` example calls
# `Sourceror.parse_string!/1` on the bare version string, which is not valid
# Elixir source for a two-dot semver like "0.1.0" or "26.8.28" -- inspect/1
# turns it into a valid string literal first).
defmodule Mix.Tasks.Beam4pm.VersionBump do
  @shortdoc "Bumps mix.exs's version: and src/beam4pm.app.src's {vsn, ...} together"

  @moduledoc """
  Bumps beam4pm's version in both `mix.exs` (the `version:` key in
  `project/0`) and `src/beam4pm.app.src` (the `{vsn, ...}` tuple) in the same
  invocation, keeping the two hand-authored version declarations in sync.

  ## Usage

      mix beam4pm.version_bump 0.1.1

  ## Refusal

  Refuses (raises `Mix.Tasks.Beam4pm.VersionBump.VersionMismatchError`,
  not a silent no-op) when `mix.exs`'s `version:` and `beam4pm.app.src`'s
  `{vsn, ...}` do not already match before the bump is applied -- a
  precondition that the two files have drifted apart and must be repaired
  by hand before this task can safely proceed.

  ## Implementation note (defect #2 workaround)

  The patch to `mix.exs` uses `Igniter.Project.MixProject.update/4` with
  `{:ok, {:code, inspect(new_version)}}`, never the base library's own
  documented `{:ok, {:code, new_version}}` example -- see
  `test/beam4pm_version_bump_test.exs` for a regression test proving the
  un-wrapped form reproduces the documented `Sourceror.parse_string!/1`
  crash against this exact fixture.
  """

  use Igniter.Mix.Task

  alias Igniter.Project.MixProject

  defmodule VersionMismatchError do
    defexception [:mix_exs_version, :app_src_version]

    @impl true
    def message(%__MODULE__{mix_exs_version: mv, app_src_version: av}) do
      "refusing to bump version: mix.exs's version: (#{inspect(mv)}) and " <>
        "src/beam4pm.app.src's {vsn, ...} (#{inspect(av)}) do not already " <>
        "match -- repair the drift by hand before running mix beam4pm.version_bump"
    end
  end

  @app_src_path "src/beam4pm.app.src"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :beam4pm,
      example: "mix beam4pm.version_bump 0.1.1",
      positional: [:new_version],
      schema: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    new_version = igniter.args.positional[:new_version]

    igniter
    |> refuse_unless_versions_match!(new_version)
    |> bump_mix_exs(new_version)
    |> bump_app_src(new_version)
  end

  # --- precondition: refuse (typed exception) if the two files disagree
  # about the current version before the bump is applied. ---
  defp refuse_unless_versions_match!(igniter, _new_version) do
    mix_exs_version = current_mix_exs_version!(igniter)
    app_src_version = current_app_src_version!(igniter)

    if mix_exs_version != app_src_version do
      raise VersionMismatchError,
        mix_exs_version: mix_exs_version,
        app_src_version: app_src_version
    end

    igniter
  end

  defp current_mix_exs_version!(igniter) do
    "mix.exs"
    |> mix_exs_content!(igniter)
    |> then(fn content ->
      case Regex.run(~r/version:\s*"([^"]*)"/, content) do
        [_, version] -> version
        nil -> raise "could not locate mix.exs's project/0 version: key"
      end
    end)
  end

  # Reads mix.exs's real current content -- from the in-progress %Igniter{}'s
  # rewrite state if it has already been touched this run (Chicago-correct
  # against Igniter.Test's in-memory %Igniter{} fixtures used by the
  # regression test), falling back to the real file on disk otherwise.
  defp mix_exs_content!(path, igniter) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
    else
      File.read!(path)
    end
  end

  defp current_app_src_version!(igniter) do
    @app_src_path
    |> mix_exs_content!(igniter)
    |> extract_vsn!()
  end

  defp extract_vsn!(source) do
    case Regex.run(~r/\{vsn,\s*"([^"]*)"\}/, source) do
      [_, vsn] -> vsn
      nil -> raise "could not locate {vsn, \"...\"} in #{@app_src_path}"
    end
  end

  # --- mix.exs: Igniter.Project.MixProject.update/4, inspect/1-wrapped
  # per the defect #2 workaround. ---
  defp bump_mix_exs(igniter, new_version) do
    MixProject.update(igniter, :project, [:version], fn _zipper ->
      {:ok, {:code, inspect(new_version)}}
    end)
  end

  # --- src/beam4pm.app.src: plain Erlang source, no Igniter/Sourceror AST
  # support for .app.src -- a targeted string replace of the {vsn, "..."}
  # tuple, verified afterward by reading the real file content back
  # (see acceptance bullet 1). ---
  defp bump_app_src(igniter, new_version) do
    Igniter.update_file(igniter, @app_src_path, fn source ->
      content = Rewrite.Source.get(source, :content)
      current_vsn = extract_vsn!(content)

      updated =
        String.replace(
          content,
          ~s({vsn, "#{current_vsn}"}),
          ~s({vsn, "#{new_version}"}),
          global: false
        )

      Rewrite.Source.update(source, :content, updated)
    end)
  end
end
