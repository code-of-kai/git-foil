defmodule GitFoil.Commands.KeyCommandsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GitFoil.Adapters.{FileKeyStorage, PasswordProtectedKeyStorage}
  alias GitFoil.Commands.{EncryptKey, UnencryptKey}
  alias GitFoil.Core.KeyMigration
  alias GitFoil.TestSupport.TempRepo

  @password "cli-test-password"

  setup do
    repo = TempRepo.create!()

    on_exit(fn ->
      File.rm_rf!(repo)
      reset_env(["GIT_FOIL_PASSWORD"])
    end)

    {:ok, repo: repo}
  end

  describe "EncryptKey.run/1" do
    test "encrypts plaintext key and reports success", %{repo: repo} do
      in_repo(repo, fn ->
        {:ok, keypair} = FileKeyStorage.generate_keypair()
        :ok = FileKeyStorage.store_keypair(keypair)

        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {output, {:ok, message}} = capture_result(fn -> EncryptKey.run() end)

          assert output =~ "Encrypting master key"
          assert message =~ "Master key encrypted with password."
          assert File.exists?(KeyMigration.encrypted_path())
          refute File.exists?(KeyMigration.plaintext_path())
          assert backup_exists?("master.key.backup.")
        end)
      end)
    end

    test "returns informational message when already encrypted", %{repo: repo} do
      in_repo(repo, fn ->
        {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
        :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, @password)

        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {_output, {:ok, message}} = capture_result(fn -> EncryptKey.run() end)
          assert message =~ "already password protected"
        end)
      end)
    end

    test "fails when GitFoil not initialized", %{repo: repo} do
      in_repo(repo, fn ->
        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {_output, {:error, reason}} = capture_result(fn -> EncryptKey.run() end)
          assert reason =~ "GitFoil not initialized"
        end)
      end)
    end

    test "fails outside git repository" do
      dir = non_git_dir()

      File.cd!(dir, fn ->
        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {_output, {:error, reason}} = capture_result(fn -> EncryptKey.run() end)
          assert reason =~ "Not a Git repository"
        end)
      end)

      File.rm_rf!(dir)
    end
  end

  describe "UnencryptKey.run/1" do
    test "unencrypts key with correct password", %{repo: repo} do
      in_repo(repo, fn ->
        {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
        :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, @password)

        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {output, {:ok, message}} = capture_result(fn -> UnencryptKey.run() end)

          assert output =~ "Removing password protection"
          assert message =~ "Master key stored without password."
          assert File.exists?(KeyMigration.plaintext_path())
          refute File.exists?(KeyMigration.encrypted_path())
          assert backup_exists?("master.key.enc.backup.")
        end)
      end)
    end

    test "returns informative message when already plaintext", %{repo: repo} do
      in_repo(repo, fn ->
        {:ok, keypair} = FileKeyStorage.generate_keypair()
        :ok = FileKeyStorage.store_keypair(keypair)

        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {_output, {:ok, message}} = capture_result(fn -> UnencryptKey.run() end)
          assert message =~ "already stored without password"
        end)
      end)
    end

    test "fails with invalid password", %{repo: repo} do
      in_repo(repo, fn ->
        {:ok, keypair} = PasswordProtectedKeyStorage.generate_keypair()
        :ok = PasswordProtectedKeyStorage.store_keypair_with_password(keypair, @password)

        with_env(%{"GIT_FOIL_PASSWORD" => "wrongpass"}, fn ->
          {_output, {:error, reason}} = capture_result(fn -> UnencryptKey.run() end)
          assert reason =~ "Invalid password"
          assert File.exists?(KeyMigration.encrypted_path())
        end)
      end)
    end

    test "fails outside git repository" do
      dir = non_git_dir()

      File.cd!(dir, fn ->
        with_env(%{"GIT_FOIL_PASSWORD" => @password}, fn ->
          {_output, {:error, reason}} = capture_result(fn -> UnencryptKey.run() end)
          assert reason =~ "Not a Git repository"
        end)
      end)

      File.rm_rf!(dir)
    end
  end

  defp capture_result(fun) do
    parent = self()

    output =
      capture_io(fn ->
        send(parent, {:result, fun.()})
      end)

    result =
      receive do
        {:result, value} -> value
      after
        0 -> flunk("Expected command result but none was captured")
      end

    {output, result}
  end

  defp with_env(vars, fun) do
    original =
      vars
      |> Map.new(fn {key, _val} -> {key, System.get_env(key)} end)

    Enum.each(vars, fn {key, value} -> System.put_env(key, value) end)

    try do
      fun.()
    after
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp reset_env(keys) do
    Enum.each(keys, &System.delete_env/1)
  end

  defp in_repo(repo, fun), do: File.cd!(repo, fun)

  defp backup_exists?(prefix) do
    ".git/git_foil"
    |> File.ls!()
    |> Enum.any?(&String.starts_with?(&1, prefix))
  end

  defp non_git_dir do
    base = System.tmp_dir!()
    path = Path.join(base, "gitfoil_nongit_" <> Integer.to_string(System.unique_integer([:positive])))
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
