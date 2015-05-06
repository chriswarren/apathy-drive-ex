defmodule ApathyDrive.Mixfile do
  use Mix.Project

  def project do
    [ app: :apathy_drive,
      version: "0.0.1",
      elixir: "~> 1.0.4",
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
      applications: [:postgrex, :ecto, :phoenix, :cowboy, :logger, :oauth2, :phoenix_ecto]
    ]
  end

  defp deps do
    [
      {:cowboy,              "~> 1.0.0"},
      {:phoenix,             github: "phoenixframework/phoenix", ref: "c12939a6bb2da6880ff93c41689edfbac726339f", override: true},
      {:phoenix_html,        github: "phoenixframework/phoenix_html", ref: "f4fc4c74c242ce821ae194cbabe9bccbfaacebb5", override: true},
      {:phoenix_live_reload, "~> 0.3.3"},
      {:ecto,                "~> 0.11.0"},
      {:decimal,             "~> 1.1.0"},
      {:postgrex,            "~> 0.8.0"},
      {:timex,               "~> 0.13.4"},
      {:inflex,              "~> 0.2.8"},
      {:block_timer,         "~> 0.0.1"},
      {:oauth2,              "~> 0.0.5"},
      {:phoenix_ecto,        "~> 0.3.1"},
      {:shouldi, only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "web", "test/matchers"]
  defp elixirc_paths(_), do: ["lib", "web"]
end
