defmodule GitFoil.Native.PqcleanLoader do
  @moduledoc false

  require Logger

  @pqclean_app :pqclean
  @nif_module :pqclean_nif
  @nif_name "pqclean_nif"

  @doc """
  Ensures the pqclean NIF is loaded when running from environments like escript
  where the dependency's priv directory is not automatically available.
  """
  @spec ensure_loaded() :: :ok | {:error, term()}
  def ensure_loaded do
    case priv_dir() do
      {:ok, dir} ->
        if priv_nif_available?(dir) do
          :ok
        else
          load_from_dev_build()
        end

      {:error, _} ->
        load_from_dev_build()
    end
  end

  defp load_from_dev_build do
    with {:ok, {ebin_path, priv_path}} <- find_dev_build_paths(),
         :ok <- reload_module(@pqclean_app, ebin_path),
         :ok <- reload_module(@nif_module, ebin_path),
         :ok <- ensure_priv_nif(priv_path) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to load pqclean NIF from development build: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp priv_dir do
    case :code.priv_dir(@pqclean_app) do
      {:error, :bad_name} -> {:error, :bad_name}
      path when is_list(path) -> {:ok, List.to_string(path)}
    end
  end

  defp priv_nif_available?(dir) do
    File.exists?(Path.join(dir, nif_filename()))
  end

  defp find_dev_build_paths do
    script_root = script_root()

    candidates =
      for env <- ["prod", "dev", "test"] do
        Path.join([script_root, "_build", env, "lib", Atom.to_string(@pqclean_app)])
      end ++
        [Path.join(script_root, "deps/#{Atom.to_string(@pqclean_app)}")]

    case Enum.find(candidates, &valid_build_path?/1) do
      nil ->
        {:error, :dev_build_not_found}

      base_path ->
        {:ok, {Path.join(base_path, "ebin"), Path.join(base_path, "priv")}}
    end
  end

  defp valid_build_path?(base_path) do
    File.dir?(Path.join(base_path, "ebin")) and
      File.dir?(Path.join(base_path, "priv"))
  end

  defp reload_module(module, ebin_path) do
    maybe_unload_module(module)

    :code.add_patha(String.to_charlist(ebin_path))

    case :code.ensure_loaded(module) do
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

  defp ensure_priv_nif(priv_path) do
    target = Path.join(priv_path, nif_filename())

    cond do
      File.exists?(target) ->
        :ok

      true ->
        case target_from_dev_build() do
          nil ->
            {:error, :nif_binary_missing}

          source ->
            File.mkdir_p!(priv_path)
            File.cp!(source, target)
            File.chmod(target, 0o755)
            :ok
        end
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
    case :os.type() do
      {:win32, _} -> ".dll"
      {:unix, :darwin} -> ".so"
      {:unix, :linux} -> ".so"
      _ -> ".so"
    end
  end
end
