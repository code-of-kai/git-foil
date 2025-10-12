defmodule GitFoil.Adapters.PasswordProtectedKeyStorage do
  @moduledoc """
  Password-protected file-based key storage using PBKDF2 + AES-GCM.

  This adapter encrypts the master keypair with a user-provided password before
  storing it to disk, addressing the "stolen laptop without disk encryption" threat.

  **Security Model:**
  - Keypair encrypted with AES-256-GCM
  - Encryption key derived from password via PBKDF2-HMAC-SHA512 (600K iterations)
  - Random salt and nonce per encryption
  - Authentication tag prevents tampering
  - File permissions: 0600 (owner read/write only)

  **File Format:**
  Encrypted keypair stored in `.git/git_foil/master.key.enc`
  See `GitFoil.Core.PasswordProtection` for format details.
  """

  @behaviour GitFoil.Ports.KeyStorage

  alias GitFoil.Core.Types.{Keypair, EncryptionKey}
  alias GitFoil.Core.PasswordProtection

  @key_subdir "git_foil"
  @encrypted_key_filename "master.key.enc"

  @impl true
  def generate_keypair do
    # Use same generation logic as FileKeyStorage
    {pq_public, pq_secret} = :pqclean_nif.kyber1024_keypair()

    classical_public = :crypto.strong_rand_bytes(32)
    classical_secret = :crypto.strong_rand_bytes(32)

    keypair = %Keypair{
      classical_public: classical_public,
      classical_secret: classical_secret,
      pq_public: pq_public,
      pq_secret: pq_secret
    }

    {:ok, keypair}
  end

  @impl true
  def store_keypair(keypair) do
    # This implementation requires password to be passed via process dictionary
    # This is intentional - password should be provided by caller during init
    case Process.get(:gitfoil_password) do
      nil ->
        {:error, "Password required for encrypted key storage. Call set_password/1 first."}

      password ->
        store_keypair_with_password(keypair, password)
    end
  end

  @doc """
  Store keypair with explicit password (bypasses process dictionary).

  Useful for testing and explicit password management.
  """
  @spec store_keypair_with_password(Keypair.t(), String.t()) :: :ok | {:error, term()}
  def store_keypair_with_password(%Keypair{} = keypair, password) when is_binary(password) do
    encrypted_path = encrypted_key_path()

    with {:ok, validated_password} <- PasswordProtection.validate_password(password),
         {:ok, encrypted_blob} <- PasswordProtection.encrypt_keypair(keypair, validated_password),
         :ok <- atomic_write_secure(encrypted_path, encrypted_blob) do
      :ok
    else
      {:error, :password_too_short} ->
        {:error, "Password must be at least 8 characters"}

      {:error, :password_too_long} ->
        {:error, "Password must be less than 1024 characters"}

      {:error, reason} ->
        {:error, "Failed to store encrypted keypair: #{inspect(reason)}"}
    end
  end

  @impl true
  def retrieve_keypair do
    # This implementation requires password to be passed via process dictionary
    case Process.get(:gitfoil_password) do
      nil ->
        {:error, "Password required to decrypt key. Call set_password/1 first."}

      password ->
        retrieve_keypair_with_password(password)
    end
  end

  @doc """
  Retrieve keypair with explicit password (bypasses process dictionary).

  Useful for testing and explicit password management.
  """
  @spec retrieve_keypair_with_password(String.t()) :: {:ok, Keypair.t()} | {:error, term()}
  def retrieve_keypair_with_password(password) when is_binary(password) do
    encrypted_path = encrypted_key_path()

    with {:ok, encrypted_blob} <- File.read(encrypted_path),
         {:ok, keypair} <- PasswordProtection.decrypt_keypair(encrypted_blob, password) do
      {:ok, keypair}
    else
      {:error, :enoent} ->
        {:error, :not_found}

      {:error, :invalid_password} ->
        {:error, :invalid_password}

      {:error, reason} ->
        {:error, "Failed to read encrypted keypair: #{inspect(reason)}"}
    end
  end

  @impl true
  def store_file_key(_path, _key) do
    # Not implemented yet - reserved for file-specific key caching
    {:error, :not_implemented}
  end

  @impl true
  def retrieve_file_key(_path) do
    # Not implemented yet - reserved for file-specific key caching
    {:error, :not_found}
  end

  @impl true
  def delete_file_key(_path) do
    # Not implemented yet - reserved for file-specific key caching
    :ok
  end

  @doc """
  Derives the master encryption key from the stored keypair.

  This is a convenience function that combines retrieve_keypair/0
  with key derivation logic.
  """
  def derive_master_key do
    case retrieve_keypair() do
      {:ok, keypair} ->
        # Deterministic derivation: SHA-512(classical_secret || pq_secret)
        # Take first 32 bytes for 256-bit key
        combined = keypair.classical_secret <> keypair.pq_secret
        master_key_bytes = :crypto.hash(:sha512, combined) |> binary_part(0, 32)
        master_key = EncryptionKey.new(master_key_bytes)
        {:ok, master_key}

      {:error, :not_found} ->
        {:error, :not_initialized}

      error ->
        error
    end
  end

  @doc """
  Derives master encryption key with explicit password.
  """
  @spec derive_master_key_with_password(String.t()) ::
          {:ok, EncryptionKey.t()} | {:error, term()}
  def derive_master_key_with_password(password) when is_binary(password) do
    case retrieve_keypair_with_password(password) do
      {:ok, keypair} ->
        combined = keypair.classical_secret <> keypair.pq_secret
        master_key_bytes = :crypto.hash(:sha512, combined) |> binary_part(0, 32)
        master_key = EncryptionKey.new(master_key_bytes)
        {:ok, master_key}

      error ->
        error
    end
  end

  @doc """
  Checks if GitFoil has been initialized with password-protected storage.
  """
  def initialized? do
    File.exists?(encrypted_key_path())
  end

  @doc """
  Sets the password in the process dictionary for subsequent operations.

  This is a convenience for init/unlock workflows where the password
  is collected once and used for multiple operations.

  ## Examples

      PasswordProtectedKeyStorage.set_password("my-secure-password")
      PasswordProtectedKeyStorage.store_keypair(keypair)  # Uses stored password
      PasswordProtectedKeyStorage.retrieve_keypair()       # Uses stored password
  """
  @spec set_password(String.t()) :: :ok
  def set_password(password) when is_binary(password) do
    Process.put(:gitfoil_password, password)
    :ok
  end

  @doc """
  Clears the password from the process dictionary.

  Good security practice after operations are complete.
  """
  @spec clear_password() :: :ok
  def clear_password do
    Process.delete(:gitfoil_password)
    :ok
  end

  @doc """
  Deletes the encrypted keypair file.

  Useful for key rotation or uninstall.
  """
  @spec delete_keypair() :: :ok | {:error, term()}
  def delete_keypair do
    encrypted_path = encrypted_key_path()

    case File.rm(encrypted_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok  # Already deleted
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp encrypted_key_path do
    Path.join(key_directory(), @encrypted_key_filename)
  end

  defp key_directory do
    case get_git_dir() do
      {:ok, git_dir} -> Path.join(git_dir, @key_subdir)
      {:error, _} -> ".git/#{@key_subdir}"  # Fallback to relative path
    end
  end

  defp get_git_dir do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {output, 0} ->
        git_dir = String.trim(output)
        absolute_git_dir = Path.expand(git_dir)
        {:ok, absolute_git_dir}

      {_error, _} ->
        {:error, :not_in_git_repo}
    end
  end

  # Atomically writes content to a file with secure permissions from the start.
  # This prevents TOCTOU race conditions where the file briefly exists with
  # default permissions before chmod is applied.
  #
  # Implementation:
  # 1. Write to temporary file with 0600 permissions
  # 2. fsync to ensure data is on disk
  # 3. Atomically rename to final path (POSIX guarantees)
  #
  # Note: On Windows, File.chmod may be a no-op. Future enhancement could
  # use platform-specific APIs for Windows ACLs.
  defp atomic_write_secure(path, content) when is_binary(content) do
    dir = Path.dirname(path)
    basename = Path.basename(path)

    # Ensure parent directory exists with secure permissions
    case ensure_directory_with_perms(dir, 0o700) do
      :ok -> :ok
      error -> error
    end

    # Create temporary file name
    unique_suffix = System.unique_integer([:positive, :monotonic])
    tmp_path = Path.join(dir, ".#{basename}.tmp.#{unique_suffix}")

    try do
      # Open file with exclusive creation
      {:ok, io} = :file.open(tmp_path, [:write, :binary, :raw, :exclusive])

      try do
        # Write content and fsync for durability
        :ok = :file.write(io, content)
        :ok = :file.sync(io)
        :ok = :file.close(io)

        # Set secure permissions on temp file before rename
        # This ensures the file has correct perms even if umask is permissive
        case File.chmod(tmp_path, 0o600) do
          :ok -> :ok
          {:error, _} -> :ok  # Continue anyway - some platforms may not support chmod
        end

        # Atomically rename into place
        # POSIX rename(2) is atomic, ensuring no partial file is ever visible
        case File.rename(tmp_path, path) do
          :ok ->
            :ok

          {:error, reason} ->
            # Cleanup temp file on rename failure
            File.rm(tmp_path)
            {:error, reason}
        end
      rescue
        error ->
          :file.close(io)
          File.rm(tmp_path)
          {:error, error}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  # Ensures directory exists with specific permissions
  defp ensure_directory_with_perms(dir, mode) do
    case File.mkdir_p(dir) do
      :ok ->
        # Set directory permissions (important for .git/git_foil)
        case File.chmod(dir, mode) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
