defmodule ApathyDrive.Exits.Trap do
  use ApathyDrive.Exit

  def move(current_room, %Spirit{} = spirit, room_exit), do: super(current_room, spirit, room_exit)
  def move(nil, monster, current_room, room_exit) do
    destination = Room.find(room_exit["destination"])
    Components.Monsters.remove_monster(current_room, monster)
    Components.Monsters.add_monster(destination, monster)
    if Entity.has_component?(monster, Components.ID) do
      Entities.save!(destination)
      Entities.save!(current_room)
    end
    Entities.save(monster)

    Systems.Aggression.monster_entered(monster, destination)

    detected = detect?(monster, room_exit)
    dodged   = dodge?(monster, room_exit)

    if (detected and dodged) do
      notify_monster_left(monster, current_room, destination)
      notify_monster_entered(monster, current_room, destination)
    else
      spring_trap!(monster, current_room, destination, room_exit)
    end
    Monster.pursue(current_room, monster, room_exit["direction"])
  end

  def move(spirit, monster, current_room, room_exit) do
    destination = Room.find(room_exit["destination"])
    Components.Monsters.remove_monster(current_room, monster)
    Components.Monsters.add_monster(destination, monster)
    Components.Characters.remove_character(current_room, spirit)
    Components.Characters.add_character(destination, spirit)
    Entities.save!(destination)
    Entities.save!(current_room)
    Entities.save!(spirit)
    Entities.save(monster)

    Systems.Aggression.monster_entered(monster, destination)

    Spirit.deactivate_hint(spirit, "movement")

    detected = detect?(monster, room_exit)
    dodged   = dodge?(monster, room_exit)

    cond do
      detected and dodged ->
        Monster.send_scroll(monster, "<p><span class='yellow'>You detected a trap as you entered and nimbly dodged out of the way!</span></p>")
      detected and !dodged ->
        Monster.send_scroll(monster, "<p><span class='yellow'>You detected a trap as you entered but were too slow to avoid it!</span></p>")
        spring_trap!(monster, current_room, destination, room_exit)
      true ->
        spring_trap!(monster, current_room, destination, room_exit)
    end

    Systems.Room.display_room_in_scroll(spirit, monster, destination)
    Monster.pursue(current_room, monster, room_exit["direction"])
  end

  def spring_trap!(monster, current_room, destination, room_exit) do
    Monster.send_scroll(monster, "<p><span class='red'>#{interpolate(room_exit["mover_message"] |> to_string, %{"user" => monster})}</span></p>")

    Systems.Monster.observers(current_room, monster)
    |> Enum.each(fn(observer) ->
      Monster.send_scroll(observer, "<p><span class='dark-green'>#{interpolate(room_exit["from_message"] |> to_string, %{"user" => monster})}</span></p>")
    end)

    Systems.Monster.observers(destination, monster)
    |> Enum.each(fn(observer) ->
      Monster.send_scroll(observer, "<p><span class='dark-green'>#{interpolate(room_exit["to_message"] |> to_string, %{"user" => monster})}</span></p>")
    end)

    # todo: damage monster
    monster
  end

  def modifier(room_exit) do
    room_exit["damage"] * 20
  end

  def detect?(_monster, room_exit) do
    :random.seed(:os.timestamp)
    perception = 100 - modifier(room_exit)
    perception >= :random.uniform(100)
  end

  def dodge?(monster, room_exit) do
    :random.seed(:os.timestamp)
    dodge = Monster.modified_skill(monster, "dodge") - modifier(room_exit)
    dodge >= :random.uniform(100)
  end

end
