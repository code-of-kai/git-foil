defmodule GitFoil.Core.PasswordProtection do
  @moduledoc """
  Password-based keypair protection using PBKDF2-HMAC-SHA512 + AES-256-GCM.

  Based on Bitwarden's FIPS-140 compliant implementation:
  - KDF: PBKDF2-HMAC-SHA512 with configurable iterations (default: 600,000)
  - AEAD: AES-256-GCM with 12-byte nonce
  - Salt: 32-byte random salt per encryption
  - Iteration count: Stored in file for future flexibility

  File format (v1):

      ┌────────┬────────────┬────────────┬───────────┬─────────┬──────────────┐
      │ Version│ Iterations │    Salt    │   Nonce   │   Tag   │  Ciphertext  │
      │ (1B)   │   (4B BE)  │   (32B)    │   (12B)   │  (16B)  │   (varies)   │
      └────────┴────────────┴────────────┴───────────┴─────────┴──────────────┘

  The iterations field is a 4-byte big-endian unsigned integer storing the
  PBKDF2 iteration count used for this encryption. This enables:
  - Future iteration count increases without breaking old files
  - Per-machine auto-tuning for optimal security/performance balance
  - Self-documenting format (KDF parameters travel with ciphertext)

  The ciphertext contains the serialized Keypair structure.
  """

  alias GitFoil.Core.Types.Keypair

  # Based on OWASP & Bitwarden recommendations (2024)
  @default_pbkdf2_iterations 600_000
  @pbkdf2_hash :sha512
  @salt_bytes 32
  @nonce_bytes 12
  @tag_bytes 16
  @kek_bytes 32  # Key Encryption Key size
  @version 1

  @type encrypted_keypair :: binary()
  @type password :: String.t()

  @doc """
  Encrypts a keypair with a password.

  ## Examples

      iex> {:ok, keypair} = FileKeyStorage.generate_keypair()
      iex> {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "strong-password")
      iex> is_binary(encrypted)
      true
  """
  @spec encrypt_keypair(Keypair.t(), password) ::
          {:ok, encrypted_keypair} | {:error, term()}
  def encrypt_keypair(%Keypair{} = keypair, password)
      when is_binary(password) and byte_size(password) > 0 do
    encrypt_keypair(keypair, password, @default_pbkdf2_iterations)
  end

  @doc """
  Encrypts a keypair with a password using a specific iteration count.

  Allows custom iteration counts for performance tuning while maintaining
  compatibility with the standard encrypt_keypair/2 function.
  """
  @spec encrypt_keypair(Keypair.t(), password, pos_integer()) ::
          {:ok, encrypted_keypair} | {:error, term()}
  def encrypt_keypair(%Keypair{} = keypair, password, iterations)
      when is_binary(password) and byte_size(password) > 0 and iterations > 0 do
    try do
      # 1. Serialize keypair to binary using Erlang term format
      plaintext = :erlang.term_to_binary(keypair)

      # 2. Generate random salt for this encryption
      salt = :crypto.strong_rand_bytes(@salt_bytes)

      # 3. Derive Key Encryption Key (KEK) from password using specified iterations
      kek = derive_kek(password, salt, iterations)

      # 4. Generate random nonce for AES-GCM
      nonce = :crypto.strong_rand_bytes(@nonce_bytes)

      # 5. Encrypt keypair with AES-256-GCM
      aad = <<"GitFoil.PasswordProtection.v", @version>>

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          kek,
          nonce,
          plaintext,
          aad,
          true  # encrypt
        )

      # 6. Securely wipe KEK from memory (best effort)
      :crypto.exor(kek, kek)

      # 7. Build encrypted blob: version || iterations || salt || nonce || tag || ciphertext
      encrypted_blob =
        <<@version::8, iterations::unsigned-big-32, salt::binary-@salt_bytes,
          nonce::binary-@nonce_bytes, tag::binary-@tag_bytes, ciphertext::binary>>

      {:ok, encrypted_blob}
    rescue
      error ->
        {:error, {:encryption_failed, error}}
    end
  end

  @doc """
  Decrypts a keypair with a password.

  ## Examples

      iex> {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")
      iex> {:ok, decrypted} = PasswordProtection.decrypt_keypair(encrypted, "password")
      iex> decrypted == keypair
      true

      iex> PasswordProtection.decrypt_keypair(encrypted, "wrong")
      {:error, :invalid_password}
  """
  @spec decrypt_keypair(encrypted_keypair, password) ::
          {:ok, Keypair.t()} | {:error, :invalid_password | :invalid_format | term()}
  def decrypt_keypair(encrypted_blob, password)
      when is_binary(encrypted_blob) and is_binary(password) do
    try do
      # 1. Parse encrypted blob (now includes iterations field)
      <<version::8, iterations::unsigned-big-32, salt::binary-@salt_bytes,
        nonce::binary-@nonce_bytes, tag::binary-@tag_bytes, ciphertext::binary>> =
        encrypted_blob

      # 2. Verify version
      unless version == @version do
        raise "Unsupported encryption version: #{version}"
      end

      # 3. Validate iteration count (basic sanity check)
      unless iterations > 0 and iterations <= 10_000_000 do
        raise "Invalid iteration count: #{iterations}"
      end

      # 4. Re-derive KEK using same salt, password, and iteration count from file
      kek = derive_kek(password, salt, iterations)

      # 5. Attempt to decrypt and verify authentication tag
      aad = <<"GitFoil.PasswordProtection.v", @version>>

      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             kek,
             nonce,
             ciphertext,
             aad,
             tag,
             false  # decrypt
           ) do
        plaintext when is_binary(plaintext) ->
          # Success! Authentication passed, deserialize keypair
          keypair = :erlang.binary_to_term(plaintext)
          {:ok, keypair}

        _error ->
          # Authentication failed - wrong password or tampered data
          {:error, :invalid_password}
      end
    rescue
      MatchError ->
        # Blob format is invalid (truncated, wrong size, etc.)
        {:error, :invalid_format}

      RuntimeError ->
        # Version or iteration validation raised - format issue
        {:error, :invalid_format}

      _error ->
        # Other errors (deserialization, etc.)
        {:error, :invalid_password}
    end
  end

  # Derives a Key Encryption Key from password and salt using PBKDF2.
  # Uses PBKDF2-HMAC-SHA512 with configurable iterations.
  # Execution time: ~100ms on modern CPU at 600K iterations (acceptable for UX).
  @spec derive_kek(password, binary(), pos_integer()) :: binary()
  defp derive_kek(password, salt, iterations) do
    :crypto.pbkdf2_hmac(
      @pbkdf2_hash,
      password,
      salt,
      iterations,
      @kek_bytes
    )
  end

  @doc """
  Benchmarks PBKDF2 performance on this machine.

  Useful for tuning iteration count or diagnosing performance issues.

  ## Examples

      iex> PasswordProtection.benchmark()
      PBKDF2-HMAC-SHA512 (600,000 iterations): 102.4ms
      :ok
  """
  def benchmark do
    benchmark(@default_pbkdf2_iterations)
  end

  @doc """
  Benchmarks PBKDF2 performance with a specific iteration count.
  """
  def benchmark(iterations) when iterations > 0 do
    password = "test-password-for-benchmarking"
    salt = :crypto.strong_rand_bytes(@salt_bytes)

    {time_us, _result} =
      :timer.tc(fn ->
        derive_kek(password, salt, iterations)
      end)

    time_ms = time_us / 1000

    IO.puts(
      "PBKDF2-HMAC-SHA512 (#{iterations} iterations): #{Float.round(time_ms, 1)}ms"
    )

    :ok
  end

  @doc """
  Validates password strength (basic check).

  Returns {:ok, password} or {:error, reason}.
  """
  @spec validate_password(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_password(password) when is_binary(password) do
    cond do
      String.length(password) < 8 ->
        {:error, :password_too_short}

      String.length(password) > 1024 ->
        {:error, :password_too_long}

      true ->
        {:ok, password}
    end
  end
end
