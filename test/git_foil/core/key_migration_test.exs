defmodule GitFoil.Core.KeyMigrationTest do
  use ExUnit.Case, async: false

  alias GitFoil.Adapters.{FileKeyStorage, PasswordProtectedKeyStorage}
  alias GitFoil.Core.KeyMigration
  alias GitFoil.TestSupport.TempRepo

  @password "super-secure-password"

  setup do
    repo = TempRepo.create!()

    on_exit(fn ->
      File.rm_rf!(repo)
      Process.delete(:gitfoil_cached_master_key)
      Process.delete(:gitfoil_cached_keypair)
    end)

    {:ok, repo: repo}
  end

  describe "encrypt_plaintext_key/1" do
    test "converts plaintext key to encrypted storage and creates backup", %{repo: repo} do
      File.cd!(repo, fn ->
        {:ok, keypair} = FileKeyStorage.generate_keypair()
        :ok = FileKeyStorage.store_keypair(keypair)

        Process.put(:gitfoil_cached_master_key, :dummy)
        Process.put(:gitfoil_cached_keypair, :dummy)

        {:ok, %{backup_path: backup}} = KeyMigration.encrypt_plaintext_key(@password)

        assert File.exists?(KeyMigration.encrypted_path())
        refute File.exists?(KeyMigration.plaintext_path())
        assert File.exists?(backup)
        assert String.starts_with?(Path.basename(backup), "master.key.backup.")
        assert Process.get(:gitfoil_cached_master_key) == nil
        assert Process.get(:gitfoil_cached_keypair) == nil
      end)
    end

    test "returns :already_encrypted when encrypted key exists", %{repo: repo} do
      File.cd!(repo, fn ->
        {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
        :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, @password)

        assert {:error, :already_encrypted} = KeyMigration.encrypt_plaintext_key(@password)
      end)
    end

    test "returns :no_plaintext_key when key missing", %{repo: repo} do
      File.cd!(repo, fn ->
        refute File.exists?(KeyMigration.plaintext_path())
        assert {:error, :no_plaintext_key} = KeyMigration.encrypt_plaintext_key(@password)
      end)
    end
  end

  describe "unencrypt_key/1" do
    test "converts encrypted storage to plaintext and creates backup", %{repo: repo} do
      File.cd!(repo, fn ->
        {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
        :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, @password)

        Process.put(:gitfoil_cached_master_key, :dummy)
        Process.put(:gitfoil_cached_keypair, :dummy)

        {:ok, %{backup_path: backup}} = KeyMigration.unencrypt_key(@password)

        assert File.exists?(KeyMigration.plaintext_path())
        refute File.exists?(KeyMigration.encrypted_path())
        assert File.exists?(backup)
        assert String.starts_with?(Path.basename(backup), "master.key.enc.backup.")
        assert Process.get(:gitfoil_cached_master_key) == nil
        assert Process.get(:gitfoil_cached_keypair) == nil
      end)
    end

    test "returns :invalid_password on wrong password", %{repo: repo} do
      File.cd!(repo, fn ->
        {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
        :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, @password)

        assert {:error, :invalid_password} = KeyMigration.unencrypt_key("wrong-password")
      end)
    end

    test "returns :no_encrypted_key when encrypted key missing", %{repo: repo} do
      File.cd!(repo, fn ->
        refute File.exists?(KeyMigration.encrypted_path())
        assert {:error, :no_encrypted_key} = KeyMigration.unencrypt_key(@password)
      end)
    end
  end

  test "path helpers resolve inside .git/git_foil directory", %{repo: repo} do
    File.cd!(repo, fn ->
      git_dir = System.cmd("git", ["rev-parse", "--git-dir"]) |> elem(0) |> String.trim()
      gitfoil_dir = Path.join(Path.expand(git_dir), "git_foil")

      assert KeyMigration.plaintext_path() == Path.join(gitfoil_dir, "master.key")
      assert KeyMigration.encrypted_path() == Path.join(gitfoil_dir, "master.key.enc")
    end)
  end
end
