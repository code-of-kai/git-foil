defmodule GitFoil.Commands.EncryptKey do
  @moduledoc """
  Encrypt the GitFoil master key with a password.

  Converts `.git/git_foil/master.key` into an encrypted
  `.git/git_foil/master.key.enc` protected by a user-supplied password.
  """

  alias GitFoil.CLI.PasswordPrompt
  alias GitFoil.Core.{KeyManager, KeyMigration}
  alias GitFoil.Helpers.UIPrompts

  @doc """
  Execute the command.
  """
  def run(_opts \\ []) do
    IO.puts("🔐  Encrypting master key...")
    IO.puts("")

    with :ok <- verify_git_repository(),
         {:ok, status} <- ensure_initialized() do
      case status do
        :plaintext ->
          encrypt_plaintext_key()

        :password_protected ->
          {:ok, already_encrypted_message()}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp encrypt_plaintext_key do
    case System.get_env("GIT_FOIL_PASSWORD") do
      # Interactive path: show requirements and reprompt until valid
      nil ->
        print_password_requirements()
        with {:ok, password} <- prompt_password_loop() do
          do_encrypt_with(password)
        end

      # Non-interactive path: respect env var and validate once
      _env_val ->
        case PasswordPrompt.get_password_with_fallback(
               "New password for master key: ",
               confirm: true
             ) do
          {:ok, password} -> do_encrypt_with(password)

          {:error, {:password_too_short, min}} ->
            {:error,
             "Password must be at least #{min} characters. Set GIT_FOIL_PASSWORD to a longer value, or unset it to be prompted interactively."}

          {:error, :password_empty} ->
            {:error,
             "Password cannot be empty. Set GIT_FOIL_PASSWORD to a non-empty value, or unset it to be prompted interactively."}

          {:error, :password_mismatch} ->
            {:error, "Passwords do not match. Re-run with a valid value or unset GIT_FOIL_PASSWORD."}

          {:error, reason} ->
            {:error, "Password prompt failed: #{PasswordPrompt.format_error(reason)}"}
        end
    end
  end

  defp do_encrypt_with(password) do
    case KeyMigration.encrypt_plaintext_key(password) do
      {:ok, %{backup_path: backup_path}} ->
        {:ok, success_message(backup_path)}

      {:error, :already_encrypted} ->
        {:ok, already_encrypted_message()}

      {:error, other} ->
        {:error, format_migration_error(other)}
    end
  end

  defp print_password_requirements do
    IO.puts("Password requirements:")
    IO.puts("  • Minimum 8 characters")
    IO.puts("  • Input is visible in this terminal (no hidden input)")
    IO.puts("  • Press Ctrl-C to cancel")
    IO.puts("")
  end

  # Interactive loop for password entry with confirmation and clear errors
  defp prompt_password_loop do
    case PasswordPrompt.get_password(
           "New password for master key (min 8 chars): ",
           confirm: true
         ) do
      {:ok, password} -> {:ok, password}
      {:error, :password_mismatch} ->
        IO.puts("\nError: Passwords do not match. Please try again.\n")
        prompt_password_loop()
      {:error, {:password_too_short, min}} ->
        IO.puts("\nError: Password must be at least #{min} characters. Please try again.\n")
        prompt_password_loop()
      {:error, :password_empty} ->
        IO.puts("\nError: Password cannot be empty. Please try again.\n")
        prompt_password_loop()
      {:error, other} ->
        {:error, "Password prompt failed: #{PasswordPrompt.format_error(other)}"}
    end
  end

  defp verify_git_repository do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {_error, _} ->
        {:error, "Not a Git repository. Run this command inside a Git repository."}
    end
  end

  defp ensure_initialized do
    case KeyManager.initialization_status() do
      {:initialized, :plaintext} ->
        {:ok, :plaintext}

      {:initialized, :password_protected} ->
        {:ok, :password_protected}

      :not_initialized ->
        {:error, "GitFoil not initialized. Run 'git-foil init' first."}
    end
  end

  defp success_message(backup_path) do
    encrypted_path = KeyMigration.encrypted_path()

    """
    ✅  Master key encrypted with password.

    📍  Encrypted key stored at: #{encrypted_path}
    🗃️  Plaintext backup copied to: #{backup_path}

    Keep the backup in a secure location (or delete it once you've stored it safely).
    """
  end

  defp already_encrypted_message do
    encrypted_path = KeyMigration.encrypted_path()

    """
    ✅  Master key already password protected.

    📍  Encrypted key located at: #{encrypted_path}

    If you need to remove password protection, run: git-foil unencrypt key
    """
  end

  defp format_migration_error({:backup_failed, reason}) do
    "Failed to back up master key: #{UIPrompts.format_error(reason)}"
  end

  defp format_migration_error({:remove_failed, reason}) do
    """
    Encrypted key saved successfully, but failed to remove plaintext key: #{UIPrompts.format_error(reason)}

    Remove #{KeyMigration.plaintext_path()} manually once resolved.
    """
    |> String.trim()
  end

  defp format_migration_error(:no_plaintext_key) do
    """
    Plaintext master key not found at #{KeyMigration.plaintext_path()}.

    If your key is already encrypted, run 'git-foil unencrypt key' instead.
    """
    |> String.trim()
  end

  defp format_migration_error(other) when is_binary(other), do: other
  defp format_migration_error(other), do: UIPrompts.format_error(other)
end
