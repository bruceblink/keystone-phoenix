defmodule KeystonePhoenix.MixProject do
  use Mix.Project

  def project do
    [
      app: :keystone_phoenix,
      version: "0.3.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [summary: [threshold: 60]],
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {KeystonePhoenix.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.16"},
      {:phoenix_live_view, "~> 1.1"},
      # 固定已迁移到 elixirc_options 的上游提交，消除 Elixir 1.20 的 xref 配置 warning。
      {:phoenix_ecto,
       github: "phoenixframework/phoenix_ecto", ref: "a0c342b5a57581037974cc992a23f4f89a77b29f"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex,
       github: "elixir-ecto/postgrex",
       ref: "87afeb9d5e9089527a728f8403dcbaf0fe0f8f31",
       override: true},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:castore, "~> 1.0"},
      {:bcrypt_elixir, "~> 3.2"},
      {:jose, "~> 1.11"},
      # 固定已适配 Elixir 1.20 的上游提交，避免 Excel 依赖在编译时产生弃用 warning。
      {:elixlsx, github: "xou/elixlsx", ref: "d24fa3843c82cf2a584637544623eb8c0aeea599"},
      {:xlsxir, path: "vendor/xlsxir", override: true},
      {:erlsom,
       github: "willemdj/erlsom", ref: "31dbbfe3b65da7bf717b9103ff6049ef6d091802", override: true},
      {:dns_cluster, "~> 0.3"},
      {:bandit, "~> 1.14"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "check.source_lines",
        "test"
      ]
    ]
  end
end
