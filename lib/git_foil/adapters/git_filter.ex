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
  alias GitFoil.CLI.PasswordInput

  alias GitFoil.Adapters.{
    OpenSSLCrypto,
    AegisCrypto,
    SchwaemmCrypto,
    DeoxysCrypto,
    AsconCrypto,
    ChaCha20Poly1305Crypto
  }

  require Logger

  @password_opts_key :gitfoil_password_options

  @impl true
  def clean(plaintext, file_path) when is_binary(plaintext) and is_binary(file_path) do
    with {:ok, master_key} <- load_master_key(),
         {:ok, encrypted_blob} <- encrypt_content(plaintext, master_key, file_path),
         serialized <- EncryptionEngine.serialize(encrypted_blob) do
      {:ok, serialized}
    else
      {:error, {exit_code, message}} ->
        {:error, {exit_code, message}}

      {:error, :not_initialized} ->
        {:error, "GitFoil not initialized - run 'git-foil init' first"}

      {:error, %UndefinedFunctionError{module: module}} ->
        {:error,
         "Crypto library not loaded (#{inspect(module)}). Escripts cannot load NIFs. Use 'mix run' instead or create a proper release with 'mix release'."}

      {:error, reason} ->
        {:error, "Encryption failed: #{format_error(reason)}"}
    end
  end

  @impl true
  def smudge(encrypted, file_path) when is_binary(encrypted) and is_binary(file_path) do
    with {:ok, master_key} <- load_master_key(),
         {:ok, blob} <- EncryptionEngine.deserialize(encrypted),
         {:ok, plaintext} <- decrypt_content(blob, master_key, file_path) do
      {:ok, plaintext}
    else
      {:error, {exit_code, message}} ->
        {:error, {exit_code, message}}

      {:error, :not_initialized} ->
        {:error, "GitFoil not initialized - run 'git-foil init' first"}

      {:error, :invalid_blob_format} ->
        {:ok, encrypted}

      {:error, %UndefinedFunctionError{module: module}} ->
        {:error,
         "Crypto library not loaded (#{inspect(module)}). Escripts cannot load NIFs. Use 'mix run' instead or create a proper release with 'mix release'."}

      {:error, reason} ->
        {:error, "Decryption failed: #{format_error(reason)}"}
    end
  end

  # Loads master encryption key from storage (plaintext or password-protected)
  defp load_master_key do
    password_opts = current_password_options()

    case KeyManager.unlock_without_password() do
      {:ok, master_key} ->
        {:ok, master_key}

      {:error, :password_required} ->
        unlock_password_protected(password_opts)

      {:error, :not_initialized} ->
        {:error, :not_initialized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Unlocks password-protected storage
  # First checks if already unlocked (cached), then prompts if needed
  defp unlock_password_protected(password_opts) do
    case KeyManager.get_master_key() do
      {:ok, master_key} ->
        # Already unlocked in this process
        {:ok, master_key}

      {:error, :locked} ->
        request_password_unlock(password_opts)
    end
  end
  defp request_password_unlock(password_opts) do
    case PasswordInput.existing_password("GitFoil password: ", password_opts) do
      {:ok, password} ->
        case KeyManager.unlock_with_password(password) do
          {:ok, master_key} ->
            {:ok, master_key}

          {:error, :invalid_password} ->
            {:error, {1, "Error: Invalid password."}}

          {:error, reason} ->
            {:error, {2, "Failed to unlock: #{format_error(reason)}"}}
        end

      {:error, {exit_code, message}} ->
        {:error, {exit_code, message}}
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
    try do
      EncryptionEngine.encrypt(
        plaintext,
        master_key,
        # Layer 1: AES-256-GCM
        OpenSSLCrypto,
        # Layer 2: AEGIS-256
        AegisCrypto,
        # Layer 3: Schwaemm256-256
        SchwaemmCrypto,
        # Layer 4: Deoxys-II-256
        DeoxysCrypto,
        # Layer 5: Ascon-128a
        AsconCrypto,
        # Layer 6: ChaCha20-Poly1305
        ChaCha20Poly1305Crypto,
        file_path
      )
    rescue
      e in UndefinedFunctionError ->
        {:error, e}
    end
  end

  # Decrypts encrypted blob using the full decryption pipeline
  # Must use same providers in same order as encryption
  defp decrypt_content(blob, master_key, file_path) do
    try do
      EncryptionEngine.decrypt(
        blob,
        master_key,
        # Layer 1: AES-256-GCM
        OpenSSLCrypto,
        # Layer 2: AEGIS-256
        AegisCrypto,
        # Layer 3: Schwaemm256-256
        SchwaemmCrypto,
        # Layer 4: Deoxys-II-256
        DeoxysCrypto,
        # Layer 5: Ascon-128a
        AsconCrypto,
        # Layer 6: ChaCha20-Poly1305
        ChaCha20Poly1305Crypto,
        file_path
      )
    rescue
      e in UndefinedFunctionError ->
        {:error, e}
    end
  end

  defp with_password_options(opts, fun) when is_function(fun, 0) do
    password_opts =
      opts
      |> Keyword.take([:password_source])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    previous = Process.get(@password_opts_key, :undefined)

    Process.put(@password_opts_key, password_opts)

    try do
      fun.()
    after
      case previous do
        :undefined -> Process.delete(@password_opts_key)
        value -> Process.put(@password_opts_key, value)
      end
    end
  end

  defp current_password_options do
    case Process.get(@password_opts_key) do
      nil -> []
      value -> value
    end
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
    result =
      case input do
        {:error, reason} ->
          {:error, "Failed to read input: #{format_error(reason)}"}

        :eof ->
          # No input available (e.g., in tests with no stdin)
          {:ok, ""}

        binary when is_binary(binary) ->
          with_password_options(opts, fn ->
            case operation do
              :clean -> clean(binary, file_path)
              :smudge -> smudge(binary, file_path)
            end
          end)
      end

    case result do
      {:ok, output} ->
        IO.binwrite(output_device, output)
        {:ok, 0}

      {:error, {exit_code, message}} when is_integer(exit_code) and is_binary(message) ->
        IO.puts(:stderr, message)
        {:error, exit_code}

      {:error, reason} ->
        IO.puts(:stderr, "GitFoil #{operation} error: #{format_error(reason)}")
        {:error, 1}
    end
  end

  # Format errors in a user-friendly way
  defp format_error(%UndefinedFunctionError{module: module, function: function, arity: arity}) do
    "#{module}.#{function}/#{arity} not available (NIF not loaded)"
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_atom(error), do: Atom.to_string(error)
  defp format_error(error), do: inspect(error)
end
