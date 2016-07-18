defmodule ApathyDrive.Room do
  use ApathyDrive.Web, :model
  alias ApathyDrive.{Ability, Area, Match, Mobile, Room, RoomServer, RoomUnity, Presence, PubSub}

  schema "rooms" do
    field :name,                     :string
    field :description,              :string
    field :light,                    :integer
    field :item_descriptions,        ApathyDrive.JSONB, default: %{"hidden" => %{}, "visible" => %{}}
    field :lair_size,                :integer
    field :lair_frequency,           :integer, default: 5
    field :exits,                    ApathyDrive.JSONB, default: []
    field :commands,                 ApathyDrive.JSONB, default: %{}
    field :legacy_id,                :string
    field :coordinates,              ApathyDrive.JSONB

    field :effects,                  :map, virtual: true, default: %{}
    field :lair_next_spawn_at,       :integer, virtual: true, default: 0
    field :timers,                   :map, virtual: true, default: %{}
    field :last_effect_key,          :integer, virtual: true, default: 0
    field :default_essence,          :integer, virtual: true
    field :mobiles,                  :any, virtual: true, default: []

    timestamps

    has_one    :room_unity, RoomUnity
    has_many   :persisted_mobiles, Mobile
    belongs_to :ability, Ability
    belongs_to :area, ApathyDrive.Area
    has_many   :lairs, ApathyDrive.LairMonster
    has_many   :lair_monsters, through: [:lairs, :monster_template]
  end

  def find_spirit(%Room{mobiles: mobiles}, spirit_id) do
    Enum.find(mobiles, &(&1.spirit && &1.spirit.id == spirit_id))
  end

  def update_mobile(%Room{} = room, %Mobile{} = mobile, update_fun) do
    update_in(room.mobiles, fn mobiles ->
      mobiles = List.delete(mobiles, mobile)
      mobile = update_fun.(mobile)
      [mobile | mobiles]
    end)
  end

  def world_map do
    from room in Room,
    where: not is_nil(room.coordinates),
    join: area in assoc(room, :area),
    join: room_unity in assoc(room, :room_unity),
    select: %{id: room.id, name: room.name, coords: room.coordinates, area: area.name, controlled_by: room_unity.controlled_by, exits: room.exits}
  end

  def controlled_by(%Room{} = room) do
    room.room_unity.controlled_by
  end

  def update_area(%Room{area: %Area{name: old_area}} = room, %Area{} = area) do
    PubSub.unsubscribe("areas:#{room.area_id}")
    room =
      room
      |> Map.put(:area, area)
      |> Map.put(:area_id, area.id)
      |> set_default_essence()
      |> Repo.save!
    PubSub.subscribe("areas:#{area.id}")
    ApathyDrive.Endpoint.broadcast!("map", "area_change", %{room_id: room.id, old_area: old_area, new_area: area.name})
    room
  end

  def set_default_essence(%Room{room_unity: %RoomUnity{controlled_by: nil}} = room) do
    room = Map.put(room, :default_essence, default_essence(room))
    put_in(room.room_unity.essences["default"], room.default_essence)
  end
  def set_default_essence(%Room{} = room) do
    Map.put(room, :default_essence, default_essence(room))
  end

  def adjacent_room_data(%Room{} = room, data \\ %{}) do
    Map.merge(data, %{
      essences: room.room_unity.essences,
      room_id: room.id,
      area: room.area.name,
      controlled_by: room.room_unity.controlled_by
    })
  end

  def update_controlled_by(%Room{room_unity: %RoomUnity{essences: essences}} = room) do
    controlled_by = room.room_unity.controlled_by

    highest_essence =
      essences
      |> Map.keys
      |> Enum.sort_by(&Map.get(essences, &1, 0), &>=/2)
      |> List.first

    new_controlled_by =
      cond do
        highest_essence == "good" and essences["good"] > 0 and (essences["good"] * 0.9) > essences["evil"] ->
          "good"
        highest_essence == "evil" and essences["evil"] > 0 and (essences["evil"] * 0.9) > essences["good"] ->
          "evil"
        true ->
          nil
      end

    if controlled_by != new_controlled_by do
      ApathyDrive.Endpoint.broadcast!("map", "room control change", %{room_id: room.id, controlled_by: new_controlled_by})

      put_in(room.room_unity.controlled_by, new_controlled_by)
      |> Repo.save
    else
      room
    end
  end

  def default_essence(%Room{area: %Area{level: level}}) do
    ApathyDrive.Level.exp_at_level(level)
  end

  def changeset(%Room{} = room, params \\ %{}) do
    room
    |> cast(params, ~w(name description exits), ~w(light item_descriptions lair_size lair_frequency commands legacy_id coordinates))
    |> validate_format(:name, ~r/^[a-zA-Z ,]+$/)
    |> validate_length(:name, min: 1, max: 30)
  end

  def find_mobile_in_room(%Room{} = room, mobile, query) do
    mobiles =
      Presence.metas("rooms:#{room.id}:mobiles")

    mobile =
      mobiles
      |> Enum.find(&(&1.mobile == mobile))

    mobiles
    |> Enum.reject(&(&1 == mobile))
    |> List.insert_at(-1, mobile)
    |> Enum.reject(&(&1 == nil))
    |> Match.one(:name_contains, query)
  end

  def datalist do
    __MODULE__
    |> Repo.all
    |> Enum.map(fn(mt) ->
         "#{mt.name} - #{mt.id}"
       end)
  end

  def start_room_id do
    ApathyDrive.Config.get(:start_room)
  end

  def find_item(%Room{room_unity: %RoomUnity{items: items}, item_descriptions: item_descriptions}, item) do
    actual_item = items
                  |> Enum.map(&(%{name: &1["name"], keywords: String.split(&1["name"]), item: &1}))
                  |> Match.one(:keyword_starts_with, item)

    visible_item = item_descriptions["visible"]
                   |> Map.keys
                   |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                   |> Match.one(:keyword_starts_with, item)

    hidden_item = item_descriptions["hidden"]
                  |> Map.keys
                  |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                  |> Match.one(:keyword_starts_with, item)

    cond do
      visible_item ->
        %{description: item_descriptions["visible"][visible_item.name]}
      hidden_item ->
        %{description: item_descriptions["hidden"][hidden_item.name]}
      actual_item ->
        actual_item.item
      true ->
        nil
    end
  end

  def get_exit(room, direction) do
    room
    |> Map.get(:exits)
    |> Enum.find(&(&1["direction"] == direction(direction)))
  end

  def mirror_exit(%Room{} = room, destination_id) do
    room
    |> Map.get(:exits)
    |> Enum.find(fn(%{"destination" => destination, "kind" => kind}) ->
         destination == destination_id and kind != "RemoteAction"
       end)
  end

  def command_exit(%Room{} = room, string) do
    room
    |> Map.get(:exits)
    |> Enum.find(fn(ex) ->
         ex["kind"] == "Command" and Enum.member?(ex["commands"], string)
       end)
  end

  def remote_action_exit(%Room{} = room, string) do
    room
    |> Map.get(:exits)
    |> Enum.find(fn(ex) ->
         ex["kind"] == "RemoteAction" and Enum.member?(ex["commands"], string)
       end)
  end

  def command(%Room{} = room, string) do
    command =
      room
      |> Map.get(:commands, %{})
      |> Map.keys
      |> Enum.find(fn(command) ->
           String.downcase(command) == String.downcase(string)
         end)

    if command do
      room.commands[command]
    end
  end

  def unlocked?(%Room{effects: effects}, direction) do
    effects
    |> Map.values
    |> Enum.filter(fn(effect) ->
         Map.has_key?(effect, :unlocked)
       end)
    |> Enum.map(fn(effect) ->
         Map.get(effect, :unlocked)
       end)
    |> Enum.member?(direction)
  end

  def temporarily_open?(%Room{} = room, direction) do
    room
    |> Map.get(:effects)
    |> Map.values
    |> Enum.filter(fn(effect) ->
         Map.has_key?(effect, :open)
       end)
    |> Enum.map(fn(effect) ->
         Map.get(effect, :open)
       end)
    |> Enum.member?(direction)
  end

  def searched?(room, direction) do
    room
    |> Map.get(:effects)
    |> Map.values
    |> Enum.filter(fn(effect) ->
         Map.has_key?(effect, :searched)
       end)
    |> Enum.map(fn(effect) ->
         Map.get(effect, :searched)
       end)
    |> Enum.member?(direction)
  end

  def exit_direction("up"),      do: "upwards"
  def exit_direction("down"),    do: "downwards"
  def exit_direction(direction), do: "to the #{direction}"

  def enter_direction(nil),       do: "nowhere"
  def enter_direction("up"),      do: "above"
  def enter_direction("down"),    do: "below"
  def enter_direction(direction), do: "the #{direction}"

  def send_scroll(%Room{mobiles: mobiles}, html) do
    Enum.each(mobiles, &Mobile.send_scroll(&1, html))
  end

  def open!(%Room{} = room, direction) do
    if open_duration = get_exit(room, direction)["open_duration_in_seconds"] do
      Systems.Effect.add(room, %{open: direction}, open_duration)
    else
      exits = room.exits
              |> Enum.map(fn(room_exit) ->
                   if room_exit["direction"] == direction do
                     Map.put(room_exit, "open", true)
                   else
                     room_exit
                   end
                 end)
      Map.put(room, :exits, exits)
    end
  end

  def close!(%Room{effects: effects} = room, direction) do
    room = effects
           |> Map.keys
           |> Enum.filter(fn(key) ->
                effects[key][:open] == direction
              end)
           |> Enum.reduce(room, fn(room, key) ->
                Systems.Effect.remove(room, key, show_expiration_message: true)
              end)

    exits = room.exits
            |> Enum.map(fn(room_exit) ->
                 if room_exit["direction"] == direction do
                   Map.delete(room_exit, "open")
                 else
                   room_exit
                 end
               end)

    room = Map.put(room, :exits, exits)

    unlock!(room, direction)
  end

  def lock!(%Room{effects: effects} = room, direction) do
    effects
    |> Map.keys
    |> Enum.filter(fn(key) ->
         effects[key][:unlocked] == direction
       end)
    |> Enum.reduce(room, fn(key, room) ->
         Systems.Effect.remove(room, key, show_expiration_message: true)
       end)
  end

  def get_direction_by_destination(%Room{exits: exits}, destination_id) do
    exit_to_destination = exits
                          |> Enum.find(fn(room_exit) ->
                               room_exit["destination"] == destination_id
                             end)
    exit_to_destination && exit_to_destination["direction"]
  end

  defp unlock!(%Room{} = room, direction) do
    unlock_duration = if open_duration = get_exit(room, direction)["open_duration_in_seconds"] do
      open_duration
    else
      10#300
    end

    Systems.Effect.add(room, %{unlocked: direction}, unlock_duration)
    # todo: tell players in the room when it re-locks
    #"The #{name} #{ApathyDrive.Exit.direction_description(exit["direction"])} just locked!"
  end

  def direction(direction) do
    case direction do
      "n" ->
        "north"
      "ne" ->
        "northeast"
      "e" ->
        "east"
      "se" ->
        "southeast"
      "s" ->
        "south"
      "sw" ->
        "southwest"
      "w" ->
        "west"
      "nw" ->
        "northwest"
      "u" ->
        "up"
      "d" ->
        "down"
      direction ->
        direction
    end
  end
  
  def report_essence(%Room{exits: exits, room_unity: %RoomUnity{essences: essences}} = room) do
    Enum.each(exits, fn(%{"destination" => dest, "direction" => direction, "kind" => kind}) ->
      unless kind in ["Cast", "RemoteAction"] do

        report = %{
          essences: essences,
          room_id: room.id,
          direction: direction,
          kind: kind,
          legacy_id: room.legacy_id,
          area: room.area.name,
          controlled_by: room.room_unity.controlled_by
        }

        dest
        |> RoomServer.find()
        |> send({:essence_report, report})
      end
    end)
  end

  def update_essence(%Room{room_unity: %RoomUnity{essences: essences}} = room) do
    room = if Enum.any?(room.room_unity.essence_targets), do: room, else: update_essence_targets(room)

    room =
      essences
      |> Enum.reduce(room, fn({essence, amount}, %Room{room_unity: %RoomUnity{essence_targets: essence_targets}} = updated_room) ->
           target = get_in(essence_targets, [essence, "target"])
           difference = target - amount
           amount_to_shift = difference / 10 / 60

           if abs(amount_to_shift) < 1 or difference == 0 or (amount > 0 and (1 - (abs(difference) / amount)) < 0.01) do
             put_in(updated_room.room_unity.essences[essence], target)
           else
             update_in(updated_room.room_unity.essences[essence], &(max(0, &1 + amount_to_shift)))
           end
         end)
      |> Room.update_controlled_by

    data =
      %{
        room_id: room.id,
        good: trunc(room.room_unity.essences["good"]),
        default: trunc(room.room_unity.essences["default"]),
        evil: trunc(room.room_unity.essences["evil"]),
      }

    ApathyDrive.PubSub.broadcast!("rooms:#{room.id}:mobiles", {:update_room_essence, data})

    room
  end

  def update_essence_targets(%Room{room_unity: %RoomUnity{exits: exits, essences: current_essences, controlled_by: controlled_by}} = room) do
    initial_essences =
      %{"good"    => %{"adjacent" => [],
                       "mobile" => []},
        "evil"    => %{"adjacent" => [],
                       "mobile" => []},
        "default" => %{"adjacent" => [],
                       "mobile" => []}}

    area_exits =
      exits
      |> Enum.filter(fn({_direction, data}) ->
           data["area"] == room.area.name
         end)
      |> Enum.into(%{})

    {essences, control_amount} =
      cond do
        room.lair_next_spawn_at > 0 and room.default_essence > 0 and controlled_by == nil ->
          {put_in(initial_essences["default"]["control"], room.default_essence), room.default_essence}
        room.lair_next_spawn_at > 0 and room.default_essence > current_essences[controlled_by] ->
          {put_in(initial_essences[controlled_by]["control"], room.default_essence), room.default_essence}
        true ->
          {initial_essences, nil}
      end

    essences =
      area_exits
      |> Map.values
      |> Enum.map(&(&1["essences"]))
      |> Enum.reduce(essences, fn(exit_essences, adjacent_essences) ->
           adjacent_essences
           |> update_in(["good", "adjacent"],    &([exit_essences["good"] | &1]))
           |> update_in(["evil", "adjacent"],    &([exit_essences["evil"] | &1]))
           |> update_in(["default", "adjacent"], &([exit_essences["default"] | &1]))
         end)

    essences =
      "rooms:#{room.id}:mobiles"
      |> Presence.metas()
      |> Enum.reduce(essences, fn
           %{invisible?: true}, updated_essences ->
             updated_essences
           %{spirit_essence: nil, unities: []} = mobile, updated_essences ->
             add_mobile_essence(updated_essences, ["default"], mobile.essence)
           %{spirit_essence: nil} = mobile, updated_essences ->
             add_mobile_essence(updated_essences, mobile.unities, mobile.essence)
           mobile, updated_essences ->
             add_mobile_essence(updated_essences, mobile.spirit_unities, mobile.spirit_essence)
         end)

    essences =
      essences
      |> Enum.reduce(essences, fn({unity, %{"adjacent" => adj, "mobile" => mobile}}, updated_essences) ->
           updated_essences
           |> put_in([unity, "adjacent"], average(adj))
           |> put_in([unity, "mobile"], average(mobile))
         end)

    essences =
      essences
      |> Enum.reduce(essences, fn
           {_unity, %{"control" => _control}}, updated_essences ->
             updated_essences
           {unity, _targets}, updated_essences ->
             if control_amount && updated_essences[unity]["adjacent"] do
               update_in(updated_essences, [unity, "adjacent"], &(max(0, &1 - control_amount)))
             else
               updated_essences
             end
         end)

    essences =
      essences
      |> Enum.reduce(essences, fn({unity, %{} = targets}, updated_essences) ->
           target =
             [targets["adjacent"], targets["mobile"], targets["control"] || nil]
             |> Enum.reject(&(&1 == nil))
             |> average()

           put_in(updated_essences[unity]["target"], target || 0)
         end)

    put_in(room.room_unity.essence_targets, essences)
  end

  def average([]), do: nil
  def average(list) do
    Enum.sum(list) / length(list)
  end

  defp add_mobile_essence(essences, mobile_unities, mobile_essence) do
    Enum.reduce(essences, essences, fn({unity, _list}, updated_essences) ->
      if unity in mobile_unities do
        updated_essences
        |> update_in([unity, "mobile"], &([mobile_essence | &1]))
      else
        updated_essences
      end
    end)
  end

end
