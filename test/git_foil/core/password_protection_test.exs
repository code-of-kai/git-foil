defmodule GitFoil.Core.PasswordProtectionTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias GitFoil.Core.PasswordProtection
  alias GitFoil.Adapters.FileKeyStorage

  describe "encrypt_keypair/2" do
    test "successfully encrypts a keypair with valid password" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      password = "secure-test-password"

      assert {:ok, encrypted_blob} = PasswordProtection.encrypt_keypair(keypair, password)
      assert is_binary(encrypted_blob)
      # Minimum size: version(1) + iterations(4) + salt(32) + nonce(12) + tag(16) + ciphertext
      assert byte_size(encrypted_blob) > 65
    end

    test "encrypted blob has correct version byte" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted_blob} = PasswordProtection.encrypt_keypair(keypair, "password")

      <<version::8, _rest::binary>> = encrypted_blob
      assert version == 1
    end

    test "returns error for invalid parameters" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()

      # Empty password should raise FunctionClauseError (guard fails)
      assert_raise FunctionClauseError, fn ->
        PasswordProtection.encrypt_keypair(keypair, "")
      end

      # Nil keypair should raise FunctionClauseError (guard fails)
      assert_raise FunctionClauseError, fn ->
        PasswordProtection.encrypt_keypair(nil, "password")
      end
    end

    test "produces different ciphertext for same keypair (salt randomization)" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      password = "test-password"

      {:ok, encrypted1} = PasswordProtection.encrypt_keypair(keypair, password)
      {:ok, encrypted2} = PasswordProtection.encrypt_keypair(keypair, password)

      # Same keypair and password should produce different ciphertext due to random salt
      assert encrypted1 != encrypted2
    end

    test "different passwords produce different ciphertext" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()

      {:ok, encrypted1} = PasswordProtection.encrypt_keypair(keypair, "password1")
      {:ok, encrypted2} = PasswordProtection.encrypt_keypair(keypair, "password2")

      assert encrypted1 != encrypted2
    end
  end

  describe "decrypt_keypair/2" do
    test "successfully decrypts keypair with correct password" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      password = "secure-test-password"

      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, password)
      assert {:ok, decrypted} = PasswordProtection.decrypt_keypair(encrypted, password)

      # Verify decrypted keypair matches original
      assert decrypted.classical_public == keypair.classical_public
      assert decrypted.classical_secret == keypair.classical_secret
      assert decrypted.pq_public == keypair.pq_public
      assert decrypted.pq_secret == keypair.pq_secret
    end

    test "fails to decrypt with wrong password" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()

      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "correct-password")
      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_keypair(encrypted, "wrong-password")
    end

    test "fails to decrypt with empty password when encrypted with non-empty" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()

      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")
      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_keypair(encrypted, "")
    end

    test "fails to decrypt corrupted ciphertext" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")

      # Corrupt the ciphertext by flipping a bit
      <<version, salt::binary-32, nonce::binary-12, tag::binary-16, ciphertext::binary>> =
        encrypted

      corrupted_ciphertext = flip_random_bit(ciphertext)

      corrupted =
        <<version, salt::binary-32, nonce::binary-12, tag::binary-16,
          corrupted_ciphertext::binary>>

      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_keypair(corrupted, "password")
    end

    test "fails to decrypt with tampered authentication tag" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")

      # Tamper with the authentication tag
      <<version, salt::binary-32, nonce::binary-12, _tag::binary-16, ciphertext::binary>> =
        encrypted

      fake_tag = :crypto.strong_rand_bytes(16)
      tampered = <<version, salt::binary-32, nonce::binary-12, fake_tag::binary, ciphertext::binary>>

      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_keypair(tampered, "password")
    end

    test "fails to decrypt blob with invalid version" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")

      # Change version byte to unsupported version
      <<_version, rest::binary>> = encrypted
      invalid_version_blob = <<99, rest::binary>>

      # Invalid version is a format error
      assert {:error, :invalid_format} =
               PasswordProtection.decrypt_keypair(invalid_version_blob, "password")
    end

    test "handles truncated encrypted blob gracefully" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")

      # Truncate the blob
      truncated = binary_part(encrypted, 0, 50)

      # Truncated blob is malformed - returns :invalid_format
      assert {:error, :invalid_format} =
               PasswordProtection.decrypt_keypair(truncated, "password")
    end

    test "fails to decrypt with tampered salt" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")

      # Tamper with the salt (bytes 5-36, after version and iterations)
      <<version, iterations::unsigned-big-32, _salt::binary-32, rest::binary>> = encrypted
      fake_salt = :crypto.strong_rand_bytes(32)
      tampered = <<version, iterations::unsigned-big-32, fake_salt::binary, rest::binary>>

      # Wrong salt means wrong derived key, authentication will fail
      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_keypair(tampered, "password")
    end

    test "fails to decrypt with tampered nonce" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, "password")

      # Tamper with the nonce (bytes 37-48, after version/iterations/salt)
      <<version, iterations::unsigned-big-32, salt::binary-32, _nonce::binary-12, rest::binary>> =
        encrypted

      fake_nonce = :crypto.strong_rand_bytes(12)

      tampered =
        <<version, iterations::unsigned-big-32, salt::binary, fake_nonce::binary, rest::binary>>

      # Wrong nonce means wrong decryption, authentication will fail
      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_keypair(tampered, "password")
    end
  end

  describe "validate_password/1" do
    test "accepts password with minimum length" do
      assert {:ok, "12345678"} = PasswordProtection.validate_password("12345678")
    end

    test "accepts password with reasonable length" do
      password = String.duplicate("a", 50)
      assert {:ok, ^password} = PasswordProtection.validate_password(password)
    end

    test "rejects password that is too short" do
      assert {:error, :password_too_short} = PasswordProtection.validate_password("short")
      assert {:error, :password_too_short} = PasswordProtection.validate_password("1234567")
    end

    test "rejects password that is too long" do
      password = String.duplicate("a", 1025)
      assert {:error, :password_too_long} = PasswordProtection.validate_password(password)
    end

    test "accepts password at maximum length boundary" do
      password = String.duplicate("a", 1024)
      assert {:ok, ^password} = PasswordProtection.validate_password(password)
    end
  end

  describe "round-trip encryption/decryption" do
    test "works with unicode password" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      password = "pāsswōrd™🔐"

      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, password)
      assert {:ok, decrypted} = PasswordProtection.decrypt_keypair(encrypted, password)

      assert decrypted.classical_secret == keypair.classical_secret
    end

    test "works with password containing special characters" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      password = "P@ssw0rd!#$%^&*()_+-=[]{}|;':\",./<>?"

      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, password)
      assert {:ok, decrypted} = PasswordProtection.decrypt_keypair(encrypted, password)

      assert decrypted.pq_secret == keypair.pq_secret
    end

    test "works with very long password" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      password = String.duplicate("long", 200)

      {:ok, encrypted} = PasswordProtection.encrypt_keypair(keypair, password)
      assert {:ok, decrypted} = PasswordProtection.decrypt_keypair(encrypted, password)

      assert decrypted.pq_public == keypair.pq_public
    end

    test "multiple independent encryptions can all be decrypted" do
      {:ok, keypair1} = FileKeyStorage.generate_keypair()
      {:ok, keypair2} = FileKeyStorage.generate_keypair()

      password1 = "password-one"
      password2 = "password-two"

      {:ok, encrypted1} = PasswordProtection.encrypt_keypair(keypair1, password1)
      {:ok, encrypted2} = PasswordProtection.encrypt_keypair(keypair2, password2)

      {:ok, decrypted1} = PasswordProtection.decrypt_keypair(encrypted1, password1)
      {:ok, decrypted2} = PasswordProtection.decrypt_keypair(encrypted2, password2)

      assert decrypted1.classical_secret == keypair1.classical_secret
      assert decrypted2.classical_secret == keypair2.classical_secret
    end
  end

  describe "benchmark/0" do
    test "benchmark completes successfully" do
      # Just verify it doesn't crash
      assert :ok = PasswordProtection.benchmark()
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp flip_random_bit(binary) when byte_size(binary) > 0 do
    byte_position = :rand.uniform(byte_size(binary)) - 1
    bit_position = :rand.uniform(8) - 1

    <<before::binary-size(byte_position), byte::8, after_::binary>> = binary

    flipped_byte = Bitwise.bxor(byte, 1 <<< bit_position)

    <<before::binary, flipped_byte::8, after_::binary>>
  end
end
