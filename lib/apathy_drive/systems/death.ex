defmodule Systems.Death do
  use Systems.Reload
  import Utility
  import Systems.Text
  use Timex

  def kill(victim) do
    if Process.alive?(victim) do
      room = Parent.of(victim)

      send_message(victim, "scroll", "<p><span class='red'>You have been killed!</span></p>")

      Systems.Monster.display_death_message(room, victim)

      room
      |> Systems.Monster.monsters_in_room(victim)
      |> Enum.each(fn(monster) ->
           reward_spirit(Possession.possessor(monster), victim)
           reward_monster(monster, victim)
         end)

      kill_monster(victim, room)
    end
  end

  def kill_monster(entity, room) do
    HPRegen.remove(entity)
    ManaRegen.remove(entity)
    Components.Brain.kill(entity)
    Components.Effects.remove(entity)
    Components.Combat.stop_timer(entity)

    possessor = Possession.possessor(entity)
    if possessor do
      Possession.unpossess(possessor)
      Systems.Prompt.update(entity, nil)
      send_message(possessor, "scroll", "<p>You are ejected from #{Components.Name.value(entity)}'s body.</p>")
      Systems.Prompt.update(possessor, nil)
    end

    Systems.Limbs.equipped_items(entity)
    |> Enum.each fn(item) ->
         Components.Limbs.unequip(entity, item)
         Components.Items.add_item(room, item)
       end

    Components.Items.get_items(entity)
    |> Enum.each fn(item) ->
         Components.Items.remove_item(entity, item)
         Components.Items.add_item(room, item)
       end

    Components.Monsters.remove_monster(room, entity)
    Entities.delete!(entity)
  end

  def experience_to_grant(entity) when is_pid entity do
    Systems.Stat.pre_effects_bonus(entity)
    |> Map.values
    |> Enum.sum
    |> experience_to_grant
  end

  def experience_to_grant(stat_total) do
    trunc(stat_total * (1 + (stat_total * 0.005)))
  end

  def reward_monster(monster, victim) do
    exp = experience_to_grant(victim)
    old_power = Systems.Trainer.total_power(monster)
    Components.Experience.add(monster, exp)
    new_power = Systems.Trainer.total_power(monster)
    power_gain = new_power - old_power
    if power_gain > 0 do
      send_message(monster, "scroll", "<p>You gain #{power_gain} development points.</p>")
    end
    Components.Alignment.alter_alignment(monster, Components.Alignment.get_alignment(victim))
  end

  def reward_spirit(nil, victim), do: nil
  def reward_spirit(spirit, victim) do
    exp = experience_to_grant(victim)
    Components.Experience.add(spirit, exp)
    send_message(spirit, "scroll", "<p>You gain #{exp} experience.</p>")
  end
end
