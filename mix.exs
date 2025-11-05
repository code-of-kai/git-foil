defmodule GitFoil.MixProject do
  use Mix.Project

  def project do
    [
      app: :git_foil,
      version: "1.0.8",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # Rustler NIF compilation
      rustler_crates: [
        ascon_nif: [
          path: "native/ascon_nif",
          mode: rustc_mode(Mix.env())
        ],
        aegis_nif: [
          path: "native/aegis_nif",
          mode: rustc_mode(Mix.env())
        ],
        schwaemm_nif: [
          path: "native/schwaemm_nif",
          mode: rustc_mode(Mix.env())
        ],
        deoxys_nif: [
          path: "native/deoxys_nif",
          mode: rustc_mode(Mix.env())
        ],
        chacha20poly1305_nif: [
          path: "native/chacha20poly1305_nif",
          mode: rustc_mode(Mix.env())
        ]
      ],
      releases: releases(),
      # Escript for development testing
      escript: [
        main_module: GitFoil.CLI,
        name: "git-foil",
        embed_elixir: true,
        strip_beams: false
      ],
      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ],
      # Dialyzer for type checking
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  defp releases do
    [
      git_foil: [
        applications: [git_foil: :permanent],
        include_executables_for: [:unix]
      ]
    ]
  end

  defp rustc_mode(:prod), do: :release
  defp rustc_mode(_), do: :debug

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {GitFoil.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Post-quantum cryptography
      {:pqclean, "~> 0.0.3"},

      # Rust NIF for Ascon-128a
      {:rustler, "~> 0.34.0"},

      # Code quality and static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Test coverage
      {:excoveralls, "~> 0.18", only: :test},

      # Property-based testing
      {:stream_data, "~> 1.1", only: :test},

      # Local fork to silence deprecated charlist warnings
      {:toml, path: "vendor/toml", override: true},

      # Tidewave MCP server for development
      {:tidewave, github: "tidewave-ai/tidewave_phoenix", only: :dev, runtime: false},
      {:bandit, "~> 1.5", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      tidewave: "run --no-halt -e 'Application.put_env(:tidewave, :root, File.cwd!()); Application.put_env(:tidewave, :git_root, File.cwd!()); Application.put_env(:tidewave, :project_name, \"git_foil\"); Agent.start(fn -> Bandit.start_link(plug: {Tidewave, []}, port: 4010) end)'"
    ]
  end
end
