defmodule GitFoil.CLI.PasswordPrompt do
  @moduledoc """
  Secure password input utilities for GitFoil CLI commands.

  Supports interactive masked prompts as well as non-interactive password
  sources (`--password-stdin`, `--password-file`, `--password-fd`).
  All inputs enforce leading/trailing whitespace validation.
  """

  @type password_source :: :tty | :stdin | {:file, Path.t()} | {:fd, non_neg_integer()}

  @whitespace_warning "⚠️  Leading/trailing spaces detected. Please re-enter."

  defmodule PromptError do
    @moduledoc false
    defstruct [:message, :exit_code, :reason]
  end

  alias __MODULE__.PromptError

  @doc """
  Prompts user for password or reads from a configured source.

  ## Options

    * `:confirm` - require confirmation (default: false)
    * `:min_length` - minimum length (default: 8)
    * `:allow_empty` - allow empty passwords (default: false)
    * `:source` - password source (`:tty`, `:stdin`, `{:file, path}`, `{:fd, fd}`)
    * `:no_confirm` - skip confirmation even when `:confirm` true (default: false)
    * `:confirm_prompt` - custom confirmation prompt (default: `"Confirm password: "`)
  """
  @spec get_password(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, PromptError.t()} | {:error, term()}
  def get_password(prompt, opts \\ []) do
    source = normalize_source(Keyword.get(opts, :source, :tty))
    confirm? = Keyword.get(opts, :confirm, false)
    allow_empty = Keyword.get(opts, :allow_empty, false)
    min_length = Keyword.get(opts, :min_length, 8)
    no_confirm = Keyword.get(opts, :no_confirm, false)
    confirm_prompt = Keyword.get(opts, :confirm_prompt, "Confirm password: ")
    confirm_required? = confirm? and not no_confirm

    case source do
      :tty ->
        read_new_password_interactive(prompt, confirm_prompt, confirm_required?, min_length, allow_empty)

      _ ->
        read_new_password_non_interactive(source, confirm_required?, min_length, allow_empty)
    end
  end

  @doc """
  Reads an existing password (used for unlock flows).

  Accepts same `:source` option as `get_password/2`. Confirmation and
  length checks are skipped but whitespace validation still applies.
  """
  @spec get_existing_password(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, PromptError.t()} | {:error, term()}
  def get_existing_password(prompt, opts \\ []) do
    source = normalize_source(Keyword.get(opts, :source, :tty))
    allow_empty = Keyword.get(opts, :allow_empty, true)

    case source do
      :tty ->
        read_existing_password_interactive(prompt, allow_empty)

      _ ->
        read_existing_password_non_interactive(source, allow_empty)
    end
  end

  @doc """
  Formats errors for user display.
  """
  @spec format_error(term()) :: String.t()
  def format_error(%PromptError{message: message}), do: message
  def format_error({exit_code, message}) when is_integer(exit_code) and is_binary(message), do: message
  def format_error(:password_mismatch), do: "Passwords do not match"
  def format_error(:password_empty), do: "Password cannot be empty"

  def format_error({:password_too_short, min_length}),
    do: "Password must be at least #{min_length} characters"

  def format_error(:eof), do: "Unexpected end of input"
  def format_error(other), do: "Password input failed: #{inspect(other)}"

  # ============================================================================
  # Interactive Input
  # ============================================================================

  defp read_new_password_interactive(prompt, confirm_prompt, confirm?, min_length, allow_empty) do
    case read_masked_input(prompt) do
      {:ok, raw} ->
        password = strip_trailing_newline(raw)

        cond do
          leading_or_trailing_whitespace?(password) ->
            IO.puts(:stderr, @whitespace_warning)
            read_new_password_interactive(prompt, confirm_prompt, confirm?, min_length, allow_empty)

          true ->
            case validate_password_length(password, min_length, allow_empty) do
              :ok ->
                handle_interactive_confirmation(prompt, confirm_prompt, confirm?, password, min_length, allow_empty)

              {:error, :password_empty} ->
                IO.puts(:stderr, "\nError: Password cannot be empty. Please try again.\n")
                read_new_password_interactive(prompt, confirm_prompt, confirm?, min_length, allow_empty)

              {:error, {:password_too_short, min}} ->
                IO.puts(:stderr, "\nError: Password must be at least #{min} characters. Please try again.\n")
                read_new_password_interactive(prompt, confirm_prompt, confirm?, min_length, allow_empty)
            end
        end

      {:error, :interrupted} ->
        handle_interrupted()

      {:error, reason} ->
        {:error, build_interactive_error(reason)}
    end
  end

  defp handle_interactive_confirmation(_prompt, _confirm_prompt, false, password, _min_length, _allow_empty),
    do: {:ok, password}

  defp handle_interactive_confirmation(prompt, confirm_prompt, true, password, min_length, allow_empty) do
    case read_masked_input(confirm_prompt) do
      {:ok, raw_confirm} ->
        confirm_password = strip_trailing_newline(raw_confirm)

        cond do
          leading_or_trailing_whitespace?(confirm_password) ->
            IO.puts(:stderr, @whitespace_warning)
            read_new_password_interactive(prompt, confirm_prompt, true, min_length, allow_empty)

          confirm_password != password ->
            IO.puts(:stderr, "\nError: Passwords do not match. Please try again.\n")
            read_new_password_interactive(prompt, confirm_prompt, true, min_length, allow_empty)

          true ->
            {:ok, password}
        end

      {:error, :interrupted} ->
        handle_interrupted()

      {:error, reason} ->
        {:error, build_interactive_error(reason)}
    end
  end

  defp read_existing_password_interactive(prompt, allow_empty) do
    case read_masked_input(prompt) do
      {:ok, raw} ->
        password = strip_trailing_newline(raw)

        cond do
          leading_or_trailing_whitespace?(password) ->
            IO.puts(:stderr, @whitespace_warning)
            read_existing_password_interactive(prompt, allow_empty)

          password == "" and not allow_empty ->
            IO.puts(:stderr, "\nError: Password cannot be empty. Please try again.\n")
            read_existing_password_interactive(prompt, allow_empty)

          true ->
            {:ok, password}
        end

      {:error, :interrupted} ->
        handle_interrupted()

      {:error, reason} ->
        {:error, build_interactive_error(reason)}
    end
  end

  # ============================================================================
  # Non-interactive Input
  # ============================================================================

  defp read_new_password_non_interactive(source, confirm?, min_length, allow_empty) do
    line_count = if confirm?, do: 2, else: 1

    case read_lines_from_source(source, line_count) do
      {:ok, [password_line | rest]} ->
        with {:ok, password} <-
               validate_non_interactive_value(password_line, source, :password, allow_empty, min_length),
             :ok <-
               maybe_validate_confirmation_non_interactive(
                 confirm?,
                 rest,
                 password,
                 source,
                 allow_empty,
                 min_length
               ) do
          {:ok, password}
        end

      {:error, {:eof, 1}} ->
        {:error, build_error(:missing_password, source)}

      {:error, {:eof, 2}} ->
        {:error, build_error(:missing_confirmation, source)}

      {:error, {:io_error, reason}} ->
        {:error, build_io_error(reason, source)}
    end
  end

  defp read_existing_password_non_interactive(source, allow_empty) do
    case read_lines_from_source(source, 1) do
      {:ok, [password_line]} ->
        validate_non_interactive_value(password_line, source, :password, allow_empty, 0)

      {:error, {:eof, _}} ->
        {:error, build_error(:missing_password, source)}

      {:error, {:io_error, reason}} ->
        {:error, build_io_error(reason, source)}
    end
  end

  defp maybe_validate_confirmation_non_interactive(false, _rest, _password, _source, _allow_empty, _min_length),
    do: :ok

  defp maybe_validate_confirmation_non_interactive(true, [confirm_line], password, source, allow_empty, min_length) do
    case validate_non_interactive_value(confirm_line, source, :confirmation, allow_empty, min_length) do
      {:ok, ^password} ->
        :ok

      {:ok, _other} ->
        {:error, build_error(:confirmation_mismatch, source)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_validate_confirmation_non_interactive(true, [], _password, source, _allow_empty, _min_length) do
    {:error, build_error(:missing_confirmation, source)}
  end

  defp validate_non_interactive_value(value, source, type, allow_empty, min_length) do
    if leading_or_trailing_whitespace?(value) do
      {:error, build_error({:whitespace, type}, source)}
    else
      case validate_password_length(value, min_length, allow_empty) do
        :ok ->
          {:ok, value}

        {:error, :password_empty} ->
          {:error, build_error({:empty, type}, source)}

        {:error, {:password_too_short, min}} ->
          {:error, build_error({:too_short, type, min}, source)}
      end
    end
  end

  # ============================================================================
  # I/O Helpers
  # ============================================================================

  defp read_lines_from_source(source, count) do
    with {:ok, reader} <- open_source(source) do
      result = do_read_lines(reader, count, [])
      close_source(reader)
      result
    end
  end

  defp do_read_lines(_reader, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp do_read_lines(reader, remaining, acc) do
    index = length(acc) + 1

    case read_line(reader) do
      {:ok, line} ->
        do_read_lines(reader, remaining - 1, [strip_trailing_newline(line) | acc])

      {:error, :eof} ->
        {:error, {:eof, index}}

      {:error, {:io_error, reason}} ->
        {:error, {:io_error, reason}}
    end
  end

  defp read_line({:stdin}) do
    case IO.binread(:stdio, :line) do
      :eof -> {:error, :eof}
      {:error, reason} -> {:error, {:io_error, reason}}
      data when is_binary(data) -> {:ok, data}
    end
  end

  defp read_line({:io_device, device}) do
    case IO.binread(device, :line) do
      :eof -> {:error, :eof}
      {:error, reason} -> {:error, {:io_error, reason}}
      data when is_binary(data) -> {:ok, data}
    end
  end

  defp open_source(:stdin), do: {:ok, {:stdin}}

  defp open_source({:file, path}) do
    case File.open(path, [:read, :binary]) do
      {:ok, device} -> {:ok, {:io_device, device}}
      {:error, reason} -> {:error, {:io_error, reason}}
    end
  end

  defp open_source({:fd, fd}) when is_integer(fd) and fd >= 0 do
    case :os.type() do
      {:unix, _} ->
        case fd_path(fd) do
          {:ok, path} ->
            open_source({:file, path})

          {:error, :not_found} ->
            {:error, {:io_error, :fd_not_available}}
        end

      _ ->
        {:error, {:io_error, :unsupported_fd}}
    end
  end

  defp close_source({:io_device, device}), do: File.close(device)
  defp close_source({:stdin}), do: :ok

  defp fd_path(fd) do
    paths =
      ["/proc/self/fd/#{fd}", "/dev/fd/#{fd}"]
      |> Enum.filter(&File.exists?/1)

    case paths do
      [path | _] -> {:ok, path}
      [] -> {:error, :not_found}
    end
  end

  # ============================================================================
  # Validation Helpers
  # ============================================================================

  @spec validate_password_length(String.t(), non_neg_integer(), boolean()) ::
          :ok | {:error, atom()} | {:error, {atom(), term()}}
  defp validate_password_length(password, min_length, allow_empty) do
    length = String.length(password)

    cond do
      length == 0 and not allow_empty ->
        {:error, :password_empty}

      length < min_length ->
        {:error, {:password_too_short, min_length}}

      true ->
        :ok
    end
  end

  defp leading_or_trailing_whitespace?(password), do: password != String.trim(password)

  defp strip_trailing_newline(password) do
    password
    |> strip_suffix("\r\n")
    |> strip_suffix("\n")
    |> strip_suffix("\r")
  end

  defp strip_suffix(password, suffix) do
    if String.ends_with?(password, suffix) do
      binary_part(password, 0, byte_size(password) - byte_size(suffix))
    else
      password
    end
  end

  defp normalize_source(nil), do: :tty
  defp normalize_source(:tty), do: :tty
  defp normalize_source(:stdin), do: :stdin
  defp normalize_source({:file, path}) when is_binary(path), do: {:file, path}
  defp normalize_source({:fd, fd}) when is_integer(fd) and fd >= 0, do: {:fd, fd}
  defp normalize_source(other), do: other

  # ============================================================================
  # Error builders
  # ============================================================================

  defp build_error(:missing_password, source) do
    message = "Error: No password provided on #{source_label(source)}."
    %PromptError{message: message, exit_code: 2, reason: :missing_password}
  end

  defp build_error(:missing_confirmation, source) do
    message =
      "Error: Password confirmation not provided on #{source_label(source)}. " <>
        "Provide two lines or use --no-confirm."

    %PromptError{message: message, exit_code: 2, reason: :missing_confirmation}
  end

  defp build_error(:confirmation_mismatch, source) do
    message = "Error: Password confirmation from #{source_label(source)} does not match."
    %PromptError{message: message, exit_code: 2, reason: :confirmation_mismatch}
  end

  defp build_error({:whitespace, :password}, source) do
    lines = [
      "Error: Password from #{source_label(source)} has leading/trailing spaces.",
      "Passwords must not start or end with whitespace."
    ]

    %PromptError{message: Enum.join(lines, "\n"), exit_code: 2, reason: :whitespace}
  end

  defp build_error({:whitespace, :confirmation}, source) do
    lines = [
      "Error: Password confirmation from #{source_label(source)} has leading/trailing spaces.",
      "Passwords must not start or end with whitespace."
    ]

    %PromptError{message: Enum.join(lines, "\n"), exit_code: 2, reason: :whitespace}
  end

  defp build_error({:empty, :password}, source) do
    message = "Error: Password from #{source_label(source)} cannot be empty."
    %PromptError{message: message, exit_code: 2, reason: :password_empty}
  end

  defp build_error({:empty, :confirmation}, source) do
    message = "Error: Password confirmation from #{source_label(source)} cannot be empty."
    %PromptError{message: message, exit_code: 2, reason: :password_empty}
  end

  defp build_error({:too_short, :password, min}, source) do
    message =
      "Error: Password from #{source_label(source)} must be at least #{min} characters long."

    %PromptError{message: message, exit_code: 2, reason: {:password_too_short, min}}
  end

  defp build_error({:too_short, :confirmation, min}, source) do
    message =
      "Error: Password confirmation from #{source_label(source)} must be at least #{min} characters long."

    %PromptError{message: message, exit_code: 2, reason: {:password_too_short, min}}
  end

  defp build_io_error(:unsupported_fd, source) do
    message =
      "Error: Password file descriptors are not supported on this platform (#{source_label(source)})."

    %PromptError{message: message, exit_code: 2, reason: :io_error}
  end

  defp build_io_error(:fd_not_available, source) do
    message =
      "Error: #{String.capitalize(source_label(source))} is not available for reading."

    %PromptError{message: message, exit_code: 2, reason: :io_error}
  end

  defp build_io_error(reason, source) do
    message =
      "Error: Could not read password from #{source_label(source)}: #{:file.format_error(reason)}"

    %PromptError{message: message, exit_code: 2, reason: :io_error}
  end

  defp source_label(:stdin), do: "stdin"
  defp source_label({:file, path}), do: "file #{path}"
  defp source_label({:fd, fd}), do: "file descriptor #{fd}"
  defp source_label(:tty), do: "prompt"
  defp source_label(other), do: to_string(other)

  # ============================================================================
  # Masked input helpers
  # ============================================================================

  defp read_masked_input(prompt) do
    case System.get_env("GIT_FOIL_TTY") do
      nil ->
        do_read_masked_input(prompt)

      tty_path ->
        IO.write(prompt)
        read_from_tty_file(tty_path)
    end
  end

  defp do_read_masked_input(prompt) do
    IO.write(prompt)

    case :io.get_password() do
      chars when is_list(chars) ->
        {:ok, List.to_string(chars)}

      {:error, :enotsup} ->
        fallback_read_line()

      {:error, :interrupted} = interrupted ->
        interrupted

      {:error, reason} ->
        {:error, build_interactive_error(reason)}
    end
  end

  defp fallback_read_line do
    case IO.gets("") do
      :eof -> {:error, :eof}
      nil -> {:error, :eof}
      {:error, reason} -> {:error, reason}
      line when is_binary(line) -> {:ok, line}
    end
  end

  defp read_from_tty_file(path) do
    case File.open(path, [:read]) do
      {:ok, device} ->
        try do
          case IO.gets(device, "") do
            :eof -> {:error, :eof}
            {:error, reason} -> {:error, reason}
            line when is_binary(line) -> {:ok, line}
          end
        after
          File.close(device)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_interrupted do
    IO.puts(:stderr, "\nInterrupted")
    System.halt(130)
  end

  defp build_interactive_error(reason) do
    message = "Error: Password prompt failed: #{format_error(reason)}"
    %PromptError{message: message, exit_code: 2, reason: reason}
  end
end
