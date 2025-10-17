defmodule GitFoil.Helpers.FileEncryption do
  @moduledoc """
  Shared helper for encrypting files with progress display.

  Used by init, encrypt, and rekey commands to avoid code duplication.
  """

  alias GitFoil.Infrastructure.Terminal

  @doc """
  Add files to Git with progress bar, triggering encryption via clean filter.

  ## Parameters

  - `files` - List of file paths to encrypt
  - `total` - Total number of files (for progress calculation)
  - `opts` - Optional keyword list with:
    - `:repository` - Git adapter module (for testing), defaults to direct System.cmd
    - `:terminal` - Terminal adapter module (for testing), defaults to Terminal

  ## Returns

  - `:ok` on success
  - `{:error, message}` on failure
  """
  def add_files_with_progress(files, total, opts \\ []) do
    repository = Keyword.get(opts, :repository)
    terminal = Keyword.get(opts, :terminal, Terminal)

    # Initial progress display
    IO.write("   ")

    files
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {file, index}, _acc ->
      # Show progress before the operation
      # \r moves cursor to start of line, \e[K clears from cursor to end of line
      progress_bar = terminal.progress_bar(index, total)
      IO.write("\r\e[K   #{progress_bar} #{index}/#{total} files")

      # Add the file (triggers clean filter for encryption)
      result = if repository do
        # Use injected repository adapter (for testing)
        repository.add_file(file)
      else
        # Direct git call
        case System.cmd("git", ["add", file], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {error, _} -> {:error, String.trim(error)}
        end
      end

      case result do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          IO.write("\n")
          {:halt, {:error, "Failed to encrypt #{file}: #{reason}"}}
      end
    end)
    |> case do
      :ok ->
        IO.write("\n")
        IO.puts("✅  All files encrypted and staged successfully")
        IO.puts("")
        :ok

      error ->
        error
    end
  end
end
