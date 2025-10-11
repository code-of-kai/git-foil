defmodule GitFoil.Core.EncryptionEngine do
  @moduledoc """
  Orchestrates the complete encryption/decryption pipeline.

  **Pipeline (v3.0):**
  1. Key Derivation: Master key → Six layer-specific keys
  2. Six-Layer Cipher: Six-layer AEAD encryption
  3. Serialization: Pack ciphertext + tags into wire format

  **Wire Format v3.0:**
  ```
  [version:1][tag1:16][tag2:32][tag3:32][tag4:16][tag5:16][tag6:16][ciphertext:variable]
  ```

  **Tag sizes:**
  - tag1: 16 bytes (AES-256-GCM)
  - tag2: 32 bytes (AEGIS-256)
  - tag3: 32 bytes (Schwaemm256-256)
  - tag4: 16 bytes (Deoxys-II-256)
  - tag5: 16 bytes (Ascon-128a)
  - tag6: 16 bytes (ChaCha20-Poly1305)

  Total overhead: 129 bytes per file

  Version byte allows for future algorithm changes.
  """

  alias GitFoil.Core.{KeyDerivation, SixLayerCipher}
  alias GitFoil.Core.Types.{EncryptionKey, EncryptedBlob}

  @version 3

  @doc """
  Encrypts plaintext using six-layer encryption.

  ## Parameters
  - plaintext: Data to encrypt
  - master_key: 32-byte master encryption key
  - layer1_provider: CryptoProvider module for AES-256-GCM
  - layer2_provider: CryptoProvider module for AEGIS-256
  - layer3_provider: CryptoProvider module for Schwaemm256-256
  - layer4_provider: CryptoProvider module for Deoxys-II-256
  - layer5_provider: CryptoProvider module for Ascon-128a
  - layer6_provider: CryptoProvider module for ChaCha20-Poly1305
  - file_path: File path for key derivation context

  ## Returns
  - {:ok, %EncryptedBlob{}} with serialized encrypted data
  - {:error, reason}
  """
  @spec encrypt(
          binary(),
          EncryptionKey.t(),
          module(),
          module(),
          module(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, EncryptedBlob.t()} | {:error, term()}
  def encrypt(
        plaintext,
        master_key,
        layer1_provider,
        layer2_provider,
        layer3_provider,
        layer4_provider,
        layer5_provider,
        layer6_provider,
        file_path
      )
      when is_binary(plaintext) and is_binary(file_path) do
    with {:ok, derived_keys} <- KeyDerivation.derive_keys(master_key, file_path),
         {:ok, ciphertext, tag1, tag2, tag3, tag4, tag5, tag6} <-
           SixLayerCipher.encrypt(
             plaintext,
             derived_keys,
             layer1_provider,
             layer2_provider,
             layer3_provider,
             layer4_provider,
             layer5_provider,
             layer6_provider,
             file_path
           ) do
      blob = %EncryptedBlob{
        version: @version,
        tag1: tag1,
        tag2: tag2,
        tag3: tag3,
        tag4: tag4,
        tag5: tag5,
        tag6: tag6,
        ciphertext: ciphertext
      }

      {:ok, blob}
    end
  end

  @doc """
  Decrypts an encrypted blob.

  ## Parameters
  - blob: %EncryptedBlob{} with version, tags, and ciphertext
  - master_key: 32-byte master encryption key
  - layer1_provider: CryptoProvider module for AES-256-GCM
  - layer2_provider: CryptoProvider module for AEGIS-256
  - layer3_provider: CryptoProvider module for Schwaemm256-256
  - layer4_provider: CryptoProvider module for Deoxys-II-256
  - layer5_provider: CryptoProvider module for Ascon-128a
  - layer6_provider: CryptoProvider module for ChaCha20-Poly1305
  - file_path: File path for key derivation context

  ## Returns
  - {:ok, plaintext}
  - {:error, reason}
  """
  @spec decrypt(
          EncryptedBlob.t(),
          EncryptionKey.t(),
          module(),
          module(),
          module(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(
        %EncryptedBlob{
          version: version,
          tag1: tag1,
          tag2: tag2,
          tag3: tag3,
          tag4: tag4,
          tag5: tag5,
          tag6: tag6,
          ciphertext: ciphertext
        },
        master_key,
        layer1_provider,
        layer2_provider,
        layer3_provider,
        layer4_provider,
        layer5_provider,
        layer6_provider,
        file_path
      )
      when is_binary(file_path) do
    with :ok <- validate_version(version),
         {:ok, derived_keys} <- KeyDerivation.derive_keys(master_key, file_path),
         {:ok, plaintext} <-
           SixLayerCipher.decrypt(
             ciphertext,
             {tag1, tag2, tag3, tag4, tag5, tag6},
             derived_keys,
             layer1_provider,
             layer2_provider,
             layer3_provider,
             layer4_provider,
             layer5_provider,
             layer6_provider,
             file_path
           ) do
      {:ok, plaintext}
    end
  end

  @doc """
  Serializes an encrypted blob to binary wire format.

  Format v3.0: [version:1][tag1:16][tag2:32][tag3:32][tag4:16][tag5:16][tag6:16][ciphertext:variable]

  Total overhead: 129 bytes (1 + 16 + 32 + 32 + 16 + 16 + 16)
  """
  @spec serialize(EncryptedBlob.t()) :: binary()
  def serialize(%EncryptedBlob{
        version: version,
        tag1: tag1,
        tag2: tag2,
        tag3: tag3,
        tag4: tag4,
        tag5: tag5,
        tag6: tag6,
        ciphertext: ciphertext
      }) do
    <<version::8, tag1::binary-16, tag2::binary-32, tag3::binary-32, tag4::binary-16,
      tag5::binary-16, tag6::binary-16, ciphertext::binary>>
  end

  @doc """
  Deserializes binary wire format to encrypted blob.

  Format v3.0: [version:1][tag1:16][tag2:32][tag3:32][tag4:16][tag5:16][tag6:16][ciphertext:variable]
  """
  @spec deserialize(binary()) :: {:ok, EncryptedBlob.t()} | {:error, term()}
  def deserialize(
        <<version::8, tag1::binary-16, tag2::binary-32, tag3::binary-32, tag4::binary-16,
          tag5::binary-16, tag6::binary-16, ciphertext::binary>>
      ) do
    blob = %EncryptedBlob{
      version: version,
      tag1: tag1,
      tag2: tag2,
      tag3: tag3,
      tag4: tag4,
      tag5: tag5,
      tag6: tag6,
      ciphertext: ciphertext
    }

    {:ok, blob}
  end

  def deserialize(_invalid) do
    {:error, :invalid_blob_format}
  end

  # Validates the version byte
  defp validate_version(@version), do: :ok
  defp validate_version(v), do: {:error, {:unsupported_version, v}}
end
