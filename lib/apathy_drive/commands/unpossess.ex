defmodule ApathyDrive.Commands.Unpossess do
  use ApathyDrive.Command

  def keywords, do: ["unpossess"]

  def execute(%Room{} = room, %Mobile{monster_template_id: nil} = mobile, _args) do
    Mobile.send_scroll(mobile, "<p>You aren't possessing anything.</p>")
    room
  end
  def execute(%Room{} = room, %Mobile{socket: socket, spirit: spirit} = mobile, _args) do
    mobile =
      mobile
      |> Map.put(:spirit, nil)
      |> Map.put(:socket, nil)
      |> Mobile.set_abilities
      |> Mobile.set_max_mana
      |> Mobile.set_mana
      |> Mobile.set_max_hp
      |> Mobile.set_hp

    send(socket, {:respawn, spirit: spirit})
    send(socket, {:scroll, "<p>You leave the body of #{Mobile.look_name(mobile)}.</p>"})

    put_in room.mobiles[mobile.ref], mobile
  end

end
