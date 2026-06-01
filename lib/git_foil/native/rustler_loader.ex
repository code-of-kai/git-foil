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

  # --- Compile-time ordering guarantee (do not remove) -----------------------
  #
  # `@embedded_libraries` below reads each compiled `.so` off disk AT THIS
  # MODULE'S COMPILE TIME and bakes the bytes into this `.beam`. That embedding
  # is how the escript ships the crypto NIFs at all: an escript is a zip of
  # `.beam`/`.app` files and cannot carry a `priv/` directory, so the `.so`
  # payloads have to ride inside a module.
  #
  # The `.so` files are produced as a side effect of compiling the NIF modules
  # (`use Rustler` runs `cargo build` and drops the artifact into
  # `_build/<env>/lib/git_foil/priv/native/`). Therefore THIS module must be
  # compiled *after* all five NIF modules, or the reads below find nothing and
  # the escript ships an empty map — at runtime every clean/smudge then fails
  # NIF `on_load` and exits 75 (the v1.1.2 keg bug).
  #
  # `require`-ing the NIF modules records a compile-time dependency edge, so
  # Mix's parallel compiler is forced to build them — and thus their `.so` —
  # before this module. `require` does NOT run `@on_load`/`dlopen` (that only
  # happens on code *load*), so this is a pure build-order constraint with no
  # runtime cost. This is the fix that makes a plain `mix compile` /
  # `mix escript.build` self-contained, independent of any external build
  # choreography in the Homebrew formula.
  require GitFoil.Native.AegisNif
  require GitFoil.Native.AsconNif
  require GitFoil.Native.ChaCha20Poly1305Nif
  require GitFoil.Native.DeoxysNif
  require GitFoil.Native.SchwaemmNif

  # Where a given `.so` may live, in priority order. `_build/<env>` is rustler's
  # output dir; the source `priv/native` copy is the fallback. Shared by the
  # `@external_resource` declarations and the embedding reduce below so the two
  # never drift apart.
  @nif_so_candidates (for %{base: base} <- @nif_libraries, into: %{} do
                        paths =
                          (for env <- ["dev", "test", "prod"] do
                             Path.expand(
                               "../../../_build/#{env}/lib/git_foil/priv/native/#{base}.so",
                               __DIR__
                             )
                           end) ++
                            [Path.expand("../../../priv/native/#{base}.so", __DIR__)]

                        {base, paths}
                      end)

  # Declare the `.so` files as external resources so Mix recompiles THIS module
  # whenever a crate is rebuilt — incremental-build correctness on top of the
  # from-scratch ordering guaranteed by the `require`s above.
  for {_base, paths} <- @nif_so_candidates, path <- paths do
    @external_resource path
  end

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
                        binary =
                          @nif_so_candidates
                          |> Map.fetch!(base)
                          |> Enum.find_value(fn path ->
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

  # Loud guard: never silently ship an escript that lost its NIF payloads.
  # If the embedding came up empty for any crate, the build that produced it is
  # broken (ordering regression, missing toolchain, moved output dir) and the
  # resulting binary would fail-closed on every clean/smudge. Fail the BUILD
  # instead, so the bug can never reach a user as a runtime exit 75.
  # Escape hatch (`GIT_FOIL_ALLOW_MISSING_NIFS=1`) exists only for deliberate
  # NIF-less builds (e.g. compiling on a host without the Rust toolchain).
  @missing_nif_payloads (for %{base: base} <- @nif_libraries,
                             not Map.has_key?(@embedded_libraries, base),
                             do: base)

  if @missing_nif_payloads != [] and System.get_env("GIT_FOIL_ALLOW_MISSING_NIFS") != "1" do
    raise """
    RustlerLoader compiled with no embedded payload for: #{inspect(@missing_nif_payloads)}.

    The crypto crates must be compiled (their `.so` present under
    _build/<env>/lib/git_foil/priv/native/ or priv/native/) BEFORE this module
    is compiled, or the escript will ship without its NIFs and fail every
    clean/smudge at runtime (exit 75).

    Run `mix compile` from a clean tree (the `require`s in this module force the
    crates to build first). If you are intentionally building without the Rust
    toolchain, set GIT_FOIL_ALLOW_MISSING_NIFS=1.
    """
  end

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
