defmodule ApathyDrive do
  use Application

  # See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(ApathyDrive.Endpoint, []),
      worker(ApathyDrive.Repo, []),
      worker(ApathyDrive.Migrator, [], restart: :temporary),
      worker(ApathyDrive.Unity, []),
      worker(ApathyDrive.World, [])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ApathyDrive.Supervisor]
    started = Supervisor.start_link(children, opts)

    load_rooms_with_permanent_monsters()

    started
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ApathyDrive.Endpoint.config_change(changed, removed)
    :ok
  end

  defp load_rooms_with_permanent_monsters do
    ApathyDrive.Mobile.permanent_monster_room_ids
    |> Enum.each(&Room.find/1)
  end
end
