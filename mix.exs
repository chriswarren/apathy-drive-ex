defmodule ApathyDrive.Mixfile do
  use Mix.Project

  def project do
    [ app: :apathy_drive,
      version: "0.0.1",
      elixir: "~> 1.1",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix] ++ Mix.compilers,
      deps: deps,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: { ApathyDrive, [] },
      applications: [:postgrex, :ecto, :phoenix, :cowboy, :logger, :oauth2, :phoenix_ecto, :comeonin]
    ]
  end

  defp deps do
    [
      {:cowboy,              "~> 1.0.0"},
      {:ecto,                "~> 1.0"},
      {:decimal,             "~> 1.1.0"},
      {:postgrex,            "~> 0.9.1"},
      {:phoenix,             "~> 0.17"},
      {:phoenix_live_reload, "~> 1.0"},
      {:phoenix_ecto,        "~> 1.2"},
      {:phoenix_html,        "~> 2.0"},
      {:timex,               "~> 0.19"},
      {:timex_ecto,          "~> 0.5"},
      {:inflex,              "~> 0.2.8"},
      {:block_timer,         "~> 0.0.1"},
      {:oauth2,              "~> 0.0.5"},
      {:scrivener,           "~> 1.0"},
      {:comeonin,            "~> 1.2.2"},
      {:plug,                "~> 1.0", override: true},
      {:shouldi, only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "web", "test/matchers", "test/support"]
  defp elixirc_paths(_), do: ["lib", "web"]
end
