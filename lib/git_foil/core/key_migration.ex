defmodule GitFoil.Core.KeyMigration do
  @moduledoc """
  Shared operations for migrating the GitFoil master key between plaintext
  and password-protected storage.

  These helpers centralize the file handling, backup creation, and cache
  management needed when toggling password protection. Commands should handle
  prompting and user interaction, then delegate the actual migration here.
  """

  alias GitFoil.Adapters.{FileKeyStorage, PasswordProtectedKeyStorage}
  alias GitFoil.Core.KeyManager

  @type migration_result :: {:ok, %{backup_path: String.t()}} | {:error, term()}

  @plaintext_filename "master.key"
  @encrypted_filename "master.key.enc"
  @plaintext_backup_prefix "master.key.backup"
  @encrypted_backup_prefix "master.key.enc.backup"

  @doc """
  Encrypts the existing plaintext master key with the provided password.

  Returns `{:ok, %{backup_path: path}}` on success. The plaintext key is copied
  to a timestamped backup before encryption, then removed after the encrypted
  key is written.
  """
  @spec encrypt_plaintext_key(String.t()) :: migration_result()
  def encrypt_plaintext_key(password) when is_binary(password) do
    plaintext_path = plaintext_key_path()

    cond do
      File.exists?(encrypted_key_path()) ->
        {:error, :already_encrypted}

      not File.exists?(plaintext_path) ->
        {:error, :no_plaintext_key}

      true ->
        with {:ok, keypair} <- FileKeyStorage.retrieve_keypair(),
             {:ok, backup_path} <- copy_backup(plaintext_path, @plaintext_backup_prefix),
             :ok <- PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password),
             :ok <- remove_file(plaintext_path) do
          KeyManager.clear_cache()
          {:ok, %{backup_path: backup_path}}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Removes password protection from the master key, storing it in plaintext.

  The encrypted key is copied to a timestamped backup before conversion. On
  success the encrypted file is removed and caches are cleared.
  """
  @spec unencrypt_key(String.t()) :: migration_result()
  def unencrypt_key(password) when is_binary(password) do
    encrypted_path = encrypted_key_path()

    cond do
      File.exists?(plaintext_key_path()) and not File.exists?(encrypted_path) ->
        {:error, :already_plaintext}

      not File.exists?(encrypted_path) ->
        {:error, :no_encrypted_key}

      true ->
        with {:ok, keypair} <-
               PasswordProtectedKeyStorage.retrieve_keypair_with_password(password),
             {:ok, backup_path} <- copy_backup(encrypted_path, @encrypted_backup_prefix),
             :ok <- FileKeyStorage.store_keypair(keypair),
             :ok <- remove_file(encrypted_path) do
          KeyManager.clear_cache()
          {:ok, %{backup_path: backup_path}}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # ===========================================================================
  # Paths
  # ===========================================================================
  @doc """
  Returns the absolute path to the plaintext master key.
  """
  @spec plaintext_path() :: String.t()
  def plaintext_path do
    plaintext_key_path()
  end

  @doc """
  Returns the absolute path to the encrypted master key.
  """
  @spec encrypted_path() :: String.t()
  def encrypted_path do
    encrypted_key_path()
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp copy_backup(source_path, prefix) do
    backup_path = Path.join(Path.dirname(source_path), "#{prefix}.#{timestamp_suffix()}")

    case File.cp(source_path, backup_path) do
      :ok ->
        :ok = set_secure_permissions(backup_path)
        {:ok, backup_path}

      {:error, reason} ->
        {:error, {:backup_failed, reason}}
    end
  end

  defp remove_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:remove_failed, reason}}
    end
  end

  defp set_secure_permissions(path) do
    case File.chmod(path, 0o600) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp timestamp_suffix do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
    |> String.replace(":", "-")
    |> String.replace(".", "-")
  end

  defp encrypted_key_path do
    Path.join(key_directory(), @encrypted_filename)
  end

  defp plaintext_key_path do
    Path.join(key_directory(), @plaintext_filename)
  end

  defp key_directory do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> Path.expand()
        |> Path.join("git_foil")

      {_error, _code} ->
        Path.expand(".git/git_foil")
    end
  end
end
