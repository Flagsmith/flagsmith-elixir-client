defmodule SpecAdapter.MixProject do
  use Mix.Project

  def project do
    [
      app: :spec_adapter,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: true,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SpecAdapter.Application, []}
    ]
  end

  defp deps do
    [
      {:flagsmith_engine, path: ".."},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.2"}
    ]
  end
end
