defmodule Room do
  require Logger
  use Ecto.Model
  use GenServer
  use Timex
  alias ApathyDrive.Repo
  alias ApathyDrive.PubSub

  schema "rooms" do
    field :name,                  :string
    field :keywords,              {:array, :string}
    field :description,           :string
    field :effects,               :any, virtual: true, default: %{}
    field :light,                 :integer
    field :item_descriptions,     ApathyDrive.JSONB
    field :lair_size,             :integer
    field :lair_monsters,         {:array, :integer}
    field :lair_frequency,        :integer
    field :lair_next_spawn_at,    :any, virtual: true, default: 0
    field :permanent_npc,         :integer
    field :start_room,            :boolean, default: false
    field :exits,                 ApathyDrive.JSONB
    field :legacy_id,             :string
    field :timers,                :any, virtual: true, default: %{}
    field :room_ability,          :any, virtual: true

    timestamps

    has_many   :monsters, Monster
    belongs_to :ability,  Ability
  end

  def init(%Room{} = room) do
    PubSub.subscribe(self, "rooms")
    PubSub.subscribe(self, "rooms:#{room.id}")
    send(self, :load_monsters)

    room = if room.lair_monsters do
      PubSub.subscribe(self, "rooms:lairs")
      send(self, {:spawn_monsters, Date.now |> Date.convert(:secs)})
      TimerManager.call_every(room, {:spawn_monsters, 60_000, fn -> send(self, {:spawn_monsters, Date.now |> Date.convert(:secs)}) end})
    else
      room
    end

    room = if room.permanent_npc do
      PubSub.subscribe(self, "rooms:permanent_npcs")
      send(self, :spawn_permanent_npc)
      TimerManager.call_every(room, {:spawn_permanent_npc, 60_000, fn -> send(self, :spawn_permanent_npc) end})
    else
      room
    end

    room = if room.ability_id do
      PubSub.subscribe(self, "rooms:abilities")

      room
      |> Map.put(:room_ability, ApathyDrive.Repo.get(Ability, room.ability_id))
      |> TimerManager.call_every({:execute_room_ability, 5_000, fn -> send(self, :execute_room_ability) end})
    else
      room
    end

    {:ok, room}
  end

  def start_room_id do
    query = from r in Room,
            where: r.start_room == true,
            select: r.id

    Repo.one(query)
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
    case Repo.get(Room, id) do
      %Room{} = room ->

        {:ok, pid} = Supervisor.start_child(ApathyDrive.Supervisor, {:"room_#{id}", {GenServer, :start_link, [Room, room, [name: {:global, :"room_#{id}"}]]}, :permanent, 5000, :worker, [Room]})

        pid
      nil ->
        nil
    end
  end

  def all do
    PubSub.subscribers("rooms")
  end

  def value(room) do
    GenServer.call(room, :value)
  end

  def exit_direction("up"),      do: "upwards"
  def exit_direction("down"),    do: "downwards"
  def exit_direction(direction), do: "to the #{direction}"

  def enter_direction(nil),       do: "nowhere"
  def enter_direction("up"),      do: "above"
  def enter_direction("down"),    do: "below"
  def enter_direction(direction), do: "the #{direction}"

  def spawned_monsters(room_id) when is_integer(room_id), do: PubSub.subscribers("rooms:#{room_id}:spawned_monsters")
  def spawned_monsters(room),   do: PubSub.subscribers("rooms:#{id(room)}:spawned_monsters")

  # Value functions
  def monsters(%Monster{room_id: room_id, pid: pid}) do
    PubSub.subscribers("rooms:#{room_id}:monsters")
    |> Enum.reject(&(&1 == pid))
  end

  def monsters(%Room{} = room, monster \\ nil) do
    PubSub.subscribers("rooms:#{room.id}:monsters")
    |> Enum.reject(&(&1 == monster))
  end

  def exit_directions(%Room{} = room) do
    room.exits
    |> Enum.map(fn(room_exit) ->
         :"Elixir.ApathyDrive.Exits.#{room_exit["kind"]}".display_direction(room, room_exit)
       end)
    |> Enum.reject(&(&1 == nil))
  end

  def random_direction(%Room{} = room) do
    :random.seed(:os.timestamp)

    case room.exits do
      nil ->
        nil
      exits ->
        exits
        |> Enum.map(&(&1["direction"]))
        |> Enum.shuffle
        |> List.first
    end
  end

  def look(%Room{light: light} = room, %Spirit{} = spirit) do
    html = ~s(<div class='room'><div class='title'>#{room.name}</div><div class='description'>#{room.description}</div>#{look_items(room)}#{look_monsters(room, nil)}#{look_directions(room)}#{light_desc(light)}</div>)

    Spirit.send_scroll spirit, html
  end

  def look(%Room{light: light} = room, %Monster{} = monster) do
    html = if Monster.blind?(monster) do
      "<p>You are blind.</p>"
    else
      ~s(<div class='room'><div class='title'>#{room.name}</div><div class='description'>#{room.description}</div>#{look_items(room)}#{look_monsters(room, monster)}#{look_directions(room)}#{light_desc(light)}</div>)
    end

    Monster.send_scroll(monster, html)
  end

  def light_desc(light_level)  when light_level <= -100, do: "<p>The room is barely visible</p>"
  def light_desc(light_level)  when light_level <=  -25, do: "<p>The room is dimly lit</p>"
  def light_desc(_light_level), do: nil

  def permanent_npc_present?(%Room{} = room) do
    PubSub.subscribers("rooms:#{room.id}:monsters")
    |> Enum.map(&(Monster.value(&1).monster_template_id))
    |> Enum.member?(room.permanent_npc)
  end

  def look_items(%Room{} = room) do
    items = room.item_descriptions["visible"]
            |> Map.keys

    case Enum.count(items) do
      0 ->
        ""
      _ ->
        "<div class='items'>You notice #{Enum.join(items, ", ")} here.</div>"
    end
  end

  def look_monsters(%Room{}, %Monster{} = monster) do
    monsters = monsters(monster)
               |> Enum.map(&Monster.value/1)
               |> Enum.map(&Monster.look_name/1)
               |> Enum.join("<span class='magenta'>, </span>")

    case(monsters) do
      "" ->
        ""
      monsters ->
        "<div class='monsters'><span class='dark-magenta'>Also here:</span> #{monsters}<span class='dark-magenta'>.</span></div>"
    end
  end

  def look_monsters(%Room{} = room, nil) do
    monsters = monsters(room, nil)
               |> Enum.map(&Monster.value/1)
               |> Enum.map(&Monster.look_name/1)
               |> Enum.join("<span class='magenta'>, </span>")

    case(monsters) do
      "" ->
        ""
      monsters ->
        "<div class='monsters'><span class='dark-magenta'>Also here:</span> #{monsters}<span class='dark-magenta'>.</span></div>"
    end
  end

  def look_directions(%Room{} = room) do
    case exit_directions(room) do
      [] ->
        "<div class='exits'>Obvious exits: NONE</div>"
      directions ->
        "<div class='exits'>Obvious exits: #{Enum.join(directions, ", ")}</div>"
    end
  end

  def send_scroll(%Room{id: id}, html) do
    ApathyDrive.Endpoint.broadcast! "rooms:#{id}", "scroll", %{:html => html}
  end

  defp open!(%Room{} = room, direction) do
    if open_duration = ApathyDrive.Exit.open_duration(room, direction) do
      Systems.Effect.add(room, %{open: direction}, open_duration)
      # todo: tell players in the room when it re-locks
      #"The #{name} #{ApathyDrive.Exit.direction_description(exit["direction"])} just locked!"
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

  defp close!(%Room{effects: effects} = room, direction) do
    room = effects
           |> Map.keys
           |> Enum.filter(fn(key) ->
                effects[key][:open] == direction
              end)
           |> Enum.reduce(room, fn(room, key) ->
                Systems.Effect.remove(room, key)
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

  defp unlock!(%Room{} = room, direction) do
    unlock_duration = if open_duration = ApathyDrive.Exit.open_duration(room, direction) do
      open_duration
    else
      10#300
    end

    Systems.Effect.add(room, %{unlocked: direction}, unlock_duration)
    # todo: tell players in the room when it re-locks
    #"The #{name} #{ApathyDrive.Exit.direction_description(exit["direction"])} just locked!"
  end

  defp lock!(%Room{effects: effects} = room, direction) do
    effects
    |> Map.keys
    |> Enum.filter(fn(key) ->
         effects[key][:unlocked] == direction
       end)
    |> Enum.reduce(room, fn(key, room) ->
         Systems.Effect.remove(room, key)
       end)
  end

  # Generate functions from Ecto schema
  fields = Keyword.keys(@struct_fields) -- Keyword.keys(@ecto_assocs)

  Enum.each(fields, fn(field) ->
    def unquote(field)(pid) do
      GenServer.call(pid, unquote(field))
    end

    def unquote(field)(pid, new_value) do
      GenServer.call(pid, {unquote(field), new_value})
    end
  end)

  Enum.each(fields, fn(field) ->
    def handle_call(unquote(field), _from, state) do
      {:reply, Map.get(state, unquote(field)), state}
    end

    def handle_call({unquote(field), new_value}, _from, state) do
      {:reply, new_value, Map.put(state, unquote(field), new_value)}
    end
  end)

  def handle_call(:value, _from, room) do
    {:reply, room, room}
  end

  # GenServer callbacks
  def handle_info({:spawn_monsters, time},
                 %{:lair_next_spawn_at => lair_next_spawn_at} = room)
                 when time >= lair_next_spawn_at do

    ApathyDrive.LairSpawning.spawn_lair(room)

    room = room
           |> Map.put(:lair_next_spawn_at, Date.now
                                           |> Date.shift(mins: room.lair_frequency)
                                           |> Date.convert(:secs))

    {:noreply, room}
  end

  def handle_info(:spawn_permanent_npc, room) do
    mt = MonsterTemplate.find(room.permanent_npc)

    unless MonsterTemplate.limit_reached?(MonsterTemplate.value(mt)) || permanent_npc_present?(room) do
      monster = MonsterTemplate.spawn_monster(mt, room)

      Monster.display_enter_message(room, monster)
    end

    {:noreply, room}
  end

  def handle_info(:load_monsters, room) do
    query = from m in assoc(room, :monsters), select: m.id

    query
    |> ApathyDrive.Repo.all
    |> Enum.each(fn(monster_id) ->
         Monster.find(monster_id)
       end)

    {:noreply, room}
  end

  def handle_info({:door_bashed_open, %{direction: direction}}, room) do
    room = open!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_bash, mirror_exit})
    end

    {:noreply, room}
  end

  def handle_info({:mirror_bash, room_exit}, room) do
    room = open!(room, room_exit["direction"])
    {:noreply, room}
  end

  def handle_info({:door_bash_failed, %{direction: direction}}, room) do
    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_bash_failed, mirror_exit})
    end

    {:noreply, room}
  end

  def handle_info({:door_opened, %{direction: direction}}, room) do
    room = open!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_open, mirror_exit})
    end

    {:noreply, room}
  end

  def handle_info({:mirror_open, room_exit}, room) do
    room = open!(room, room_exit["direction"])
    {:noreply, room}
  end

  def handle_info({:door_closed, %{direction: direction}}, room) do
    room = close!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_close, mirror_exit})
    end

    {:noreply, room}
  end

  def handle_info({:mirror_close, room_exit}, room) do
    room = close!(room, room_exit["direction"])
    {:noreply, room}
  end

  def handle_info({:door_locked, %{direction: direction}}, room) do
    room = lock!(room, direction)

    room_exit = ApathyDrive.Exit.get_exit_by_direction(room, direction)

    {mirror_room, mirror_exit} = ApathyDrive.Exit.mirror(room, room_exit)

    if mirror_exit["kind"] == room_exit["kind"] do
      ApathyDrive.PubSub.broadcast!("rooms:#{mirror_room.id}", {:mirror_lock, mirror_exit})
    end

    {:noreply, room}
  end

  def handle_info({:mirror_lock, room_exit}, room) do
    room = lock!(room, room_exit["direction"])
    {:noreply, room}
  end

  def handle_info(:execute_room_ability, %Room{room_ability: nil} = room) do
    ApathyDrive.PubSub.unsubscribe(self, "rooms:abilities")

    {:noreply, room}
  end

  def handle_info(:execute_room_ability, %Room{room_ability: ability} = room) do
    ApathyDrive.PubSub.broadcast!("rooms:#{room.id}:monsters", {:execute_room_ability, ability})

    {:noreply, room}
  end

  def handle_info({:timeout, _ref, {name, time, function}}, %Room{timers: timers} = room) do
    jitter = trunc(time / 2) + :random.uniform(time)

    new_ref = :erlang.start_timer(jitter, self, {name, time, function})

    timers = Map.put(timers, name, new_ref)

    TimerManager.execute_function(function)

    {:noreply, Map.put(room, :timers, timers)}
  end

  def handle_info({:timeout, _ref, {name, function}}, %Room{timers: timers} = room) do
    TimerManager.execute_function(function)

    timers = Map.delete(timers, name)

    {:noreply, Map.put(room, :timers, timers)}
  end

  def handle_info({:remove_effect, key}, room) do
    room = Systems.Effect.remove(room, key)
    {:noreply, room}
  end

  def handle_info({:search, direction}, room) do
    room = Systems.Effect.add(room, %{searched: direction}, 300)
    {:noreply, room}
  end

  def handle_info({:trigger, direction}, room) do
    room = Systems.Effect.add(room, %{triggered: direction}, 300)
    {:noreply, room}
  end

  def handle_info({:clear_triggers, direction}, room) do
    room = room.effects
           |> Map.keys
           |> Enum.filter(fn(key) ->
                room.effects[key][:triggered] == direction
              end)
           |> Enum.reduce(room, &(Systems.Effect.remove(&2, &1)))

    {:noreply, room}
  end

  def handle_info(_message, room) do
    {:noreply, room}
  end

end
