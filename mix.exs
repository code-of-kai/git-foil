defmodule GitFoil.MixProject do
  use Mix.Project

  def project do
    [
      app: :git_foil,
      version: "0.7.2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
      # CLI escript configuration
      escript: [main_module: GitFoil.CLI, name: "git-foil"],
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
      ],
      # Mix Release configuration with Burrito
      releases: [
        git_foil: [
          steps: [:assemble, &Burrito.wrap/1],
          include_executables_for: [],
          applications: [runtime_tools: :none],
          burrito: [
            targets: [
              macos_arm64: [os: :darwin, cpu: :aarch64],
              macos_x86_64: [os: :darwin, cpu: :x86_64],
              linux_x86_64: [os: :linux, cpu: :x86_64],
              linux_arm64: [os: :linux, cpu: :aarch64]
            ]
          ]
        ]
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

      # Burrito - standalone executable builder
      {:burrito, "~> 1.0"},

      # Alternative crypto implementation (libsodium)
      # DISABLED: enacl not compatible with OTP 28 yet
      # {:enacl, "~> 1.2"},

      # Code quality and static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Test coverage
      {:excoveralls, "~> 0.18", only: :test},

      # Property-based testing
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end
