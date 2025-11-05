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
    {password_env, cleanup_password_env} = build_password_env(opts)

    show_progress? = total > 0

    if show_progress? do
      IO.write("   ")
    end

    result =
      files
      |> Enum.with_index(1)
      |> Enum.reduce_while(:ok, fn {file, index}, _acc ->
        if show_progress? do
          progress_bar = terminal.progress_bar(index, total)
          IO.write("\r\e[K   #{progress_bar} #{index}/#{total} files")
        end

        # Add the file (triggers clean filter for encryption)
        result =
          if repository do
            repository.add_file(file)
          else
            case System.cmd("git", ["add", file], env: password_env, stderr_to_stdout: true) do
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

    cleanup_password_env.()

    case result do
      :ok ->
        if show_progress? do
          IO.write("\n")
        end

        IO.puts("✅  All files encrypted and staged successfully")
        IO.puts("")
        :ok

      error ->
        if show_progress? do
          IO.write("\n")
        end

        error
    end
  end

  defp build_password_env(opts) do
    case Keyword.get(opts, :password_value) do
      password when is_binary(password) ->
        path = Path.join(System.tmp_dir!(), "gitfoil-pass-" <> random_suffix())

        File.write!(path, password <> "\n" <> password <> "\n")

        case File.chmod(path, 0o600) do
          :ok -> :ok
          {:error, _} -> :ok
        end

        previous = System.get_env("GIT_FOIL_TTY")
        System.put_env("GIT_FOIL_TTY", path)

        env = [{"GIT_FOIL_TTY", path}]

        cleanup = fn ->
          case previous do
            nil -> System.delete_env("GIT_FOIL_TTY")
            value -> System.put_env("GIT_FOIL_TTY", value)
          end

          File.rm_rf(path)
        end
        {env, cleanup}

      _ ->
        {[], fn -> :ok end}
    end
  end

  defp random_suffix do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
