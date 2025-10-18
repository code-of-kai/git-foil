defmodule GitFoil.Native.PqcleanLoader do
  @moduledoc false

  require Logger

  @pqclean_app :pqclean
  @nif_module :pqclean_nif
  @nif_name "pqclean_nif"
  @shared_lib_ext (
                    case :os.type() do
                      {:win32, _} -> ".dll"
                      {:unix, :darwin} -> ".so"
                      {:unix, :linux} -> ".so"
                      _ -> ".so"
                    end
                  )
  @embedded_nif_path Path.expand("../../../deps/pqclean/priv/#{@nif_name <> @shared_lib_ext}", __DIR__)
  @embedded_nif (
                  case File.read(@embedded_nif_path) do
                    {:ok, bin} -> bin
                    _ -> nil
                  end
                )
  @embedded_app (
                  [
                    "../../../_build/dev/lib/pqclean/ebin/pqclean.app",
                    "../../../_build/prod/lib/pqclean/ebin/pqclean.app",
                    "../../../_build/test/lib/pqclean/ebin/pqclean.app"
                  ]
                  |> Enum.map(&Path.expand(&1, __DIR__))
                  |> Enum.find_value(fn path ->
                    case File.read(path) do
                      {:ok, bin} -> bin
                      _ -> nil
                    end
                  end)
                )

  @doc """
  Ensures the pqclean NIF is loaded when running from environments like escript
  where the dependency's priv directory is not automatically available.
  """
  @spec ensure_loaded() :: :ok | {:error, term()}
  def ensure_loaded do
    case priv_path_from_runtime() do
      {:ok, priv_path} ->
        case ensure_priv_nif(priv_path) do
          :ok ->
            :ok

          {:error, :nif_binary_missing} ->
            stage_and_reload()

          {:error, {:embedded_write_failed, _, _}} ->
            stage_and_reload()

          {:error, :dev_build_not_found} ->
            stage_and_reload()

          {:error, reason} ->
            log_prepare_failure(reason)
            {:error, reason}
        end

      {:error, _} ->
        stage_and_reload()
    end
  end

  defp stage_and_reload do
    with {:ok, priv_path} <- stage_embedded_build(),
         :ok <- ensure_priv_nif(priv_path) do
      :ok
    else
      {:error, reason} ->
        log_stage_failure(reason)
        {:error, reason}
    end
  end

  defp priv_dir do
    case :code.priv_dir(@pqclean_app) do
      {:error, :bad_name} -> {:error, :bad_name}
      path when is_list(path) -> {:ok, List.to_string(path)}
    end
  end

  defp priv_path_from_runtime do
    case priv_dir() do
      {:ok, dir} ->
        {:ok, dir}

      {:error, _} ->
        priv_path_from_code_path()
    end
  end

  defp priv_path_from_code_path do
    case :code.which(@nif_module) do
      :non_existing ->
        {:error, :module_not_found}

      path when is_list(path) ->
        priv_path =
          path
          |> List.to_string()
          |> Path.dirname()
          |> Path.join("../priv")
          |> Path.expand()

        {:ok, priv_path}
    end
  end

  defp ensure_priv_nif(priv_path) do
    target = Path.join(priv_path, nif_filename())

    cond do
      File.exists?(target) ->
        :ok

      true ->
        case maybe_write_embedded_nif(target) do
          :ok ->
            :ok

          {:error, reason} ->
            {:error, reason}

          :error ->
            copy_from_dev_build(priv_path, target)
        end
    end
  end

  defp copy_from_dev_build(priv_path, target) do
    case target_from_dev_build() do
      source when is_binary(source) ->
        with :ok <- File.mkdir_p(priv_path),
             :ok <- File.cp(source, target),
             :ok <- File.chmod(target, 0o755) do
          :ok
        else
          {:error, reason} -> {:error, {:nif_copy_failed, reason}}
        end

      _ ->
        {:error, :dev_build_not_found}
    end
  end

  defp stage_embedded_build do
    with true <- embedded_nif_available?(),
         {:ok, base_path} <- embedded_base_path(),
         :ok <- clear_directory(base_path),
         ebin_path = Path.join(base_path, "ebin"),
         {:ok, pqclean_bin} <- get_object_code(@pqclean_app),
         {:ok, pqclean_nif_bin} <- get_object_code(@nif_module),
         :ok <- File.mkdir_p(ebin_path),
         :ok <- write_embedded_app(ebin_path),
         :ok <- remove_existing_code_paths(),
         :ok <- add_code_path(ebin_path),
         :ok <- load_module_from_embedded(@pqclean_app, ebin_path, pqclean_bin),
         :ok <- ensure_application_loaded(),
         {:ok, priv_path} <- resolve_priv_path(),
         :ok <- File.mkdir_p(priv_path),
         :ok <- write_embedded_nif(Path.join([priv_path, nif_filename()])),
         :ok <- load_module_from_embedded(@nif_module, ebin_path, pqclean_nif_bin) do
      {:ok, priv_path}
    else
      false ->
        {:error, :embedded_nif_missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp target_from_dev_build do
    script_root = script_root()

    build_candidates =
      for env <- ["prod", "dev", "test"] do
        Path.join([
          script_root,
          "_build",
          env,
          "lib",
          Atom.to_string(@pqclean_app),
          "priv",
          nif_filename()
        ])
      end

    (build_candidates ++
       [
        Path.join([
          script_root,
          "deps",
          Atom.to_string(@pqclean_app),
          "priv",
          nif_filename()
        ])
       ])
    |> Enum.find(&File.exists?/1)
  end

  defp app_source_from_dev_build do
    script_root = script_root()

    candidates =
      for env <- ["prod", "dev", "test"] do
        Path.join([
          script_root,
          "_build",
          env,
          "lib",
          Atom.to_string(@pqclean_app),
          "ebin",
          "pqclean.app"
        ])
      end ++
        [
          Path.join([
            script_root,
            "deps",
            Atom.to_string(@pqclean_app),
            "ebin",
            "pqclean.app"
          ])
        ]

    Enum.find(candidates, &File.exists?/1)
  end

  defp embedded_base_path do
    cache_dir =
      :filename.basedir(:user_cache, ~c"git_foil/pqclean")
      |> List.to_string()

    {:ok, Path.join(cache_dir, "embedded")}
  end

  defp write_embedded_app(ebin_path) do
    target = Path.join(ebin_path, "pqclean.app")

    cond do
      is_binary(@embedded_app) ->
        File.write(target, @embedded_app)

      source = app_source_from_dev_build() ->
        File.cp(source, target)

      true ->
        {:error, :app_missing}
    end
  end

  defp get_object_code(module) do
    case :code.get_object_code(module) do
      {^module, binary, _path} -> {:ok, binary}
      :error -> {:error, {:object_code_not_found, module}}
    end
  end

  defp remove_existing_code_paths do
    :code.get_path()
    |> Enum.filter(fn path ->
      path
      |> List.to_string()
      |> String.contains?("/pqclean/ebin")
    end)
    |> Enum.each(&:code.del_path/1)

    :ok
  end

  defp add_code_path(path) do
    :code.add_patha(String.to_charlist(path))
    :ok
  end

  defp ensure_application_loaded do
    _ = Application.unload(@pqclean_app)

    case Application.load(@pqclean_app) do
      :ok -> :ok
      {:error, {:already_loaded, _}} -> :ok
      {:error, reason} -> {:error, {:app_load_failed, reason}}
    end
  end

  defp resolve_priv_path do
    try do
      case apply(@pqclean_app, :priv_dir, []) do
        path when is_list(path) ->
          {:ok, List.to_string(path)}
        {:error, reason} -> {:error, {:priv_dir_error, reason}}
      end
    rescue
      _ -> {:error, :priv_dir_error}
    end
  end

  defp clear_directory(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _success} -> {:error, {:cleanup_failed, reason}}
    end
  end

  defp load_module_from_embedded(module, ebin_path, binary) do
    file_path = Path.join(ebin_path, "#{Atom.to_string(module)}.beam")
    maybe_unload_module(module)

    case :code.load_binary(module, String.to_charlist(file_path), binary) do
      {:module, ^module} -> :ok
      {:error, reason} -> {:error, {:load_failed, module, reason}}
    end
  end

  defp maybe_unload_module(module) do
    case :code.is_loaded(module) do
      false ->
        :ok

      {:file, path} ->
        :code.purge(module)
        :code.delete(module)
        :code.del_path(:filename.dirname(path))
    end
  end

  defp script_root do
    case :escript.script_name() do
      :undefined ->
        File.cwd!()

      script_name ->
        script_name
        |> List.to_string()
        |> Path.dirname()
    end
  end

  defp nif_filename do
    @nif_name <> shared_library_extension()
  end

  defp shared_library_extension do
    @shared_lib_ext
  end

  defp maybe_write_embedded_nif(target) do
    if embedded_nif_available?() do
      dir = Path.dirname(target)

      with :ok <- File.mkdir_p(dir),
           :ok <- File.write(target, @embedded_nif),
           :ok <- File.chmod(target, 0o755) do
        :ok
      else
        {:error, reason} -> {:error, {:embedded_write_failed, reason, target}}
      end
    else
      :error
    end
  end

  defp write_embedded_nif(target) do
    dir = Path.dirname(target)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(target, @embedded_nif),
         :ok <- File.chmod(target, 0o755) do
      :ok
    else
      {:error, reason} -> {:error, {:embedded_write_failed, reason, target}}
    end
  end

  defp embedded_nif_available? do
    is_binary(@embedded_nif) and byte_size(@embedded_nif) > 0
  end

  defp log_prepare_failure(reason) do
    Logger.log(log_level(reason), "Failed to prepare pqclean NIF: #{inspect(reason)}")
  end

  defp log_stage_failure(reason) do
    Logger.log(log_level(reason), "Failed to stage embedded pqclean NIF: #{inspect(reason)}")
  end

  defp log_level(:dev_build_not_found), do: :debug
  defp log_level({:embedded_write_failed, _, _}), do: :error
  defp log_level({:app_load_failed, _}), do: :error
  defp log_level({:nif_copy_failed, _}), do: :error
  defp log_level({:object_code_not_found, _}), do: :error
  defp log_level(_), do: :error
end
