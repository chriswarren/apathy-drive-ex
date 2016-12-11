defmodule ApathyDrive.Commands.Move do
  alias ApathyDrive.{Character, Companion, Doors, Mobile, Room, RoomServer}

  def execute(%Room{} = room, %{} = character, command) when is_binary(command) do
    direction = Room.direction(command)
    room_exit = Room.get_exit(room, direction)

    execute(room, character, room_exit)
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => kind} = room_exit) when kind in ["Trap", "Cast"] do
    execute(room, character, Map.put(room_exit, "kind", "Normal"))
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => kind} = room_exit) when kind in ["Door", "Gate"] do
    execute(room, character, Map.put(room_exit, "kind", "Normal"))
  end

  def execute(%Room{} = room, character, %{"kind" => "Hidden", "passable_while_hidden" => true} = room_exit) do
    execute(room, character, Map.put(room_exit, "kind", "Normal"))
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => "Hidden", "passable_while_hidden" => false} = room_exit) do
    if Doors.open?(room, room_exit) do
      execute(room, character, Map.put(room_exit, "kind", "Normal"))
    else
      Mobile.send_scroll(character, "<p>There is no exit in that direction.</p>")
      room
    end
  end

  def execute(%Room{} = room, %{} = character, nil) do
    Mobile.send_scroll(character, "<p>There is no exit in that direction.</p>")
    room
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => "Command"}) do
    Mobile.send_scroll(character, "<p>There is no exit in that direction.</p>")
    room
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => "RemoteAction"}) do
    Mobile.send_scroll(character, "<p>There is no exit in that direction.</p>")
    room
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => "Normal", "destination" => destination_id} = room_exit) do
    if !Mobile.held(character) and !Mobile.confused(character, room) do
      Room.display_exit_message(room, %{mobile: character, message: Mobile.exit_message(character), to: destination_id})

      if Mobile.stealth_at_level(character, character.level, room) > 0 do
        Mobile.send_scroll(character, "<p>Sneaking...</p>")
      end

      destination_id
      |> RoomServer.find
      |> RoomServer.mobile_entered(character)

      put_in(room.mobiles, Map.delete(room.mobiles, character.ref))
      |> party_move(character, room_exit)
    else
      room
    end
  end

  def execute(%Room{} = room, %{} = character, %{"kind" => "Action", "destination" => destination_id} = room_exit) do
    if !Mobile.held(character) and !Mobile.confused(character, room) do

      if Mobile.stealth_at_level(character, character.level, room) > 0 do
        Mobile.send_scroll(character, "<p>Sneaking...</p>")
      end
      Mobile.send_scroll(character, "<p><span class='yellow'>#{room_exit["mover_message"]}</span></p>")

      destination_id
      |> RoomServer.find
      |> RoomServer.mobile_entered(character, "<span class='yellow'>#{room_exit["to_message"]}</span>")

      Room.display_exit_message(room, %{mobile: character, message: room_exit["from_message"], to: destination_id})

      put_in(room.mobiles, Map.delete(room.mobiles, character.ref))
      |> party_move(character, room_exit)
    else
      room
    end
  end

  def party_move(room, %{leader: ref, ref: ref} = character, %{"direction" => direction} = room_exit) do
    room.mobiles
    |> Map.values
    |> Enum.reduce(room, fn
         %Character{leader: ^ref} = party_member, updated_room ->
           Mobile.send_scroll(party_member, "<p> -- Following your Party leader #{direction} --</p>")
           execute(updated_room, party_member, room_exit)
         %Companion{leader: ^ref} = party_member, updated_room ->
           execute(updated_room, party_member, room_exit)
         _, updated_room ->
           updated_room
       end)
  end

  def party_move(room, character, _room_exit) do
    room
  end

end
