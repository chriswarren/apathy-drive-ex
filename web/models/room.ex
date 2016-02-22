defmodule Room do
  require Logger
  use ApathyDrive.Web, :model
  use GenServer
  use Timex
  alias ApathyDrive.{PubSub, Mobile, TimerManager, Ability, World}

  schema "rooms" do
    field :name,                  :string
    field :keywords,              {:array, :string}
    field :description,           :string
    field :effects,               :any, virtual: true, default: %{}
    field :light,                 :integer
    field :item_descriptions,     ApathyDrive.JSONB, default: %{"hidden" => %{}, "visible" => %{}}
    field :lair_size,             :integer
    field :lair_frequency,        :integer, default: 5
    field :lair_next_spawn_at,    :any, virtual: true, default: 0
    field :lair_faction,          :string
    field :exits,                 ApathyDrive.JSONB, default: []
    field :commands,              ApathyDrive.JSONB, default: %{}
    field :legacy_id,             :string
    field :timers,                :any, virtual: true, default: %{}
    field :room_ability,          :any, virtual: true
    field :items,                 ApathyDrive.JSONB, default: []
    field :last_effect_key,       :any, virtual: true, default: 0

    timestamps

    has_many   :mobiles, Mobile
    belongs_to :ability, Ability
    has_many   :lairs, ApathyDrive.LairMonster
    has_many   :lair_monsters, through: [:lairs, :monster]
  end

  def init(id) do
    :random.seed(:os.timestamp)

    room = Repo.get!(Room, id)
    PubSub.subscribe(self, "rooms")
    PubSub.subscribe(self, "rooms:#{room.id}")

    room.exits
    |> Enum.each(fn(room_exit) ->
         PubSub.subscribe(self, "rooms:#{room_exit["destination"]}:adjacent")
       end)

    send(self, :spawn_permanent_monsters)

    if room.lair_size && Enum.any?(ApathyDrive.LairMonster.monsters_template_ids(id)) do
      send(self, :spawn_monsters)
    end

    if room.ability_id do
      PubSub.subscribe(self, "rooms:abilities")

      room =
        room
        |> Map.put(:room_ability, ApathyDrive.Repo.get(Ability, room.ability_id).properties)
        |> TimerManager.send_every({:execute_room_ability, 5_000, :execute_room_ability})
    end


    {:ok, World.add_room(room)}
  end

  def changeset(%Room{} = room, params \\ :empty) do
    room
    |> cast(params, ~w(name description exits), ~w(light item_descriptions lair_size lair_frequency lair_faction commands legacy_id))
    |> validate_format(:name, ~r/^[a-zA-Z ,]+$/)
    |> validate_length(:name, min: 1, max: 30)
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

  def find(id) do
    case :global.whereis_name(:"room_#{id}") do
      :undefined ->
        load(id)
      room ->
        room
    end
  end

  def load(id) do
    case Supervisor.start_child(ApathyDrive.Supervisor, {:"room_#{id}", {GenServer, :start_link, [Room, id, [name: {:global, :"room_#{id}"}]]}, :permanent, 5000, :worker, [Room]}) do
      {:error, {:already_started, pid}} ->
        pid
      {:ok, pid} ->
        # Hack to give the newly spawned pid a chance to handle messages in its mailbox before returning it
        # e.g. load monsters etc
        #:timer.sleep(50)
        pid
    end
  end

  def all do
    PubSub.subscribers("rooms")
  end

  def get_look_data(room, mobile) do
    room = World.room(room)

    %{
      name: room.name,
      description: room.description,
      items: look_items(room),
      mobiles: look_mobiles(%{room_id: room.id, mobile: mobile}),
      exits: look_directions(room),
      light: light_desc(room.light)
    }
  end

  def get_item(room, item) do
    GenServer.call(room, {:get_item, item})
  end

  def destroy_item(room, item) do
    GenServer.call(room, {:destroy_item, item})
  end

  def id(room) do
    room
    |> World.room
    |> Map.get(:id)
  end

  def exits(room) do
    room
    |> World.room
    |> Map.get(:exits)
  end

  def find_item(room, item) do
    %Room{items: items, item_descriptions: item_descriptions} = World.room(room)

    actual_item = items
                  |> Enum.map(&(%{name: &1["name"], keywords: String.split(&1["name"]), item: &1}))
                  |> Systems.Match.one(:keyword_starts_with, item)

    visible_item = item_descriptions["visible"]
                   |> Map.keys
                   |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                   |> Systems.Match.one(:keyword_starts_with, item)

    hidden_item = item_descriptions["hidden"]
                  |> Map.keys
                  |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                  |> Systems.Match.one(:keyword_starts_with, item)

    cond do
      visible_item ->
        item_descriptions["visible"][visible_item.name]
      hidden_item ->
        item_descriptions["hidden"][hidden_item.name]
      actual_item ->
        actual_item.item
      true ->
        nil
    end
  end

  def item_names(room) do
    room
    |> World.room
    |> Map.get(:items)
    |> Enum.map(&(&1["name"]))
  end

  def get_exit(room, direction) when is_pid(room) do
    room
    |> World.room
    |> get_exit(direction)
  end

  def get_exit(room, direction) do
    room
    |> Map.get(:exits)
    |> Enum.find(&(&1["direction"] == direction(direction)))
  end

  def mirror_exit(room, destination_id) do
    room
    |> World.room
    |> Map.get(:exits)
    |> Enum.find(fn(%{"destination" => destination, "kind" => kind}) ->
         destination == destination_id and kind != "RemoteAction"
       end)
  end

  def command_exit(room, string) do
    room
    |> World.room
    |> Map.get(:exits)
    |> Enum.find(fn(ex) ->
         ex["kind"] == "Command" and Enum.member?(ex["commands"], string)
       end)
  end

  def remote_action_exit(room, string) do
    room
    |> World.room
    |> Map.get(:exits)
    |> Enum.find(fn(ex) ->
         ex["kind"] == "RemoteAction" and Enum.member?(ex["commands"], string)
       end)
  end

  def command(room, string) do
    room = World.room(room)

    command =
      room
      |> Map.get(:commands)
      |> Map.keys
      |> Enum.find(fn(command) ->
           String.downcase(command) == String.downcase(string)
         end)

    room.commands[command]
  end

  def add_item(room, item) do
    GenServer.cast(room, {:add_item, item})
  end

  def add_items(room, items) do
    GenServer.cast(room, {:add_items, items})
  end

  def auto_move_exit(room, last_room) when is_pid(room) do
    room = World.room(room)

    case room.exits do
      nil ->
        nil
      exits ->
        case last_room do
          %{id: last_room_id, name: last_room_name} ->
            exit_to_last_room = Enum.find(exits, &(&1["destination"] == last_room_id))

            words_in_common =
              MapSet.intersection(MapSet.new(Regex.scan(~r/\w+/, last_room_name)
                                      |> List.flatten
                                      |> Enum.uniq),
                           MapSet.new(Regex.scan(~r/\w+/, room.name)
                                      |> List.flatten
                                      |> Enum.uniq))

            if Enum.any?(words_in_common) do
              new_exits =
                exits
                |> Enum.reject(&(&1 == exit_to_last_room))

              if Enum.any?(new_exits) do
                %{new_exit: Enum.random(new_exits), last_room: %{id: room.id, name: room.name}}
              else
                %{new_exit: exit_to_last_room, last_room: last_room}
              end
            else
              %{new_exit: exit_to_last_room, last_room: %{id: room.id, name: last_room.name}}
            end
          nil ->
            if Enum.any?(exits), do: %{new_exit: Enum.random(exits), last_room: %{id: room.id, name: room.name}}
        end
    end
  end

  def unlocked?(room, direction) do
    %Room{effects: effects} = World.room(room)

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

  def temporarily_open?(room, direction) when is_pid(room) do
    room
    |> World.room
    |> temporarily_open?(direction)
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

  def searched?(room, direction) when is_pid(room) do
    room
    |> World.room
    |> searched?(direction)
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

  def triggered?(room, direction) do
    room
    |> World.room
    |> Map.get(:effects)
    |> Map.values
    |> Enum.filter(fn(effect) ->
         Map.has_key?(effect, :triggered)
       end)
    |> Enum.map(fn(effect) ->
         Map.get(effect, :triggered)
       end)
    |> Enum.member?(direction)
  end

  def look_at_room(room, mobile) do
    data = get_look_data(room, mobile)

    Mobile.send_scroll(mobile, "<p><span class='cyan'>#{data.name}</span></p>")
    Mobile.send_scroll(mobile, "<p>    #{data.description}</p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-cyan'>#{data.items}</span></p>")
    Mobile.send_scroll(mobile, "<p>#{data.mobiles}</p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>#{data.exits}</span></p>")
    if data.light do
      Mobile.send_scroll(mobile, "<p>#{data.light}</p>")
    end
  end

  def exit_direction("up"),      do: "upwards"
  def exit_direction("down"),    do: "downwards"
  def exit_direction(direction), do: "to the #{direction}"

  def enter_direction(nil),       do: "nowhere"
  def enter_direction("up"),      do: "above"
  def enter_direction("down"),    do: "below"
  def enter_direction(direction), do: "the #{direction}"

  def sound_direction("up"),      do: "above you"
  def sound_direction("down"),    do: "below you"
  def sound_direction(direction), do: "to the #{direction}"

  def spawned_monsters(room_id) when is_integer(room_id), do: PubSub.subscribers("rooms:#{room_id}:spawned_monsters")
  def spawned_monsters(room),   do: PubSub.subscribers("rooms:#{World.room(room).id}:spawned_monsters")

  # Value functions
  def mobiles(%{room_id: room_id, mobile: pid}) do
    PubSub.subscribers("rooms:#{room_id}:mobiles", [pid])
  end

  def mobiles(%Mobile{room_id: room_id}) do
    PubSub.subscribers("rooms:#{room_id}:mobiles")
  end

  def mobiles(%Room{} = room) do
    PubSub.subscribers("rooms:#{room.id}:mobiles")
  end

  def exit_directions(%Room{} = room) do
    room.exits
    |> Enum.map(fn(room_exit) ->
         :"Elixir.ApathyDrive.Exits.#{room_exit["kind"]}".display_direction(room, room_exit)
       end)
    |> Enum.reject(&(&1 == nil))
  end

  def light_desc(light_level)  when light_level <= -100, do: "The room is barely visible"
  def light_desc(light_level)  when light_level <=  -25, do: "The room is dimly lit"
  def light_desc(_light_level), do: nil

  def look_items(%Room{} = room) do
    psuedo_items = room.item_descriptions["visible"]
                   |> Map.keys

    items = case room.items do
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

  def look_mobiles(%{room_id: room_id, mobile: mobile}) do
    pid = if is_pid(mobile), do: mobile, else: mobile.pid
    mobiles = mobiles(%{room_id: room_id, mobile: pid})
              |> Enum.map(&Mobile.look_name/1)
              |> Enum.join("<span class='magenta'>, </span>")

    case(mobiles) do
      "" ->
        ""
      mobiles ->
        "<span class='dark-magenta'>Also here:</span> #{mobiles}<span class='dark-magenta'>.</span>"
    end
  end

  def look_mobiles(%Room{} = room) do
    mobiles = mobiles(room)
               |> Enum.map(&Mobile.look_name/1)
               |> Enum.join("<span class='magenta'>, </span>")

    case(mobiles) do
      "" ->
        ""
      mobiles ->
        "<span class='dark-magenta'>Also here:</span> #{mobiles}<span class='dark-magenta'>.</span>"
    end
  end

  def look_directions(%Room{} = room) do
    case exit_directions(room) do
      [] ->
        "Obvious exits: NONE"
      directions ->
        "Obvious exits: #{Enum.join(directions, ", ")}"
    end
  end

  def send_scroll(%Room{id: id}, html) do
    ApathyDrive.Endpoint.broadcast! "rooms:#{id}:mobiles", "scroll", %{:html => html}
  end
  def send_scroll(room, html) do
    ApathyDrive.Endpoint.broadcast! "rooms:#{Room.id(room)}:mobiles", "scroll", %{:html => html}
  end

  def open!(room, direction) when is_pid(room) do
    GenServer.call(room, {:open, direction})
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

  def close!(room, direction) when is_pid(room) do
    GenServer.call(room, {:close, direction})
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

  def lock!(room, direction) when is_pid(room) do
    GenServer.call(room, {:lock, direction})
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

  def handle_call({:destroy_item, item}, _from, %Room{items: items, item_descriptions: item_descriptions} = room) do
    actual_item = items
                  |> Enum.map(&(%{name: &1["name"], keywords: String.split(&1["name"]), item: &1}))
                  |> Systems.Match.one(:name_contains, item)

    visible_item = item_descriptions["visible"]
                   |> Map.keys
                   |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                   |> Systems.Match.one(:keyword_starts_with, item)

    hidden_item = item_descriptions["hidden"]
                  |> Map.keys
                  |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                  |> Systems.Match.one(:keyword_starts_with, item)

    cond do
      visible_item ->
        {:reply, {:cant_destroy, visible_item.name}, room}
      hidden_item ->
        {:reply, {:cant_destroy, hidden_item.name}, room}
      actual_item ->
        room =
          room
          |> Map.put(:items, List.delete(room.items, actual_item.item))
          |> Repo.save!
        {:reply, {:ok, actual_item.item}, room}
      true ->
        {:reply, :not_found, room}
    end
  end

  def handle_call({:get_item, item}, _from, %Room{items: items, item_descriptions: item_descriptions} = room) do
    actual_item = items
                  |> Enum.map(&(%{name: &1["name"], keywords: String.split(&1["name"]), item: &1}))
                  |> Systems.Match.one(:name_contains, item)

    visible_item = item_descriptions["visible"]
                   |> Map.keys
                   |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                   |> Systems.Match.one(:keyword_starts_with, item)

    hidden_item = item_descriptions["hidden"]
                  |> Map.keys
                  |> Enum.map(&(%{name: &1, keywords: String.split(&1)}))
                  |> Systems.Match.one(:keyword_starts_with, item)

    cond do
      visible_item ->
        {:reply, {:cant_get, visible_item.name}, room}
      hidden_item ->
        {:reply, {:cant_get, hidden_item.name}, room}
      actual_item ->
        room =
          room
          |> Map.put(:items, List.delete(room.items, actual_item.item))
          |> Repo.save!
        {:reply, actual_item.item, room}
      true ->
        {:reply, :not_found, room}
    end
  end

  def handle_call({:open, direction}, _from, room) do
    room = open!(room, direction)
    {:reply, room, World.add_room(room)}
  end

  def handle_call({:close, direction}, _from, room) do
    room = close!(room, direction)
    {:reply, room, World.add_room(room)}
  end

  def handle_call({:lock, direction}, _from, room) do
    room = lock!(room, direction)
    {:reply, room, World.add_room(room)}
  end

  def handle_cast({:add_item, item}, %Room{items: items} = room) do
    room =
      put_in(room.items, [item | items])
      |> Repo.save!

    {:noreply, World.add_room(room)}
  end

  def handle_cast({:add_items, new_items}, %Room{items: items} = room) do
    room =
      put_in(room.items, new_items ++ items)
      |> Repo.save!

    {:noreply, World.add_room(room)}
  end

  # GenServer callbacks
  def handle_info(:spawn_permanent_monsters, room) do

    ApathyDrive.Mobile.permanent_monsters_in_room(room.id)
    |> Enum.each(fn(mobile) ->
         mobile_pid =
          mobile
          |> Map.put(:permanent, true)
          |> MonsterTemplate.spawn

         room_pid = self
         Task.start fn ->
           ApathyDrive.Exits.Normal.display_enter_message(room_pid, mobile_pid)
         end
       end)

    {:noreply, room}
  end

  def handle_info(:spawn_monsters,
                  %{:lair_next_spawn_at => lair_next_spawn_at} = room) do

    if Date.to_secs(Date.now) >= lair_next_spawn_at do
      ApathyDrive.LairSpawning.spawn_lair(room)

      room = room
             |> Map.put(:lair_next_spawn_at, Date.now
                                             |> Date.shift(mins: room.lair_frequency)
                                             |> Date.to_secs)
    end

    :erlang.send_after(5000, self, :spawn_monsters)

    {:noreply, World.add_room(room)}
  end

  def handle_info({:door_bashed_open, %{direction: direction}}, room) do
    room = open!(room, direction)

    room_exit = get_exit(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_bash, mirror_exit})
    end

    {:noreply, World.add_room(room)}
  end

  def handle_info({:mirror_bash, room_exit}, room) do
    room = open!(room, room_exit["direction"])
    {:noreply, World.add_room(room)}
  end

  def handle_info({:door_bash_failed, %{direction: direction}}, room) do
    room_exit = get_exit(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_bash_failed, mirror_exit})
    end

    {:noreply, World.add_room(room)}
  end

  def handle_info({:door_opened, %{direction: direction}}, room) do
    room = open!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_open, mirror_exit})
    end

    {:noreply, World.add_room(room)}
  end

  def handle_info({:mirror_open, room_exit}, room) do
    room = open!(room, room_exit["direction"])
    {:noreply, World.add_room(room)}
  end

  def handle_info({:door_closed, %{direction: direction}}, room) do
    room = close!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_close, mirror_exit})
    end

    {:noreply, World.add_room(room)}
  end

  def handle_info({:mirror_close, room_exit}, room) do
    room = close!(room, room_exit["direction"])
    {:noreply, World.add_room(room)}
  end

  def handle_info({:door_locked, %{direction: direction}}, room) do
    room = lock!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_lock, mirror_exit})
    end

    {:noreply, World.add_room(room)}
  end

  def handle_info({:mirror_lock, room_exit}, room) do
    room = lock!(room, room_exit["direction"])
    {:noreply, World.add_room(room)}
  end

  def handle_info(:execute_room_ability, %Room{room_ability: nil} = room) do
    ApathyDrive.PubSub.unsubscribe(self, "rooms:abilities")

    {:noreply, World.add_room(room)}
  end

  def handle_info(:execute_room_ability, %Room{room_ability: ability} = room) do
    ApathyDrive.PubSub.broadcast!("rooms:#{room.id}:spirits", {:execute_room_ability, ability})

    {:noreply, World.add_room(room)}
  end

  def handle_info({:timeout, _ref, {name, time, [module, function, args]}}, %Room{timers: timers} = room) do
    jitter = trunc(time / 2) + :random.uniform(time)

    new_ref = :erlang.start_timer(jitter, self, {name, time, [module, function, args]})

    timers = Map.put(timers, name, new_ref)

    apply module, function, args

    {:noreply, Map.put(room, :timers, timers) |> World.add_room}
  end

  def handle_info({:timeout, _ref, {name, [module, function, args]}}, %Room{timers: timers} = room) do
    apply module, function, args

    timers = Map.delete(timers, name)

    {:noreply, Map.put(room, :timers, timers) |> World.add_room}
  end

  def handle_info({:remove_effect, key}, room) do
    room = Systems.Effect.remove(room, key, fire_after_cast: true, show_expiration_message: true)
    {:noreply, World.add_room(room)}
  end

  def handle_info({:search, direction}, room) do
    room = Systems.Effect.add(room, %{searched: direction}, 300)
    {:noreply, World.add_room(room)}
  end

  def handle_info({:trigger, direction}, room) do
    room = Systems.Effect.add(room, %{triggered: direction}, 300)
    {:noreply, World.add_room(room)}
  end

  def handle_info({:clear_triggers, direction}, room) do
    room = room.effects
           |> Map.keys
           |> Enum.filter(fn(key) ->
                room.effects[key][:triggered] == direction
              end)
           |> Enum.reduce(room, &(Systems.Effect.remove(&2, &1, show_expiration_message: true)))

    {:noreply, World.add_room(room)}
  end

  def handle_info({:room_updated, %{changes: changes}}, room) do
    {:noreply, Map.merge(room, changes) |> World.add_room(room)}
  end

  def handle_info({:audibile_movement, room_id, exception_room_id}, %Room{id: id} = room) when id != exception_room_id do
    case Enum.find(room.exits, &(&1["destination"] == room_id)) do
      %{"direction" => direction} ->
        send_scroll(room, "<p><span class='dark-magenta'>You hear movement #{sound_direction(direction)}.</span></p>")
      _ ->
        :noop
    end
    {:noreply, World.add_room(room)}
  end

  def handle_info(_message, room) do
    {:noreply, room}
  end

end
