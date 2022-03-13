defmodule FlagsmithEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :flagsmith_engine,
      version: "0.1.1",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      source_url: "https://github.com/Flagsmith/flagsmith-elixir-flag-engine",
      homepage_url: "https://hexdocs.pm/flagsmith_engine/readme.html",
      docs: [
        main: "Flagsmith.Client",
        extras: ["README.md"]
      ],
      description:
        "Elixir Engine and Client for Flagsmith. Ship features with confidence using feature flags.",
      package: [
        exclude_patterns: [~r/.*~$/, ~r/#.*#$/],
        licenses: ["MIT"],
        links: %{
          "github/readme" => "https://github.com/Flagsmith/flagsmith-elixir-flag-engine"
        }
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.4"},
      {:jason, "~> 1.2"},
      {:ecto, "~> 3.7.0"},
      {:typed_ecto_schema, "~> 0.3", runtime: false},
      {:typed_enum, "~> 0.1"},
      {:plug_cowboy, "~> 2.0", only: :test, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
