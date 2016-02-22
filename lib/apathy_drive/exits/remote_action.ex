defmodule ApathyDrive.Exits.RemoteAction do
  use ApathyDrive.Exit
  alias ApathyDrive.World

  def display_direction(_room, _room_exit), do: nil

  def move(_room, mobile, _room_exit, _last_room) do
    Mobile.send_scroll(mobile, "<p>There is no exit in that direction.</p>")
  end

  def look(_room, mobile, _room_exit) do
    Mobile.send_scroll(mobile, "<p>There is no exit in that direction.</p>")
  end

  def get_room(%Room{id: id} = room, other_id) when id == other_id do
    room
  end
  def get_room(%Room{}, id) do
    id
    |> Room.find
    |> World.room
  end

  def trigger_remote_action(room, mobile, room_exit) do
    room   = World.room(room)
    mobile = Mobile.value(mobile)

    remote_room = get_room(room, room_exit["destination"])
    remote_exit = remote_room.exits
                  |> Enum.find(fn(remote_exit) ->
                       remote_exit["remote_action_exits"] && Enum.member?(remote_exit["remote_action_exits"],
                                                                          %{"room" => room.id,
                                                                            "direction" => room_exit["direction"]})
                     end)

    if trigger_remote_action?(remote_room, remote_exit, room_exit) do
      ApathyDrive.PubSub.broadcast!("rooms:#{room.id}", {:trigger, room_exit["direction"]})

      Mobile.send_scroll(mobile, "<p>#{room_exit["message"]}</p>")

      ApathyDrive.Endpoint.broadcast_from! self, "rooms:#{room.id}", "scroll", %{:html => "<p><span class='dark-green'>#{interpolate(room_exit["room_message"], %{"user" => mobile})}</span></p>"}

      if :"Elixir.ApathyDrive.Exits.#{remote_exit["kind"]}".open?(remote_room, remote_exit) do
        if remote_exit["message_when_revealed"] do
          Room.send_scroll(remote_room, "<p><span class='white'>#{remote_exit["message_when_revealed"]}</span></p>")
        end
      end
    else
      clear_triggers!(remote_exit)
      trigger_remote_action(room, mobile, room_exit)
    end
  end

  def trigger_remote_action?(remote_room, %{"remote_action_order_matters" => true} = remote_exit, room_exit) do
    remote_exit["remote_action_exits"]
    |> Enum.filter(&triggered?/1)
    |> Enum.all?(fn(ra_exit) ->
         remote_action_order = get_room(remote_room, ra_exit["room"]).exits
                               |> Enum.find(fn(other_remote_exit) ->
                                    other_remote_exit["direction"] == ra_exit["direction"]
                                  end)
                               |> Map.get("remote_action_order")

         remote_action_order == nil or remote_action_order < room_exit["remote_action_order"]
       end)
  end
  def trigger_remote_action?(_remote_room, _remote_exit, _room_exit), do: true

  def clear_triggers!(remote_exit) do
    remote_exit["remote_action_exits"]
    |> Enum.each(fn(map) ->
         ApathyDrive.PubSub.broadcast!("rooms:#{map["room"]}", {:clear_triggers, map["direction"]})
       end)
  end

  def triggered?(room_direction) do
    room = room_direction["room"]
           |> Room.find
           |> World.room

    effects = room.effects

    effects
    |> Map.keys
    |> Enum.any?(fn(key) ->
         effects[key][:triggered] == room_direction["direction"]
       end)
  end

  # [%{"commands" => ["push knot"], "destination" => 23579,
  #    "direction" => "east", "kind" => "RemoteAction",
  #    "message" => "You push a large knot on the darkwood tree.",
  #    "remote_action_order" => 1,
  #    "room_message" => "{{User}} pushes a large knot on the darkwood tree."},
  #  %{"commands" => ["twist knot", "turn knot"], "destination" => 23579,
  #    "direction" => "west", "kind" => "RemoteAction",
  #    "message" => "You twist a large knot on the darkwood tree.",
  #    "remote_action_order" => 2,
  #    "room_message" => "{{User}} twists a large knot on the darkwood tree."},
  #  %{"destination" => 4493, "direction" => "northeast",
  #    "kind" => "Normal"},
  #  %{"description" => "crack in tree southwest", "destination" => 23583,
  #    "direction" => "southwest", "kind" => "Hidden",
  #    "message_when_revealed" => "A groaning crack in the darkwood tree yawns open!",
  #    "passable_while_hidden" => false,
  #    "remote_action_exits" => [%{"direction" => "east", "room" => 23579},
  #     %{"direction" => "west", "room" => 23579}],
  #    "remote_action_order_matters" => true, "searchable" => false}]
end