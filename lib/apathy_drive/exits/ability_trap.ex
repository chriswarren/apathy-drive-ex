defmodule ApathyDrive.Exits.AbilityTrap do
  use ApathyDrive.Exit

  def move(%Room{} = room, %Spirit{} = spirit, room_exit),  do: super(room, spirit, room_exit)
  def move(%Room{} = room, %Monster{} = monster, room_exit) do
    destination = Room.find(room_exit["destination"])
                  |> Room.value

    Room.send_scroll(destination, "<p>#{interpolate(room_exit["to_message"], %{"user" => monster, "alignment-color" => Monster.alignment_color(monster)})}</p>")

    monster = monster
              |> Monster.set_room_id(destination.id)
              |> Monster.save

    Monster.send_scroll(monster, "<p><span class='yellow'>#{interpolate(room_exit["mover_message"], %{"user" => monster})}</span></p>")

    if ability = ApathyDrive.Repo.get(Ability, room_exit["ability"]) do
      send(monster.pid, {:execute_ability, ability, [monster.pid]})
    end

    Room.look(destination, monster)

    Room.send_scroll(room, "<p>#{interpolate(room_exit["from_message"], %{"user" => monster})}</p>")
    monster
  end

end
