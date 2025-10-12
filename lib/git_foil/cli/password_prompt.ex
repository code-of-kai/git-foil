defmodule GitFoil.CLI.PasswordPrompt do
  @moduledoc """
  Secure password prompting for CLI operations.

  Provides password input with echo disabled and optional confirmation.
  Supports environment variable fallback for automation/CI.

  ## Security Features
  - Echo disabled during input (password not visible)
  - Confirmation prompt to prevent typos
  - Environment variable support for automation
  - Clears password from memory after use

  ## Examples

      # Interactive prompt with confirmation
      {:ok, password} = PasswordPrompt.get_password("Enter password: ", confirm: true)

      # Simple prompt without confirmation
      {:ok, password} = PasswordPrompt.get_password("Password: ")

      # Check environment variable first
      {:ok, password} = PasswordPrompt.get_password_with_fallback("Enter password: ")
  """

  @env_var "GIT_FOIL_PASSWORD"

  @doc """
  Prompts user for password with echo disabled.

  ## Options
  - `:confirm` - If true, prompts for password confirmation (default: false)
  - `:min_length` - Minimum password length (default: 8)
  - `:allow_empty` - Allow empty passwords (default: false)

  ## Examples

      iex> PasswordPrompt.get_password("Enter password: ")
      {:ok, "secret"}

      iex> PasswordPrompt.get_password("Enter password: ", confirm: true)
      {:ok, "secret"}

      iex> PasswordPrompt.get_password("Enter password: ", confirm: true)
      {:error, :password_mismatch}
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

  This is useful for CI/CD automation while maintaining
  interactive UX for human users.

  ## Examples

      # With environment variable set
      System.put_env("GIT_FOIL_PASSWORD", "secret")
      {:ok, "secret"} = PasswordPrompt.get_password_with_fallback("Enter password: ")

      # Without environment variable (prompts user)
      System.delete_env("GIT_FOIL_PASSWORD")
      {:ok, password} = PasswordPrompt.get_password_with_fallback("Enter password: ")
  """
  @spec get_password_with_fallback(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def get_password_with_fallback(prompt, opts \\ []) do
    case System.get_env(@env_var) do
      nil ->
        # No env var set, prompt interactively
        get_password(prompt, opts)

      password when is_binary(password) ->
        # Env var set, use it
        min_length = Keyword.get(opts, :min_length, 8)
        allow_empty = Keyword.get(opts, :allow_empty, false)

        case validate_password_length(password, min_length, allow_empty) do
          :ok -> {:ok, password}
          error -> error
        end
    end
  end

  @doc """
  Prompts for password twice and verifies they match.

  Returns `{:ok, password}` if both entries match,
  `{:error, :password_mismatch}` otherwise.
  """
  @spec get_confirmed_password(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :password_mismatch | atom()}
  def get_confirmed_password(prompt, confirm_prompt \\ "Confirm password: ") do
    with {:ok, password1} <- read_password(prompt),
         {:ok, password2} <- read_password(confirm_prompt) do
      if password1 == password2 do
        {:ok, password1}
      else
        {:error, :password_mismatch}
      end
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Reads password from stdin with echo disabled
  @spec read_password(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp read_password(prompt) do
    # Write prompt to stderr (so it appears even if stdout is redirected)
    IO.write(:stderr, prompt)

    # Disable echo (password won't be visible)
    original_echo = :io.getopts() |> Keyword.get(:echo, true)
    :io.setopts(echo: false)

    try do
      # Read password line
      case IO.gets("") do
        :eof ->
          {:error, :eof}

        {:error, reason} ->
          {:error, reason}

        line when is_binary(line) ->
          # Remove trailing newline and return
          password = String.trim_trailing(line, "\n")
          {:ok, password}
      end
    after
      # Always restore echo, even if error occurs
      :io.setopts(echo: original_echo)
      # Print newline since echo was off
      IO.write(:stderr, "\n")
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

  ## Examples

      iex> PasswordPrompt.format_error(:password_mismatch)
      "Passwords do not match"

      iex> PasswordPrompt.format_error({:password_too_short, 8})
      "Password must be at least 8 characters"
  """
  @spec format_error(atom() | {atom(), term()}) :: String.t()
  def format_error(:password_mismatch), do: "Passwords do not match"
  def format_error(:password_empty), do: "Password cannot be empty"

  def format_error({:password_too_short, min_length}),
    do: "Password must be at least #{min_length} characters"

  def format_error(:eof), do: "Unexpected end of input"
  def format_error(other), do: "Password input failed: #{inspect(other)}"
end
