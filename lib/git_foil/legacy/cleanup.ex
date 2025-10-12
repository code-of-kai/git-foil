defmodule GitFoil.Legacy.Cleanup do
  @moduledoc """
  Cleans up legacy GitFoil (formerly GitVeil) configuration that can interfere
  with current development workflows.

  Historically the project used the `gitveil` clean/smudge filters and the
  `/usr/local/bin/git-veil` wrapper. Repositories that still reference those
  entries will fail when Git attempts to run the missing binary. These helpers
  make sure stale settings are removed or neutralised.
  """

  require Logger

  @legacy_filter "gitveil"

  @doc """
  Removes known legacy configuration artifacts from the current repository.
  """
  @spec run() :: :ok
  def run do
    cleanup_git_filter()
    cleanup_gitattributes()
    :ok
  end

  @doc """
  Removes the legacy gitveil filter section from the local git config, if it exists.
  """
  @spec cleanup_git_filter() :: :ok
  def cleanup_git_filter do
    case exec_git(["config", "--local", "--remove-section", filter_section()]) do
      {:ok, _} ->
        Logger.debug("Removed legacy GitVeil filter configuration")

      {:error, {:not_found, _}} ->
        :ok

      {:error, {:not_git_repo, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to remove legacy GitVeil filter configuration: #{inspect(reason)}")
    end
  end

  @doc """
  Strips GitVeil filter entries from the repository's .gitattributes file.
  """
  @spec cleanup_gitattributes() :: :ok
  def cleanup_gitattributes do
    path = ".gitattributes"

    if File.exists?(path) do
      case File.read(path) do
        {:ok, contents} ->
          cleaned_lines =
            contents
            |> String.split("\n")
            |> Enum.reject(&legacy_attribute?/1)

          cleaned_content = Enum.join(cleaned_lines, "\n")

          if cleaned_content != contents do
            :ok = File.write(path, cleaned_content)
            Logger.debug("Removed legacy GitVeil entries from .gitattributes")
          end

        {:error, reason} ->
          Logger.warning(
            "Unable to read .gitattributes during legacy cleanup: #{inspect(reason)}"
          )
      end
    end

    :ok
  end

  defp exec_git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, :removed}

      {message, 128} ->
        lowered = String.downcase(message)

        cond do
          String.contains?(lowered, "no such section") ->
            {:error, {:not_found, message}}

          String.contains?(lowered, "not in a git directory") ->
            {:error, {:not_git_repo, message}}

          true ->
            {:error, {:unknown, 128, message}}
        end

      {message, exit_code} ->
        {:error, {:unknown, exit_code, message}}
    end
  end

  defp legacy_attribute?(line) do
    String.contains?(line, "filter=#{@legacy_filter}")
  end

  defp filter_section do
    "filter.#{@legacy_filter}"
  end
end
