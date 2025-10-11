defmodule GitFoil.Adapters.LibsodiumCrypto do
  @moduledoc """
  Libsodium-based crypto provider using enacl NIF.

  **STATUS: NOT CURRENTLY USABLE**
  enacl (libsodium bindings) is not compatible with OTP 28 yet.
  This adapter is kept for when compatibility is restored.

  **Alternative Implementation for Defense in Depth:**
  Provides the same AEAD algorithms as OpenSSL but through libsodium,
  a completely different codebase. If OpenSSL has a vulnerability,
  libsodium likely doesn't have the same bug.

  **Performance:**
  - ChaCha20-Poly1305: ~500 MB/s (comparable to OpenSSL)
  - AES-256-GCM: ~400 MB/s (if CPU has AES-NI)

  **Security:**
  All operations use authenticated encryption (AEAD).
  libsodium is audited and widely trusted (NaCl/libsodium lineage).
  """

  # Suppress warnings for :enacl module (not available in OTP 28)
  @compile {:no_warn_undefined, :enacl}

  # @behaviour GitFoil.Ports.CryptoProvider

  # @impl true
  def aes_256_gcm_encrypt(key, iv, plaintext, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(plaintext) and
             is_binary(aad) do
    try do
      # libsodium AES-256-GCM (requires CPU with AES-NI support)
      {ciphertext, tag} = :enacl.aead_aes256gcm_encrypt(plaintext, aad, iv, key)
      {:ok, ciphertext, tag}
    rescue
      error ->
        {:error, {:libsodium_error, error}}
    end
  end

  def aes_256_gcm_encrypt(_key, _iv, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  # @impl true
  def aes_256_gcm_decrypt(key, iv, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(ciphertext) and
             byte_size(tag) == 16 and is_binary(aad) do
    try do
      # Combine ciphertext and tag for libsodium
      combined = ciphertext <> tag

      case :enacl.aead_aes256gcm_decrypt(combined, aad, iv, key) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        {:error, :failed_verification} ->
          {:error, :authentication_failed}
      end
    rescue
      error ->
        {:error, {:libsodium_error, error}}
    end
  end

  def aes_256_gcm_decrypt(_key, _iv, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # @impl true
  def chacha20_poly1305_encrypt(key, iv, plaintext, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(plaintext) and
             is_binary(aad) do
    try do
      # libsodium ChaCha20-Poly1305 (IETF version with 96-bit nonce)
      {ciphertext, tag} = :enacl.aead_chacha20poly1305_ietf_encrypt(plaintext, aad, iv, key)
      {:ok, ciphertext, tag}
    rescue
      error ->
        {:error, {:libsodium_error, error}}
    end
  end

  def chacha20_poly1305_encrypt(_key, _iv, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  # @impl true
  def chacha20_poly1305_decrypt(key, iv, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(ciphertext) and
             byte_size(tag) == 16 and is_binary(aad) do
    try do
      # Combine ciphertext and tag for libsodium
      combined = ciphertext <> tag

      case :enacl.aead_chacha20poly1305_ietf_decrypt(combined, aad, iv, key) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        {:error, :failed_verification} ->
          {:error, :authentication_failed}
      end
    rescue
      error ->
        {:error, {:libsodium_error, error}}
    end
  end

  def chacha20_poly1305_decrypt(_key, _iv, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # Stub implementations for Ascon (not supported by libsodium)
  # @impl true
  def ascon_128a_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :not_implemented}
  end

  # @impl true
  def ascon_128a_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :not_implemented}
  end
end
