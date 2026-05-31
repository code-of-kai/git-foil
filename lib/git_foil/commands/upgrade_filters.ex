defmodule GitFoil.Commands.UpgradeFilters do
  @moduledoc """
  Non-interactive upgrade of an existing repository's git filter config.

  Adds `filter.gitfoil.process` (and re-affirms clean/smudge/required) to a
  repository that was initialised by an older GitFoil. This is the bulk-,
  script-friendly path for migrating already-encrypted repos onto the
  long-running filter process without re-running the full interactive `init`.

  Idempotent: writing the same config twice is a no-op for git. It does NOT
  touch the encryption key, patterns, or any file content — purely transport
  configuration, so it never rewrites history or churns the working tree.
  """

  alias GitFoil.Infrastructure.{FilterConfig, Git}

  @doc """
  Writes the GitFoil filter config into the current repository.

  Refuses to run if the repo has no GitFoil key (nothing to upgrade), to avoid
  configuring a `required` filter that would then fail every checkout.
  """
  @spec run(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(opts \\ []) do
    repository = Keyword.get(opts, :repository, Git)

    with {:ok, _root} <- repository.verify_repository(),
         :ok <- ensure_initialized() do
      entries = FilterConfig.entries()

      results = Enum.map(entries, fn {key, value} -> repository.set_config(key, value) end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, success_message()}
        {:error, reason} -> {:error, "Failed to write git config: #{inspect(reason)}"}
      end
    end
  end

  defp ensure_initialized do
    if File.exists?(".git/git_foil/master.key") or
         File.exists?(".git/git_foil/master.key.enc") do
      :ok
    else
      {:error,
       "No GitFoil key found in this repository. Run 'git-foil init' first " <>
         "(upgrade-filters only adds the filter.gitfoil.process key to a repo " <>
         "that is already initialized)."}
    end
  end

  defp success_message do
    """
    ✅  Configured filter.gitfoil.process (plus clean/smudge fallback) for this repository.

       git >= 2.11 will now use the single long-running filter process.
       Ciphertext is unchanged, so 'git status' should report nothing modified.

    ⚠️   Rollback note: if you ever downgrade git-foil to a build that predates
        the process protocol, first run in this repo:

           git config --unset filter.gitfoil.process

        (otherwise git will keep invoking a filter-process the old binary
        cannot speak). See scripts/gitfoil-rollback.sh to do this across many repos.
    """
  end
end
