defmodule GitFoil.Commands.UnencryptKey do
  @moduledoc """
  Remove password protection from the GitFoil master key.

  Converts `.git/git_foil/master.key.enc` back to plaintext storage.
  """

  alias GitFoil.CLI.PasswordPrompt
  alias GitFoil.Core.{KeyManager, KeyMigration}
  alias GitFoil.Helpers.UIPrompts

  @doc """
  Execute the command.
  """
  def run(_opts \\ []) do
    IO.puts("🔓  Removing password protection from master key...")
    IO.puts("")

    with :ok <- verify_git_repository(),
         {:ok, status} <- ensure_initialized() do
      case status do
        :password_protected ->
          unencrypt_key()

        :plaintext ->
          {:ok, already_plaintext_message()}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp unencrypt_key do
    case PasswordPrompt.get_password_with_fallback("Current master key password: ") do
      {:ok, password} ->
        case KeyMigration.unencrypt_key(password) do
          {:ok, %{backup_path: backup_path}} ->
            {:ok, success_message(backup_path)}

          {:error, :already_plaintext} ->
            {:ok, already_plaintext_message()}

          {:error, :invalid_password} ->
            {:error, "Invalid password. Master key remains encrypted."}

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
    plaintext_path = KeyMigration.plaintext_path()

    """
    ✅  Master key stored without password.

    📍  Plaintext key saved to: #{plaintext_path}
    🗃️  Encrypted backup copied to: #{backup_path}

    Keep the encrypted backup somewhere safe (or delete it once you've stored it securely).
    """
  end

  defp already_plaintext_message do
    plaintext_path = KeyMigration.plaintext_path()

    """
    ✅  Master key already stored without password.

    📍  Plaintext key located at: #{plaintext_path}

    To enable password protection, run: git-foil encrypt key
    """
  end

  defp format_migration_error({:backup_failed, reason}) do
    "Failed to back up encrypted key: #{UIPrompts.format_error(reason)}"
  end

  defp format_migration_error({:remove_failed, reason}) do
    """
    Plaintext key saved successfully, but failed to remove encrypted key: #{UIPrompts.format_error(reason)}

    Remove #{KeyMigration.encrypted_path()} manually once resolved.
    """
    |> String.trim()
  end

  defp format_migration_error(:no_encrypted_key) do
    """
    Encrypted master key not found at #{KeyMigration.encrypted_path()}.

    If your key is already plaintext, run 'git-foil encrypt key' instead.
    """
    |> String.trim()
  end

  defp format_migration_error(other) when is_binary(other), do: other
  defp format_migration_error(other), do: UIPrompts.format_error(other)
end
