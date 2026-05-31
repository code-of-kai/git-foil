defmodule GitFoil.Infrastructure.FilterConfig do
  @moduledoc """
  Single source of truth for the `filter.gitfoil.*` git config GitFoil writes.

  Centralised so that every code path that configures a repository — fresh
  `init`, re-`init` on an existing repo, and the standalone `upgrade-filters`
  command — writes the *same* set of keys. The historical bug class this
  prevents: one path learning about `filter.gitfoil.process` while another
  keeps writing only clean/smudge, leaving repos half-migrated.
  """

  @doc """
  The git config entries GitFoil writes, as `{key, value}` tuples.

  Both transports are configured deliberately when running as the installed
  escript:

    * `filter.gitfoil.process` — git >= 2.11 prefers this single long-running
      process (no per-file BEAM boot, no concurrent-dlopen race).
    * `filter.gitfoil.clean` / `.smudge` — the per-file fallback. Older git
      ignores the unknown `.process` key and uses these; an un-reconfigured
      repo also keeps working. This is the *old-git* compatibility net.

  Note the value for `.process` carries no `%f`: the long-running protocol
  supplies the pathname out-of-band via the `pathname=` packet.

  **Source/dev mode (`mix run`) omits `.process`.** The long-running protocol
  uses stdout as the pkt-line wire, which must be pristine; a `mix run` shim
  emits startup/compiler chatter on stdout and cannot serve as a filter
  process. Dev mode therefore stays on clean/smudge. `.process` is added only
  for the installed escript, whose stdout is clean.
  """
  @spec entries() :: [{String.t(), String.t()}]
  def entries do
    executable_path = executable_path()

    base = [
      {"filter.gitfoil.clean", "#{executable_path} clean %f"},
      {"filter.gitfoil.smudge", "#{executable_path} smudge %f"},
      {"filter.gitfoil.required", "true"}
    ]

    if process_supported?() do
      [{"filter.gitfoil.process", "#{executable_path} filter-process"} | base]
    else
      base
    end
  end

  @doc """
  Whether the long-running filter process is usable in the current execution
  mode. False under `mix run` (source/dev), true for the installed escript.
  """
  @spec process_supported?() :: boolean()
  def process_supported? do
    not running_from_source?(Path.expand("../../..", __DIR__))
  end

  @doc """
  Resolves the path to the git-foil executable that git should invoke.

  When running from source (mix dev/test) we shell out via `mix run`; when
  running as the installed escript we use the real executable path so git can
  invoke it directly.
  """
  @spec executable_path() :: String.t()
  def executable_path do
    project_root = Path.expand("../../..", __DIR__)

    cond do
      running_from_source?(project_root) ->
        "cd '#{project_root}' && mix run -e 'GitFoil.CLI.main(System.argv())' --"

      exec_path = current_exec_path() ->
        exec_path

      executable = System.find_executable("git-foil") ->
        executable

      executable = System.find_executable("git-foil-dev") ->
        executable

      true ->
        "git-foil"
    end
  end

  defp running_from_source?(project_root) do
    case {maybe_mix_env(), File.exists?(Path.join(project_root, "mix.exs"))} do
      {{:ok, env}, true} when env in [:dev, :test] -> true
      _ -> false
    end
  end

  defp maybe_mix_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      {:ok, Mix.env()}
    else
      :error
    end
  end

  defp current_exec_path do
    case System.fetch_env("_") do
      {:ok, path} when path not in ["", "mix"] -> path
      _ -> nil
    end
  end
end
