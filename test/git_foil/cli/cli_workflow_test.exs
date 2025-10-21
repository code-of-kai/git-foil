defmodule GitFoil.CLIWorkflowTest do
  use ExUnit.Case

  setup_all do
    Mix.Task.run("escript.build")
    escript = Path.join(File.cwd!(), "git-foil")
    {:ok, escript: escript}
  end

  test "full CLI workflow encrypts and cleans up", %{escript: escript} do
    repo = tmp_repo()
    env = [{"GIT_FOIL_NO_SPINNER", "1"}, {"CI", "1"}]

    {init_out, init_status} = run_cli(escript, ["init"], repo, env, "\n\n5\n")
    assert init_status == 0, "init failed: #{init_out}"
    assert File.exists?(Path.join(repo, ".git/git_foil/master.key"))

    {add_out, add_status} = run_cli(escript, ["add-pattern", "*.env"], repo, env)
    assert add_status == 0, "add-pattern failed: #{add_out}"

    File.write!(Path.join(repo, "config.env"), "SECRET=1")

    {enc_out, enc_status} = run_cli(escript, ["encrypt"], repo, env, "1\n")
    assert enc_status == 0, "encrypt failed: #{enc_out}"

    {status_out, status_code} = System.cmd("git", ["status", "--short"], cd: repo)
    assert status_code == 0
    assert status_out =~ "config.env"

    {unencrypt_out, unencrypt_status} = run_cli(escript, ["unencrypt"], repo, env, "y\nyes\n")
    assert unencrypt_status == 0, "unencrypt failed: #{unencrypt_out}"
    refute File.exists?(Path.join(repo, ".git/git_foil"))
  end

  test "CLI reports unknown command" do
    assert {:error, message} = GitFoil.CLI.run(["bogus"])
    assert message =~ "Unknown command"
  end

  test "CLI encrypt key toggles password protection", %{escript: escript} do
    repo = tmp_repo()
    base_env = [{"GIT_FOIL_NO_SPINNER", "1"}, {"CI", "1"}]

    {init_out, init_status} = run_cli(escript, ["init"], repo, base_env, "\n\n5\n")
    assert init_status == 0, "init failed: #{init_out}"

    plaintext_key = Path.join(repo, ".git/git_foil/master.key")
    encrypted_key = Path.join(repo, ".git/git_foil/master.key.enc")
    assert File.exists?(plaintext_key)
    refute File.exists?(encrypted_key)

    password_env = [{"GIT_FOIL_PASSWORD", "cli-t0ggle-pass"} | base_env]
    before_files = File.ls!(Path.join(repo, ".git/git_foil"))

    {encrypt_out, encrypt_status} = run_cli(escript, ["encrypt", "key"], repo, password_env)
    assert encrypt_status == 0, "encrypt key failed: #{encrypt_out}"
    assert File.exists?(encrypted_key)
    refute File.exists?(plaintext_key)

    after_encrypt_files = File.ls!(Path.join(repo, ".git/git_foil"))
    assert Enum.any?(after_encrypt_files -- before_files, &String.starts_with?(&1, "master.key.backup."))

    {unencrypt_out, unencrypt_status} = run_cli(escript, ["unencrypt", "key"], repo, password_env)
    assert unencrypt_status == 0, "unencrypt key failed: #{unencrypt_out}"
    assert File.exists?(plaintext_key)
    refute File.exists?(encrypted_key)

    after_unencrypt_files = File.ls!(Path.join(repo, ".git/git_foil"))
    assert Enum.any?(after_unencrypt_files, &String.starts_with?(&1, "master.key.enc.backup."))
  end

  defp run_cli(escript, args, repo, env, input) when is_binary(input) do
    command =
      "printf #{shell_escape(input)} | #{shell_escape(escript)} " <>
        Enum.map_join(args, " ", &shell_escape/1)

    System.cmd("sh", ["-c", command],
      cd: repo,
      env: enrich_env(env, escript),
      stderr_to_stdout: true
    )
  end

  defp run_cli(escript, args, repo, env) do
    System.cmd(escript, args,
      cd: repo,
      env: enrich_env(env, escript),
      stderr_to_stdout: true
    )
  end

  defp enrich_env(env, escript) do
    path_dir = Path.dirname(escript)
    path = System.get_env("PATH")
    env ++ [{"PATH", path_dir <> ":" <> path}, {"_", escript}]
  end

  defp shell_escape(str) do
    "'" <> String.replace(str, "'", "'\"'\"'") <> "'"
  end

  defp tmp_repo do
    base = System.tmp_dir!()
    repo = Path.join(base, "gitfoil_cli_" <> Integer.to_string(System.unique_integer([:positive])))
    File.rm_rf!(repo)
    File.mkdir_p!(repo)
    {_, 0} = System.cmd("git", ["init"], cd: repo)
    repo
  end
end
