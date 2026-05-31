defmodule GitFoil.Native.RustlerLoader do
  @moduledoc false

  require Logger

  @nif_libraries [
    %{module: GitFoil.Native.AegisNif, base: "libaegis_nif"},
    %{module: GitFoil.Native.AsconNif, base: "libascon_nif"},
    %{module: GitFoil.Native.ChaCha20Poly1305Nif, base: "libchacha20poly1305_nif"},
    %{module: GitFoil.Native.DeoxysNif, base: "libdeoxys_nif"},
    %{module: GitFoil.Native.SchwaemmNif, base: "libschwaemm_nif"}
  ]

  @app_candidates [
                    "../../../_build/dev/lib/git_foil/ebin/git_foil.app",
                    "../../../_build/test/lib/git_foil/ebin/git_foil.app",
                    "../../../_build/prod/lib/git_foil/ebin/git_foil.app",
                    "../../../deps/git_foil/ebin/git_foil.app"
                  ]
                  |> Enum.map(&Path.expand(&1, __DIR__))

  @embedded_app Enum.find_value(@app_candidates, fn path ->
                  case File.read(path) do
                    {:ok, bin} -> bin
                    _ -> nil
                  end
                end)

  @embedded_libraries Enum.reduce(@nif_libraries, %{}, fn %{base: base}, acc ->
                        candidates =
                          for env <- ["dev", "test", "prod"] do
                            Path.expand(
                              "../../../_build/#{env}/lib/git_foil/priv/native/#{base}.so",
                              __DIR__
                            )
                          end ++
                            [Path.expand("../../../priv/native/#{base}.so", __DIR__)]

                        binary =
                          Enum.find_value(candidates, fn path ->
                            case File.read(path) do
                              {:ok, bin} -> bin
                              _ -> nil
                            end
                          end)

                        if binary do
                          Map.put(acc, base, binary)
                        else
                          acc
                        end
                      end)

  @doc """
  Ensures Rustler NIF libraries are available when running from escripts/releases.
  """
  @spec ensure_loaded() :: :ok | {:error, term()}
  def ensure_loaded do
    with {:ok, base_path} <- stage_application_layout(),
         :ok <- ensure_native_libraries(Path.join(base_path, "priv/native")) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to prepare Rustler NIFs: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Forces every crypto NIF module to load now, retrying on a transient failure.

  Loading a Rustler module runs its `@on_load` (`:erlang.load_nif` -> `dlopen`).
  Under the per-file clean/smudge model, many processes `dlopen` the same `.so`
  concurrently and macOS dyld occasionally races, leaving the module unloaded
  (its stubs raise `UndefinedFunctionError`). `Code.ensure_loaded/1` re-runs
  `@on_load` on each call, so a short retry with backoff absorbs the transient
  failure at the source.

  In the long-running filter process this is called exactly once at startup,
  where there is no concurrency at all — so it is the point that eliminates the
  race rather than papering over it.
  """
  @spec force_load_nifs() :: :ok | {:error, term()}
  def force_load_nifs do
    _ = ensure_loaded()

    @nif_libraries
    |> Enum.reduce_while(:ok, fn %{module: module}, :ok ->
      case load_with_retry(module, 5) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:nif_load_failed, module, reason}}}
      end
    end)
  end

  defp load_with_retry(module, attempts_left) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        :ok

      {:error, _reason} when attempts_left > 1 ->
        # Drop the failed load so ensure_loaded re-runs @on_load next attempt.
        _ = :code.purge(module)
        _ = :code.delete(module)
        Process.sleep(backoff_ms(attempts_left))
        load_with_retry(module, attempts_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # 6 -> retry; gives ~ 20, 40, 80, 160 ms backoffs across attempts.
  defp backoff_ms(attempts_left), do: max(20, (6 - attempts_left) * 20)

  defp stage_application_layout do
    base_path =
      :filename.basedir(:user_cache, ~c"git_foil/runtime")
      |> List.to_string()
      |> Path.join("git_foil")

    ebin_path = Path.join(base_path, "ebin")
    priv_path = Path.join(base_path, "priv")

    with :ok <- clear_directory(base_path),
         :ok <- File.mkdir_p(ebin_path),
         :ok <- File.mkdir_p(priv_path),
         :ok <- write_embedded_app(Path.join(ebin_path, "git_foil.app")),
         :ok <- add_code_path(ebin_path) do
      {:ok, base_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_native_libraries(native_dir) do
    File.mkdir_p!(native_dir)

    @nif_libraries
    |> Enum.reduce_while(:ok, fn %{base: base}, :ok ->
      target = Path.join(native_dir, "#{base}.so")

      case ensure_library_file(base, target) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:library_setup_failed, base, reason}}}
      end
    end)
  end

  defp ensure_library_file(base, target) do
    cond do
      File.exists?(target) ->
        :ok

      binary = Map.get(@embedded_libraries, base) ->
        with :ok <- File.write(target, binary),
             :ok <- File.chmod(target, 0o755) do
          :ok
        else
          {:error, reason} -> {:error, reason}
        end

      source = find_library_on_disk(base) ->
        with :ok <- File.cp(source, target),
             :ok <- File.chmod(target, 0o755) do
          :ok
        else
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:error, :library_not_found}
    end
  end

  defp write_embedded_app(target) do
    cond do
      File.exists?(target) ->
        :ok

      is_binary(@embedded_app) ->
        File.write(target, @embedded_app)

      source = find_app_on_disk() ->
        File.cp(source, target)

      true ->
        write_stub_app(target)
    end
  end

  defp add_code_path(ebin_path) do
    charlist = String.to_charlist(ebin_path)
    :code.del_path(charlist)
    :code.add_patha(charlist)
    :ok
  end

  defp clear_directory(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, {:cleanup_failed, reason}}
    end
  end

  defp find_library_on_disk(base) do
    env_candidates =
      case System.get_env("GIT_FOIL_NIF_DIR") do
        nil -> []
        dir -> [Path.join(dir, "#{base}.so")]
      end

    candidates =
      env_candidates ++
        for env <- ["dev", "test", "prod"] do
          Path.expand(
            "../../../_build/#{env}/lib/git_foil/priv/native/#{base}.so",
            __DIR__
          )
        end ++
        [
          Path.expand("../../../priv/native/#{base}.so", __DIR__)
        ]

    Enum.find(candidates, &File.exists?/1)
  end

  defp find_app_on_disk do
    Enum.find(@app_candidates, &File.exists?/1)
  end

  defp write_stub_app(target) do
    stub = """
    {application, git_foil,
     [{description, "GitFoil runtime stub"},
      {vsn, "0.0.0"},
      {modules, []},
      {registered, []},
      {applications, [kernel,stdlib,elixir,logger]},
      {env, []},
      {runtime_dependencies, []}
     ]}.
    """

    File.write(target, stub)
  end
end
