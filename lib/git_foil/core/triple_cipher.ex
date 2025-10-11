defmodule GitFoil.Core.TripleCipher do
  @moduledoc """
  Three-layer authenticated encryption with provider injection.

  **Architecture (v2.0 - Quantum-Resistant):**
  - Layer 1: OpenSSL AES-256-GCM (32-byte key, 12-byte IV)
  - Layer 2: Rust Ascon-128a (16-byte key, 16-byte nonce)
  - Layer 3: OpenSSL ChaCha20-Poly1305 (32-byte key, 12-byte nonce)

  **Defense in Depth:**
  - Algorithm diversity: AES (block cipher), Ascon (sponge), ChaCha20 (stream)
  - Implementation diversity: OpenSSL (C/assembly) + Rust (memory-safe)
  - Post-quantum design: Ascon-128a (NIST Lightweight Crypto winner)

  **Deterministic:**
  Same keys + plaintext → same ciphertext (required for Git)
  Each layer uses deterministic IV/nonce derived from key + layer number.
  """

  alias GitFoil.Core.Types.DerivedKeys

  @doc """
  Encrypts data through three layers.

  ## Parameters
  - plaintext: Data to encrypt
  - derived_keys: Three independent 32-byte keys
  - layer1_provider: CryptoProvider for layer 1 (e.g., OpenSSLCrypto)
  - layer2_provider: CryptoProvider for layer 2 (e.g., LibsodiumCrypto)
  - layer3_provider: CryptoProvider for layer 3 (e.g., LibsodiumCrypto)
  - file_path: File path for AAD context

  ## Returns
  - {:ok, ciphertext, layer1_tag, layer2_tag, layer3_tag}
  - {:error, reason}
  """
  @spec encrypt(
          binary(),
          DerivedKeys.t(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary(), binary(), binary(), binary()} | {:error, term()}
  def encrypt(
        plaintext,
        %DerivedKeys{
          layer1_key: key1,
          layer2_key: key2,
          layer3_key: key3
        },
        layer1_provider,
        layer2_provider,
        layer3_provider,
        file_path
      )
      when is_binary(plaintext) and is_binary(file_path) do
    aad = file_path

    # Layer 1: AES-256-GCM (12-byte IV)
    # Layer 2: Ascon-128a (16-byte nonce)
    # Layer 3: ChaCha20-Poly1305 (12-byte nonce)
    with {:ok, iv1} <- derive_deterministic_iv(key1, 1, 12),
         {:ok, ciphertext1, tag1} <-
           layer1_provider.aes_256_gcm_encrypt(key1, iv1, plaintext, aad),
         {:ok, nonce2} <- derive_deterministic_iv(key2, 2, 16),
         {:ok, ciphertext2, tag2} <-
           layer2_provider.ascon_128a_encrypt(key2, nonce2, ciphertext1, aad),
         {:ok, nonce3} <- derive_deterministic_iv(key3, 3, 12),
         {:ok, ciphertext3, tag3} <-
           layer3_provider.chacha20_poly1305_encrypt(key3, nonce3, ciphertext2, aad) do
      {:ok, ciphertext3, tag1, tag2, tag3}
    end
  end

  @doc """
  Decrypts data through three layers (reverse order).

  ## Parameters
  - ciphertext: Encrypted data
  - tags: {layer1_tag, layer2_tag, layer3_tag}
  - derived_keys: Three independent 32-byte keys
  - layer1_provider: CryptoProvider for layer 1
  - layer2_provider: CryptoProvider for layer 2
  - layer3_provider: CryptoProvider for layer 3
  - file_path: File path for AAD context

  ## Returns
  - {:ok, plaintext}
  - {:error, reason} (including :authentication_failed if tags don't match)
  """
  @spec decrypt(
          binary(),
          {binary(), binary(), binary()},
          DerivedKeys.t(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(
        ciphertext,
        {tag1, tag2, tag3},
        %DerivedKeys{
          layer1_key: key1,
          layer2_key: key2,
          layer3_key: key3
        },
        layer1_provider,
        layer2_provider,
        layer3_provider,
        file_path
      )
      when is_binary(ciphertext) and is_binary(file_path) do
    aad = file_path

    # Decrypt in reverse order: Layer 3 → Layer 2 → Layer 1
    # Layer 3: ChaCha20-Poly1305 (12-byte nonce)
    # Layer 2: Ascon-128a (16-byte nonce)
    # Layer 1: AES-256-GCM (12-byte IV)
    with {:ok, nonce3} <- derive_deterministic_iv(key3, 3, 12),
         {:ok, ciphertext2} <-
           layer3_provider.chacha20_poly1305_decrypt(key3, nonce3, ciphertext, tag3, aad),
         {:ok, nonce2} <- derive_deterministic_iv(key2, 2, 16),
         {:ok, ciphertext1} <-
           layer2_provider.ascon_128a_decrypt(key2, nonce2, ciphertext2, tag2, aad),
         {:ok, iv1} <- derive_deterministic_iv(key1, 1, 12),
         {:ok, plaintext} <-
           layer1_provider.aes_256_gcm_decrypt(key1, iv1, ciphertext1, tag1, aad) do
      {:ok, plaintext}
    end
  end

  # Derives deterministic IV/nonce from key + layer number
  # Supports variable-length output (12 bytes for AES/ChaCha20, 16 bytes for Ascon)
  #
  # Cannot use content because during decryption we don't have the input content
  # (chicken-and-egg problem: need IV to decrypt, but IV depends on decrypted content)
  # This ensures same key + layer → same IV/nonce (required for Git determinism)
  defp derive_deterministic_iv(key, layer_num, size) do
    try do
      # Hash key + layer number to generate deterministic IV/nonce
      # Don't use content - it creates chicken-and-egg problem during decryption
      hash_input = key <> <<layer_num>>
      iv = :crypto.hash(:sha3_256, hash_input) |> binary_part(0, size)
      {:ok, iv}
    rescue
      error -> {:error, {:iv_derivation_failed, error}}
    end
  end
end
