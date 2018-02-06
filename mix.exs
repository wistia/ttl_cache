defmodule TtlCache.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ttl_cache,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: false,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/wistia/ttl_cache",
      package: [
        description: "Caches a value and expires it after a given TTL.",
        maintainers: ["Wistia"],
        licenses: ["MIT"],
        links: %{"github" => "https://github.com/wistia/ttl_cache"}
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger],
      env: [ttl: 30_000]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # To depend on another app inside the umbrella:
  #
  #   {:myapp, in_umbrella: true}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
