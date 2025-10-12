defmodule GitFoil.Adapters.PasswordProtectedKeyStorageTest do
  use ExUnit.Case, async: false

  alias GitFoil.Adapters.PasswordProtectedKeyStorage
  alias GitFoil.Core.Types.{Keypair, EncryptionKey}

  @test_dir "test_tmp/password_protected_storage"

  setup do
    # Clean up test directory before each test
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Change to test directory
    original_dir = File.cwd!()
    File.cd!(@test_dir)

    # Initialize git repo in test directory
    System.cmd("git", ["init"], stderr_to_stdout: true)

    # Clean up password from process dictionary
    PasswordProtectedKeyStorage.clear_password()

    on_exit(fn ->
      File.cd!(original_dir)
      File.rm_rf!(@test_dir)
      PasswordProtectedKeyStorage.clear_password()
    end)

    :ok
  end

  describe "generate_keypair/0" do
    test "successfully generates a new keypair" do
      assert {:ok, %Keypair{} = keypair} = PasswordProtectedKeyStorage.generate_keypair()

      # Verify keypair has all required fields
      assert byte_size(keypair.classical_public) == 32
      assert byte_size(keypair.classical_secret) == 32
      assert is_binary(keypair.pq_public)
      assert is_binary(keypair.pq_secret)
    end

    test "generates different keypairs on each call" do
      {:ok, keypair1} = PasswordProtectedKeyStorage.generate_keypair()
      {:ok, keypair2} = PasswordProtectedKeyStorage.generate_keypair()

      # Keypairs should be different
      assert keypair1.classical_secret != keypair2.classical_secret
      assert keypair1.pq_secret != keypair2.pq_secret
    end
  end

  describe "store_keypair_with_password/2" do
    test "successfully stores encrypted keypair" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
      password = "secure-test-password"

      assert :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password)

      # Verify file was created
      assert File.exists?(".git/git_foil/master.key.enc")
    end

    test "creates encrypted file with secure permissions" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "password")

      # Check file permissions (0600 = owner read/write only)
      %{mode: mode} = File.stat!(".git/git_foil/master.key.enc")
      # Convert to octal string and check last 3 digits
      octal_mode = Integer.to_string(mode, 8)
      perms = String.slice(octal_mode, -3, 3)

      assert perms == "600"
    end

    test "rejects password that is too short" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      assert {:error, "Password must be at least 8 characters"} =
               PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "short")
    end

    test "rejects password that is too long" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
      password = String.duplicate("a", 1025)

      assert {:error, "Password must be less than 1024 characters"} =
               PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password)
    end

    test "overwrites existing encrypted keypair" do
      {:ok, keypair1} = PasswordProtectedKeyStorage.generate_keypair()
      {:ok, keypair2} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair1, "password1")
      original_content = File.read!(".git/git_foil/master.key.enc")

      # Small delay to ensure mtime changes
      Process.sleep(10)

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair2, "password2")
      new_content = File.read!(".git/git_foil/master.key.enc")

      # File should be updated with different content
      assert new_content != original_content

      # Should be able to decrypt with new password
      assert {:ok, decrypted} =
               PasswordProtectedKeyStorage.retrieve_keypair_with_password("password2")

      assert decrypted.classical_secret == keypair2.classical_secret
    end
  end

  describe "retrieve_keypair_with_password/1" do
    test "successfully retrieves encrypted keypair" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
      password = "test-password"

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password)

      assert {:ok, retrieved} =
               PasswordProtectedKeyStorage.retrieve_keypair_with_password(password)

      assert retrieved.classical_public == keypair.classical_public
      assert retrieved.classical_secret == keypair.classical_secret
      assert retrieved.pq_public == keypair.pq_public
      assert retrieved.pq_secret == keypair.pq_secret
    end

    test "fails with wrong password" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "correct-password")

      assert {:error, :invalid_password} =
               PasswordProtectedKeyStorage.retrieve_keypair_with_password("wrong-password")
    end

    test "returns error when no encrypted keypair exists" do
      assert {:error, :not_found} =
               PasswordProtectedKeyStorage.retrieve_keypair_with_password("password")
    end
  end

  describe "store_keypair/1 with process dictionary" do
    test "successfully stores keypair when password is set" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      PasswordProtectedKeyStorage.set_password("test-password")

      assert :ok = PasswordProtectedKeyStorage.store_keypair(keypair)
      assert File.exists?(".git/git_foil/master.key.enc")
    end

    test "returns error when password is not set" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      assert {:error, message} = PasswordProtectedKeyStorage.store_keypair(keypair)
      assert message =~ "Password required"
    end
  end

  describe "retrieve_keypair/0 with process dictionary" do
    test "successfully retrieves keypair when password is set" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
      password = "test-password"

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password)

      PasswordProtectedKeyStorage.set_password(password)

      assert {:ok, retrieved} = PasswordProtectedKeyStorage.retrieve_keypair()
      assert retrieved.classical_secret == keypair.classical_secret
    end

    test "returns error when password is not set" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "password")

      assert {:error, message} = PasswordProtectedKeyStorage.retrieve_keypair()
      assert message =~ "Password required"
    end
  end

  describe "set_password/1 and clear_password/0" do
    test "set_password stores password in process dictionary" do
      assert :ok = PasswordProtectedKeyStorage.set_password("test")
      assert Process.get(:gitfoil_password) == "test"
    end

    test "clear_password removes password from process dictionary" do
      PasswordProtectedKeyStorage.set_password("test")
      assert Process.get(:gitfoil_password) == "test"

      assert :ok = PasswordProtectedKeyStorage.clear_password()
      assert Process.get(:gitfoil_password) == nil
    end
  end

  describe "derive_master_key_with_password/1" do
    test "derives consistent master key from stored keypair" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
      password = "test-password"

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password)

      assert {:ok, %EncryptionKey{} = key1} =
               PasswordProtectedKeyStorage.derive_master_key_with_password(password)

      assert {:ok, %EncryptionKey{} = key2} =
               PasswordProtectedKeyStorage.derive_master_key_with_password(password)

      # Same password should derive same key
      assert key1.key == key2.key
      assert byte_size(key1.key) == 32
    end

    test "fails to derive key with wrong password" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "correct-password")

      assert {:error, :invalid_password} =
               PasswordProtectedKeyStorage.derive_master_key_with_password("wrong-password")
    end
  end

  describe "derive_master_key/0 with process dictionary" do
    test "derives master key when password is set" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
      password = "test-password"

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password)
      PasswordProtectedKeyStorage.set_password(password)

      assert {:ok, %EncryptionKey{} = key} =
               PasswordProtectedKeyStorage.derive_master_key()

      assert byte_size(key.key) == 32
    end

    test "returns error when password is not set" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "password")

      assert {:error, message} = PasswordProtectedKeyStorage.derive_master_key()
      assert message =~ "Password required"
    end

    test "returns error when not initialized" do
      PasswordProtectedKeyStorage.set_password("password")

      assert {:error, :not_initialized} = PasswordProtectedKeyStorage.derive_master_key()
    end
  end

  describe "initialized?/0" do
    test "returns false when no encrypted keypair exists" do
      refute PasswordProtectedKeyStorage.initialized?()
    end

    test "returns true when encrypted keypair exists" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "password")

      assert PasswordProtectedKeyStorage.initialized?()
    end
  end

  describe "delete_keypair/0" do
    test "successfully deletes encrypted keypair" do
      {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()

      :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, "password")
      assert File.exists?(".git/git_foil/master.key.enc")

      assert :ok = PasswordProtectedKeyStorage.delete_keypair()
      refute File.exists?(".git/git_foil/master.key.enc")
    end

    test "returns ok when no keypair exists" do
      assert :ok = PasswordProtectedKeyStorage.delete_keypair()
    end
  end

  describe "file-specific key operations" do
    test "store_file_key/2 returns not_implemented" do
      key = EncryptionKey.new(:crypto.strong_rand_bytes(32))

      assert {:error, :not_implemented} =
               PasswordProtectedKeyStorage.store_file_key("path/to/file", key)
    end

    test "retrieve_file_key/1 returns not_found" do
      assert {:error, :not_found} =
               PasswordProtectedKeyStorage.retrieve_file_key("path/to/file")
    end

    test "delete_file_key/1 returns ok" do
      assert :ok = PasswordProtectedKeyStorage.delete_file_key("path/to/file")
    end
  end
end
