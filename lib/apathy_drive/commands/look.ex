defmodule ApathyDrive.Commands.Look do
  require Logger
  use ApathyDrive.Command
  alias ApathyDrive.{Doors, Mobile, Match, RoomServer}

  @directions ["n", "north", "ne", "northeast", "e", "east",
              "se", "southeast", "s", "south", "sw", "southwest",
               "w", "west", "nw", "northwest", "u", "up", "d", "down"]

  def keywords, do: ["look", "l"]

  def execute(%Room{} = room, %Mobile{} = mobile, args) do
    if blind?(mobile) do
      Mobile.send_scroll(mobile, "<p>You are blind.</p>")
    else
      look(room, mobile, args)
    end
    room
  end

  def look(%Room{id: id} = room, %Mobile{room_id: room_id} = mobile, []) when id != room_id do
    peek(room, mobile, room_id)
    look(room, Map.put(mobile, :room_id, id), [])
  end

  def look(%Room{} = room, %Mobile{} = mobile, []) do
    name_color =
      case Room.controlled_by(room) do
        "evil" ->
          "magenta"
        "good" ->
          "white"
        _ ->
          "cyan"
      end

    good = Map.get(room.room_unity.essences, "good", 0)
    evil = Map.get(room.room_unity.essences, "evil", 0)
    default = Map.get(room.room_unity.essences, "default", 0)

    Mobile.send_scroll(mobile, "<p><span class='#{name_color}'>#{room.name}</span> (<span class='white room-#{room.id}-good'>#{trunc(good)}</span>/<span class='cyan room-#{room.id}-default'>#{trunc(default)}</span>/<span class='magenta room-#{room.id}-evil'>#{trunc(evil)}</span>)</p>")
    Mobile.send_scroll(mobile, "<p>    #{room.description}</p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-cyan'>#{look_items(room)}</span></p>")
    Mobile.send_scroll(mobile, look_mobiles(room, mobile))
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>#{look_directions(room)}</span></p>")
    if room.light do
      Mobile.send_scroll(mobile, "<p>#{light_desc(room.light)}</p>")
    end
  end

  def look(%Room{} = room, %Mobile{} = mobile, arguments) when is_list(arguments) do
    cond do
      Enum.member?(@directions, Enum.join(arguments, " ")) ->
        room_exit = Room.get_exit(room, Enum.join(arguments, " "))
        look(room, mobile, room_exit)
      target = Room.find_mobile_in_room(room, mobile, Enum.join(arguments, " ")) ->
        look_at_mobile(target, mobile)
      target = Room.find_item(room, Enum.join(arguments, " ")) ->
        look_at_item(mobile, target)
      true ->
        look_at_item(mobile, Enum.join(arguments, " "))
    end
  end

  def look(%Room{}, %Mobile{} = mobile, nil) do
    Mobile.send_scroll(mobile, "<p>There is no exit in that direction!</p>")
  end

  def look(%Room{}, %Mobile{} = mobile, %{"kind" => kind}) when kind in ["RemoteAction", "Command"] do
    Mobile.send_scroll(mobile, "<p>There is no exit in that direction!</p>")
  end

  def look(%Room{} = room, %Mobile{} = mobile, %{"kind" => "Door"} = room_exit) do
    if Doors.open?(room, room_exit) do
      look(room, mobile, Map.put(room_exit, "kind", "Normal"))
    else
      Mobile.send_scroll(mobile, "<p>The door is closed in that direction!</p>")
    end
  end

  def look(%Room{} = room, %Mobile{} = mobile, %{"kind" => "Hidden"} = room_exit) do
    if Doors.open?(room, room_exit) do
      look(room, mobile, Map.put(room_exit, "kind", "Normal"))
    else
      Mobile.send_scroll(mobile, "<p>There is no exit in that direction!</p>")
    end
  end

  def look(%Room{}, %Mobile{} = mobile, %{"destination" => destination}) do
    destination
    |> RoomServer.find
    |> RoomServer.look(mobile, [])
  end

  def peek(%Room{} = room, name, room_id) do
    mirror_exit = Room.mirror_exit(room, room_id)

    if mirror_exit do
      message = "#{Mobile.look_name(name)} peeks in from #{Room.enter_direction(mirror_exit["direction"])}!"

      Room.send_scroll(room, "<p><span class='dark-magenta'>#{message}</span></p>")
    end
  end

  def look_at_mobile(%Mobile{crippled_limbs: crippled, missing_limbs: missing} = target, %Mobile{} = mobile) do
    Mobile.send_scroll(target, "<p>#{name} looks you over.</p>")

    hp_percentage = round(100 * (target.hp / target.max_hp))

    hp_description = case hp_percentage do
      _ when hp_percentage >= 100 ->
        "unwounded"
      _ when hp_percentage >= 90 ->
        "slightly wounded"
      _ when hp_percentage >= 60 ->
        "moderately wounded"
      _ when hp_percentage >= 40 ->
        "heavily wounded"
      _ when hp_percentage >= 20 ->
        "severely wounded"
      _ when hp_percentage >= 10 ->
        "critically wounded"
      _ ->
        "very critically wounded"
    end

    hp_description =
      "{{target:He/She/It}} appears to be #{hp_description}."
      |> interpolate(%{"target" => target})

    limbs =
      Enum.reduce crippled, [], fn limb, limbs ->
        ["{{target:His/Her/It's}} #{limb} appears to be crippled." |> interpolate(%{"target" => target}), limbs]
      end

    limbs =
      Enum.reduce missing, limbs, fn limb, limbs ->
        ["{{target:His/Her/It's}} #{limb} has been severed, and is bleeding profusely!" |> interpolate(%{"target" => target}), limbs]
      end

    limb_description = Enum.join(limbs, " ")

    Mobile.send_scroll(mobile, "<p>#{Mobile.look_name(target)}</p>")
    Mobile.send_scroll(mobile, "<p>#{target.description} #{limb_description}</p>")
    Mobile.send_scroll(mobile, "<p>#{hp_description}</p>")
  end

  def look_mobiles(%Room{mobiles: mobiles}, mobile \\ nil) do
    mobiles_to_show =
      mobiles
      |> Map.values
      |> Enum.reduce([], fn(%{monster_template_id: mt_id} = room_mobile, list) ->
           if mobile == room_mobile or is_nil(mt_id) do
             list
           else
             [Mobile.look_name(room_mobile) | list]
           end
         end)

    if Enum.any?(mobiles_to_show) do
      "<p><span class='dark-magenta'>Also here:</span> #{Enum.join(mobiles_to_show, ", ")}<span class='dark-magenta'>.</span></p>"
    else
      ""
    end
  end

  def light_desc(light_level)  when light_level <= -100, do: "The room is barely visible"
  def light_desc(light_level)  when light_level <=  -25, do: "The room is dimly lit"
  def light_desc(_light_level), do: nil

  def display_direction(%{"kind" => "Gate", "direction" => direction} = room_exit, room) do
    if Doors.open?(room, room_exit), do: "open gate #{direction}", else: "closed gate #{direction}"
  end
  def display_direction(%{"kind" => "Door", "direction" => direction} = room_exit, room) do
    if Doors.open?(room, room_exit), do: "open door #{direction}", else: "closed door #{direction}"
  end
  def display_direction(%{"kind" => "Hidden"} = room_exit, room) do
    if Doors.open?(room, room_exit), do: room_exit["description"]
  end
  def display_direction(%{"kind" => kind}, _room) when kind in ["Command", "RemoteAction"], do: nil
  def display_direction(%{"direction" => direction}, _room), do: direction

  def exit_directions(%Room{} = room) do
    room.exits
    |> Enum.map(fn(room_exit) ->
        display_direction(room_exit, room)
       end)
    |> Enum.reject(&(&1 == nil))
  end

  def look_directions(%Room{} = room) do
    case exit_directions(room) do
      [] ->
        "Obvious exits: NONE"
      directions ->
        "Obvious exits: #{Enum.join(directions, ", ")}"
    end
  end

  def look_items(%Room{} = room) do
    psuedo_items = room.item_descriptions["visible"]
                   |> Map.keys

    items = case room.room_unity.items do
      nil ->
        []
      items ->
        items
        |> Enum.map(&(&1["name"]))
    end

    items = items ++ psuedo_items

    case Enum.count(items) do
      0 ->
        ""
      _ ->
        "You notice #{Enum.join(items, ", ")} here."
    end
  end

  def blind?(%Mobile{} = mobile) do
    mobile.effects
    |> Map.values
    |> Enum.any?(&(Map.has_key?(&1, "blinded")))
  end

  def look_at_item(mobile, %{description: description}) do
    Mobile.send_scroll mobile, "<p>#{description}</p>"
  end

  def look_at_item(%Mobile{} = mobile, %{} = item) do
    Mobile.send_scroll(mobile, "\n\n")

    Mobile.send_scroll(mobile, "<p><span class='cyan'>#{item["name"]}</span></p>")
    Mobile.send_scroll(mobile, "<p>#{item["description"]}</p>\n\n")

    current =
      mobile
      |> Mobile.score_data

    %{equipped: _, mobile: equipped} =
      mobile
      |> ApathyDrive.Commands.Wear.equip_item(item)

    equipped = Mobile.score_data(equipped)

    score_data =
      current
      |> Map.take([:max_hp, :max_mana, :physical_damage, :magical_damage, :physical_defense, :magical_defense, :strength, :agility, :will])
      |> Enum.reduce(%{}, fn({key, val}, values) ->
           Map.put(values, key, value(val, equipped[key]))
         end)

    Mobile.send_scroll(mobile, "<p><span class='dark-yellow'>Changes if Equipped:</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Max HP:</span> <span class='dark-cyan'>#{score_data.max_hp}</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Max Mana:</span> <span class='dark-cyan'>#{score_data.max_mana}</span></p>")

    Mobile.send_scroll(mobile, "\n\n")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Physical Damage:</span> <span class='dark-cyan'>#{score_data.physical_damage}</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Magical Damage:</span>  <span class='dark-cyan'>#{score_data.magical_damage}</span></p>")
    Mobile.send_scroll(mobile, "\n\n")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Physical Defense:</span> <span class='dark-cyan'>#{score_data.physical_defense}</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Magical Defense:</span> <span class='dark-cyan'>#{score_data.magical_defense}</span></p>")
    Mobile.send_scroll(mobile, "\n\n")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Strength:</span> <span class='dark-cyan'>#{score_data.strength}</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Agility:</span>  <span class='dark-cyan'>#{score_data.agility}</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>Will:</span>     <span class='dark-cyan'>#{score_data.will}</span></p>")
  end

  def look_at_item(%Mobile{} = mobile, item_name) do
    case find_item(mobile, item_name) do
      nil ->
        Mobile.send_scroll(mobile, "<p>You do not notice that here.</p>")
      item ->
        look_at_item(mobile, item)
    end
  end

  defp value(pre, post) when pre > post and is_float(pre) and is_float(post) do
    "#{Float.to_string(post, decimals: 2)}(<span class='dark-red'>#{Float.to_string(post - pre, decimals: 2)}</span>)"
  end
  defp value(pre, post) when pre > post do
    "#{post}(<span class='dark-red'>#{post - pre}</span>)"
  end
  defp value(pre, post) when pre < post and is_float(pre) and is_float(post) do
    "#{Float.to_string(post, decimals: 2)}(<span class='green'>+#{Float.to_string(post - pre, decimals: 2)}</span>)"
  end
  defp value(pre, post) when pre < post do
    "#{post}(<span class='green'>+#{post - pre}</span>)"
  end
  defp value(_pre, post) when is_float(post) do
    "#{Float.to_string(post, decimals: 2)}"
  end
  defp value(_pre, post) do
    "#{post}"
  end

  defp find_item(%Mobile{spirit: %Spirit{inventory: inventory, equipment: equipment}}, item) do
    item = (inventory ++ equipment)
           |> Enum.map(&(%{name: &1["name"], keywords: String.split(&1["name"]), item: &1}))
           |> Match.one(:keyword_starts_with, item)

    case item do
      nil ->
        nil
      %{item: item} ->
        item
    end
  end


end
