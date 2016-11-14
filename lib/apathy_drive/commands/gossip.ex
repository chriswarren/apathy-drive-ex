defmodule ApathyDrive.Commands.Gossip do
  use ApathyDrive.Command

  def keywords, do: ["gos"]

  def execute(%Room{} = room, %Character{} = character, args) do
    message =
      args
      |> Enum.join(" ")
      |> Monster.sanitize()
    ApathyDrive.Endpoint.broadcast!("chat:gossip", "scroll", %{html: "<p>[<span class='dark-magenta'>gossip</span> : #{Mobile.look_name(character)}] #{message}</p>"})
    room
  end

end
