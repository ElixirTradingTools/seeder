defmodule Seeder.MixProject do
  use Mix.Project

  def project do
    [
      app: :seeder,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:depo, "~> 1.7"},
      {:jason, "~> 1.2"},
      {:typed_struct, "~> 0.2.1"}
    ]
  end
end
