defmodule GitFoil.Adapters.OpenSSLCrypto do
  @moduledoc """
  OpenSSL-based crypto provider using Erlang :crypto.

  **Default Implementation:**
  Uses the battle-tested OpenSSL library via Erlang's built-in :crypto module.
  This is the standard crypto implementation shipped with BEAM.

  **Performance:**
  - AES-256-GCM: ~1-2 GB/s (with AES-NI CPU support)
  - ChaCha20-Poly1305: ~500-800 MB/s

  **Security:**
  All operations use authenticated encryption (AEAD).
  OpenSSL is widely audited and considered the industry standard.
  """

  @behaviour GitFoil.Ports.CryptoProvider

  @impl true
  def aes_256_gcm_encrypt(key, iv, plaintext, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(plaintext) and
             is_binary(aad) do
    try do
      # OpenSSL AES-256-GCM via Erlang :crypto
      {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true)
      {:ok, ciphertext, tag}
    rescue
      error ->
        {:error, {:openssl_error, error}}
    end
  end

  def aes_256_gcm_encrypt(_key, _iv, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def aes_256_gcm_decrypt(key, iv, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(ciphertext) and
             byte_size(tag) == 16 and is_binary(aad) do
    try do
      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        :error ->
          {:error, :authentication_failed}
      end
    rescue
      error ->
        {:error, {:openssl_error, error}}
    end
  end

  def aes_256_gcm_decrypt(_key, _iv, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def chacha20_poly1305_encrypt(key, iv, plaintext, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(plaintext) and
             is_binary(aad) do
    try do
      # OpenSSL ChaCha20-Poly1305 via Erlang :crypto
      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:chacha20_poly1305, key, iv, plaintext, aad, true)

      {:ok, ciphertext, tag}
    rescue
      error ->
        {:error, {:openssl_error, error}}
    end
  end

  def chacha20_poly1305_encrypt(_key, _iv, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def chacha20_poly1305_decrypt(key, iv, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(ciphertext) and
             byte_size(tag) == 16 and is_binary(aad) do
    try do
      case :crypto.crypto_one_time_aead(
             :chacha20_poly1305,
             key,
             iv,
             ciphertext,
             aad,
             tag,
             false
           ) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        :error ->
          {:error, :authentication_failed}
      end
    rescue
      error ->
        {:error, {:openssl_error, error}}
    end
  end

  def chacha20_poly1305_decrypt(_key, _iv, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # Stub implementations for algorithms not supported by OpenSSL
  @impl true
  def ascon_128a_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def ascon_128a_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def aegis_256_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def aegis_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def schwaemm256_256_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def schwaemm256_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def deoxys_ii_256_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :not_implemented}
  end

  @impl true
  def deoxys_ii_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :not_implemented}
  end
end
