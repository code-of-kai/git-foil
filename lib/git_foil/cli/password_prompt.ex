defmodule GitFoil.CLI.PasswordPrompt do
  @moduledoc """
  Simple password prompting for CLI operations.

  Provides visible password input with optional confirmation.
  Supports environment variable fallback for automation/CI.
  """

  @env_var "GIT_FOIL_PASSWORD"

  @doc """
  Prompts user for password.

  ## Options
  - `:confirm` - If true, prompts for password confirmation (default: false)
  - `:min_length` - Minimum password length (default: 8)
  - `:allow_empty` - Allow empty passwords (default: false)
  """
  @spec get_password(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def get_password(prompt, opts \\ []) do
    confirm? = Keyword.get(opts, :confirm, false)
    min_length = Keyword.get(opts, :min_length, 8)
    allow_empty = Keyword.get(opts, :allow_empty, false)

    with {:ok, password} <- read_password(prompt),
         :ok <- validate_password_length(password, min_length, allow_empty),
         :ok <- maybe_confirm_password(password, confirm?) do
      {:ok, password}
    end
  end

  @doc """
  Gets password from environment variable or prompts if not set.

  Checks `GIT_FOIL_PASSWORD` environment variable first.
  Falls back to interactive prompt if not set.
  """
  @spec get_password_with_fallback(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def get_password_with_fallback(prompt, opts \\ []) do
    case System.get_env(@env_var) do
      nil ->
        get_password(prompt, opts)

      password when is_binary(password) ->
        min_length = Keyword.get(opts, :min_length, 8)
        allow_empty = Keyword.get(opts, :allow_empty, false)

        case validate_password_length(password, min_length, allow_empty) do
          :ok -> {:ok, password}
          error -> error
        end
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Reads password from stdin (visible)
  @spec read_password(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp read_password(prompt) do
    with {:ok, raw} <- read_from_tty(prompt) do
      {:ok, String.trim(raw)}
    end
  end

  defp read_from_tty(prompt) do
    case open_tty() do
      {:ok, tty} ->
        try do
          case IO.gets(tty, prompt) do
            :eof ->
              {:error, :eof}

            {:error, reason} ->
              {:error, reason}

            line when is_binary(line) ->
              {:ok, line}
          end
        after
          File.close(tty)
        end

      {:error, _reason} ->
        # Fallback to standard IO (works when piping passwords)
        case IO.gets(prompt) do
          :eof ->
            {:error, :eof}

          {:error, reason} ->
            {:error, reason}

          line when is_binary(line) ->
            {:ok, line}
        end
    end
  end

  defp open_tty do
    cond do
      tty_path = System.get_env("GIT_FOIL_TTY") ->
        File.open(tty_path, [:read, :write])

      match?({:unix, _}, :os.type()) ->
        File.open("/dev/tty", [:read, :write])

      match?({:win32, _}, :os.type()) ->
        File.open("CONIN$", [:read, :write])

      true ->
        {:error, :no_tty}
    end
  end

  # Validates password meets minimum length requirement
  @spec validate_password_length(String.t(), non_neg_integer(), boolean()) ::
          :ok | {:error, atom()}
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

  # Optionally confirms password by prompting again
  @spec maybe_confirm_password(String.t(), boolean()) :: :ok | {:error, :password_mismatch}
  defp maybe_confirm_password(_password, false), do: :ok

  defp maybe_confirm_password(password, true) do
    case read_password("Confirm password: ") do
      {:ok, ^password} ->
        :ok

      {:ok, _other} ->
        {:error, :password_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Formats error messages for user display.
  """
  @spec format_error(atom() | {atom(), term()}) :: String.t()
  def format_error(:password_mismatch), do: "Passwords do not match"
  def format_error(:password_empty), do: "Password cannot be empty"

  def format_error({:password_too_short, min_length}),
    do: "Password must be at least #{min_length} characters"

  def format_error(:eof), do: "Unexpected end of input"
  def format_error(other), do: "Password input failed: #{inspect(other)}"
end
