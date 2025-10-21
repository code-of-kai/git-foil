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
    case PasswordPrompt.get_password_with_fallback("New password for master key: ", confirm: true) do
      {:ok, password} ->
        case KeyMigration.encrypt_plaintext_key(password) do
          {:ok, %{backup_path: backup_path}} ->
            {:ok, success_message(backup_path)}

          {:error, :already_encrypted} ->
            {:ok, already_encrypted_message()}

          {:error, other} ->
            {:error, format_migration_error(other)}
        end

      {:error, reason} ->
        {:error, "Password prompt failed: #{PasswordPrompt.format_error(reason)}"}
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
