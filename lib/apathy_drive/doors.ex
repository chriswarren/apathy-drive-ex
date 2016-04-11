defmodule ApathyDrive.Doors do
  alias ApathyDrive.{Mobile, PubSub}

  def name, do: "door"

  def lock(mobile, room, room_exit) do
    cond do
      locked?(room, room_exit) ->
        Mobile.send_scroll(mobile, "<p>The #{name} is already locked.</p>")
      open?(room, room_exit) ->
        Mobile.send_scroll(mobile, "<p>You must close the #{name} before you may lock it.</p>")
      true ->
        Mobile.send_scroll(mobile, "<p>The #{name} is now locked.</p>")
        PubSub.subscribers("rooms:#{Room.id(room)}:mobiles", [mobile])
        |> Enum.each(&(Mobile.send_scroll(&1, "<p>You see #{Mobile.name(mobile)} lock the #{name} #{ApathyDrive.Exit.direction_description(room_exit["direction"])}.</p>")))

        Room.lock!(room, room_exit["direction"])

        mirror_room = Room.find(room_exit["destination"])
        mirror_exit = Room.mirror_exit(mirror_room, Room.id(room))

        if mirror_exit["kind"] == room_exit["kind"] do
          PubSub.subscribers("rooms:#{room_exit["destination"]}:mobiles")
          |> Enum.each(&(Mobile.send_scroll(&1, "<p>The #{String.downcase(mirror_exit["kind"])} #{ApathyDrive.Exit.direction_description(mirror_exit["direction"])} just locked!</p>")))

          Room.lock!(mirror_room, mirror_exit["direction"])
        end
    end
  end

  def locked?(room, room_exit) do
    !open?(room, room_exit) and !Room.unlocked?(room, room_exit["direction"])
  end

  def open?(room, room_exit) do
    permanently_open?(room_exit) or
    all_remote_actions_triggered?(room, room_exit) or
    Room.temporarily_open?(room, room_exit["direction"]) or
    Room.searched?(room, room_exit["direction"]) or
    opened_remotely?(room, room_exit)
  end

  def permanently_open?(room_exit) do
    !!room_exit["open"]
  end

  def all_remote_actions_triggered?(room, room_exit) do
    if room_exit["remote_action_exits"] do
      room_exit["remote_action_exits"]
      |> Enum.all?(fn(remote_exit) ->
           triggered?(room, remote_exit)
         end)
    else
      false
    end
  end

  def triggered?(room, %{} = room_exit) do
    room
    |> Map.get(:effects)
    |> Map.values
    |> Enum.filter(fn(effect) ->
         Map.has_key?(effect, :triggered)
       end)
    |> Enum.map(fn(effect) ->
          effect.triggered.remote_exit
       end)
    |> Enum.member?(room_exit)
  end

  def triggered?(room, direction) do
    room
    |> Map.get(:effects)
    |> Map.values
    |> Enum.filter(fn(effect) ->
         Map.has_key?(effect, :triggered)
       end)
    |> Enum.filter(fn(effect) ->
          effect.triggered.direction == direction
       end)
  end

  def opened_remotely?(_room, _room_exit) do
    false
    #!!reactor.timer(self, :opened_remotely)
  end

end
