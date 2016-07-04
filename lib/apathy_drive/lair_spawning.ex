defmodule ApathyDrive.LairSpawning do
  alias ApathyDrive.{MonsterTemplate, Mobile, Repo, RoomServer}
  require Ecto.Query

  def spawn_lair(room, room_pid) do
    lair_monsters = ApathyDrive.LairMonster.monsters_template_ids(room.id)

    if room.lair_size > spawned_monster_count(room.id) do
      monster_templates = eligible_monsters(lair_monsters)
      if Enum.any?(monster_templates) do
        {mt_id, monster_template} = select_lair_monster(monster_templates)

        monster = MonsterTemplate.create_monster(monster_template, room)
                  |> Mobile.load

        RoomServer.audible_movement({:global, "room_#{room.id}"}, nil)

        Mobile.display_enter_message(monster, room_pid)

        spawn_lair(room, room_pid)
      end
    end

  end

  def select_lair_monster(monster_ids) do
    monster_ids
    |> Enum.random
  end

  def eligible_monsters(lair_monsters) do
    lair_monsters
    |> Enum.map(&({&1, MonsterTemplate.find(&1)}))
    |> Enum.reject(fn({_mt_id, mt}) ->
         mt = MonsterTemplate.value(mt)

         MonsterTemplate.limit_reached?(mt)
       end)
  end

  defp spawned_monster_count(room_id) do
    ApathyDrive.Mobile
    |> Ecto.Query.where(spawned_at: ^room_id)
    |> Ecto.Query.select([m], count(m.id))
    |> Repo.one
  end

end
