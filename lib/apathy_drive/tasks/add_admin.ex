defmodule Mix.Tasks.AddAdmin do
  use Mix.Task

  def run([name]) do
    Mix.Ecto.ensure_started(ApathyDrive.Repo, [])
    case ApathyDrive.Repo.get_by(Spirit, name: name) do
      %Spirit{admin: true} ->
        Mix.shell.info "#{name} is already an admin"
      %Spirit{} = spirit ->
        spirit
        |> Map.put(:admin, true)
        |> ApathyDrive.Repo.save!

        Mix.shell.info "#{name} is now an admin"
      nil ->
        Mix.shell.info "#{name} does not exist"
    end
  end
end
