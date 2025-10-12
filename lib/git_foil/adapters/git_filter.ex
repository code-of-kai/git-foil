defmodule GitFoil.Adapters.GitFilter do
  @moduledoc """
  Git clean/smudge filter adapter.

  **Git Filter Protocol:**
  - Clean: Encrypts plaintext when adding files to Git (git add)
  - Smudge: Decrypts ciphertext when checking out files (git checkout)

  **Integration:**
  Git calls this via configured filter commands:
  ```
  git config filter.gitfoil.clean "git-foil clean %f"
  git config filter.gitfoil.smudge "git-foil smudge %f"
  ```

  **Data Flow:**
  - Clean: stdin (plaintext) → encrypt → stdout (ciphertext)
  - Smudge: stdin (ciphertext) → decrypt → stdout (plaintext)

  **Error Handling:**
  - Encryption/decryption errors written to stderr
  - Git receives empty output on error (preserves original file)
  - Non-zero exit code signals failure to Git
  """

  @behaviour GitFoil.Ports.Filter

  alias GitFoil.Core.{EncryptionEngine, KeyManager}
  alias GitFoil.CLI.PasswordPrompt
  alias GitFoil.Adapters.{
    OpenSSLCrypto,
    AegisCrypto,
    SchwaemmCrypto,
    DeoxysCrypto,
    AsconCrypto,
    ChaCha20Poly1305Crypto
  }

  require Logger

  @impl true
  def clean(plaintext, file_path) when is_binary(plaintext) and is_binary(file_path) do
    with {:ok, master_key} <- load_master_key(),
         {:ok, encrypted_blob} <- encrypt_content(plaintext, master_key, file_path),
         serialized <- EncryptionEngine.serialize(encrypted_blob) do
      {:ok, serialized}
    else
      {:error, :not_initialized} ->
        {:error, "GitFoil not initialized - run 'git-foil init' first"}

      {:error, reason} ->
        {:error, "Encryption failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def smudge(encrypted, file_path) when is_binary(encrypted) and is_binary(file_path) do
    with {:ok, master_key} <- load_master_key(),
         {:ok, blob} <- EncryptionEngine.deserialize(encrypted),
         {:ok, plaintext} <- decrypt_content(blob, master_key, file_path) do
      {:ok, plaintext}
    else
      {:error, :not_initialized} ->
        {:error, "GitFoil not initialized - run 'git-foil init' first"}

      {:error, :invalid_blob_format} ->
        # Not a GitFoil encrypted file - return as-is
        # This handles files that were committed before encryption was enabled
        {:ok, encrypted}

      {:error, reason} ->
        {:error, "Decryption failed: #{inspect(reason)}"}
    end
  end

  # Loads master encryption key from storage (plaintext or password-protected)
  defp load_master_key do
    case KeyManager.initialization_status() do
      {:initialized, :password_protected} ->
        # Password-protected storage - try to unlock
        unlock_password_protected()

      {:initialized, :plaintext} ->
        # Plaintext storage - load directly
        KeyManager.unlock_without_password()

      :not_initialized ->
        {:error, :not_initialized}
    end
  end

  # Unlocks password-protected storage
  # First checks if already unlocked (cached), then prompts if needed
  defp unlock_password_protected do
    case KeyManager.get_master_key() do
      {:ok, master_key} ->
        # Already unlocked in this process
        {:ok, master_key}

      {:error, :locked} ->
        # Not yet unlocked - try environment variable first, then prompt
        case System.get_env("GIT_FOIL_PASSWORD") do
          nil ->
            # No env var - prompt for password
            prompt_for_password()

          password when is_binary(password) ->
            # Use password from environment
            KeyManager.unlock_with_password(password)
        end
    end
  end

  # Prompts user for password to unlock key
  defp prompt_for_password do
    case PasswordPrompt.get_password("GitFoil password: ") do
      {:ok, password} ->
        case KeyManager.unlock_with_password(password) do
          {:ok, master_key} ->
            {:ok, master_key}

          {:error, :invalid_password} ->
            {:error, "Invalid password. Run 'git-foil init' if you've lost your password."}

          {:error, reason} ->
            {:error, "Failed to unlock: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Password prompt failed: #{PasswordPrompt.format_error(reason)}"}
    end
  end

  # Encrypts plaintext using the full encryption pipeline
  # Six-layer quantum-resistant encryption:
  # - Layer 1: AES-256-GCM
  # - Layer 2: AEGIS-256
  # - Layer 3: Schwaemm256-256
  # - Layer 4: Deoxys-II-256
  # - Layer 5: Ascon-128a
  # - Layer 6: ChaCha20-Poly1305
  defp encrypt_content(plaintext, master_key, file_path) do
    EncryptionEngine.encrypt(
      plaintext,
      master_key,
      OpenSSLCrypto,           # Layer 1: AES-256-GCM
      AegisCrypto,             # Layer 2: AEGIS-256
      SchwaemmCrypto,          # Layer 3: Schwaemm256-256
      DeoxysCrypto,            # Layer 4: Deoxys-II-256
      AsconCrypto,             # Layer 5: Ascon-128a
      ChaCha20Poly1305Crypto,  # Layer 6: ChaCha20-Poly1305
      file_path
    )
  end

  # Decrypts encrypted blob using the full decryption pipeline
  # Must use same providers in same order as encryption
  defp decrypt_content(blob, master_key, file_path) do
    EncryptionEngine.decrypt(
      blob,
      master_key,
      OpenSSLCrypto,           # Layer 1: AES-256-GCM
      AegisCrypto,             # Layer 2: AEGIS-256
      SchwaemmCrypto,          # Layer 3: Schwaemm256-256
      DeoxysCrypto,            # Layer 4: Deoxys-II-256
      AsconCrypto,             # Layer 5: Ascon-128a
      ChaCha20Poly1305Crypto,  # Layer 6: ChaCha20-Poly1305
      file_path
    )
  end

  @doc """
  Processes a filter operation (clean or smudge) with proper I/O handling.

  This is the main entry point called by the CLI. It handles:
  - Reading from stdin
  - Calling the appropriate filter operation
  - Writing to stdout
  - Error logging to stderr

  Returns {:ok, exit_code} where exit_code is 0 for success, 1 for failure.
  """
  def process(operation, file_path, opts \\ [])
      when operation in [:clean, :smudge] and is_binary(file_path) do
    input_device = Keyword.get(opts, :input, :stdio)
    output_device = Keyword.get(opts, :output, :stdio)

    # Ensure stdio is in binary mode (handles non-UTF8 files)
    if input_device == :stdio do
      :io.setopts(:standard_io, [:binary, encoding: :latin1])
    end

    # Read entire input (Git provides complete file content)
    # binread returns binary data or error tuple
    input = IO.binread(input_device, :eof)

    # Handle IO read errors
    result = case input do
      {:error, reason} ->
        {:error, "Failed to read input: #{inspect(reason)}"}

      :eof ->
        # No input available (e.g., in tests with no stdin)
        {:ok, ""}

      binary when is_binary(binary) ->
        case operation do
          :clean -> clean(binary, file_path)
          :smudge -> smudge(binary, file_path)
        end
    end

    case result do
      {:ok, output} ->
        # Write encrypted/decrypted output to stdout
        IO.binwrite(output_device, output)
        {:ok, 0}

      {:error, reason} ->
        # Log error to stderr, return empty output to Git
        IO.puts(:stderr, "GitFoil #{operation} error: #{reason}")
        {:error, 1}
    end
  end
end
