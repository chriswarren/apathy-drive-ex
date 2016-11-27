defmodule ApathyDrive.Companion do
  alias ApathyDrive.{Character, Companion, EntityAbility, Mobile, Monster,
                     Party, Repo, Room, RoomMonster, Spell, Text, TimerManager}
  require Ecto.Query

  defstruct [:gender, :description, :enter_message, :exit_message, :death_message,
             :hp, :mana, :timers, :effects, :last_effect_key, :spells,
             :strength, :agility, :intellect, :willpower, :health, :charm,
             :name, :room_id, :level, :monster_id, :character_id, :leader, :attack_target]

  def character(%Companion{character_id: id}, %Room{} = room) do
    room.mobiles
    |> Map.values
    |> Enum.find(& &1.__struct__ == Character and &1.id == id)
  end

  def toggle_combat(%Companion{} = companion, room) do
    time = min(Mobile.attack_interval(companion), TimerManager.time_remaining(companion, :auto_attack_timer))

    if Mobile.auto_attack_target(companion, room, nil) do
      companion
      |> TimerManager.send_after({:auto_attack_timer, time, {:execute_auto_attack, companion.ref}})
    else
      companion
    end
  end

  def hire_price(%Character{} = character) do
    character
    |> Mobile.power_at_level(character.level)
    |> div(10)
  end

  def load_for_character(%Room{} = room, %Character{id: id} = character) do
    rm =
      RoomMonster
      |> Ecto.Query.where(character_id: ^id)
      |> Repo.one
    if rm do
      companion =
        rm
        |> from_room_monster()
        |> Map.put(:leader, character.ref)
        |> Map.put(:character_id, id)

      mobiles =
        room.mobiles
        |> Enum.reject(fn {_ref, mobile} ->
             Map.get(mobile, :character_id) == id
           end)
        |> Enum.into(%{})
        |> Map.put(companion.ref, companion)

      put_in(room.mobiles, mobiles)
    else
      room
    end
  end

  def load_spells(%Companion{monster_id: id} = companion) do
    entities_spells =
      ApathyDrive.EntitySpell
      |> Ecto.Query.where(assoc_id: ^id, assoc_table: "monsters")
      |> Ecto.Query.preload([:spell])
      |> Repo.all

    spells =
      Enum.reduce(entities_spells, %{}, fn
        %{level: level, spell: %Spell{id: id} = spell}, spells ->
          spell =
            put_in(spell.abilities, EntityAbility.load_abilities("spells", id))
            |> Map.put(:level, level)
          Map.put(spells, spell.command, spell)
      end)
    Map.put(companion, :spells, spells)
  end

  def from_room_monster(%RoomMonster{id: id, monster_id: monster_id} = rm) do
    monster =
      Monster
      |> Repo.get(monster_id)
      |> Map.take([
           :gender, :description, :enter_message, :exit_message, :death_message,
           :hp, :mana, :timers, :effects, :last_effect_key, :spells
         ])

    room_monster =
      Map.take(rm, [:strength, :agility, :intellect, :willpower, :health, :charm,
                    :name, :room_id, :level])

    ref = make_ref()

    %Companion{}
    |> Map.merge(monster)
    |> Map.merge(room_monster)
    |> Map.put(:room_monster_id, id)
    |> Map.put(:monster_id, monster_id)
    |> Map.put(:ref, ref)
    |> Map.put(:level, rm.level)
    |> load_spells()
    |> TimerManager.send_after({:heartbeat, 1_000, {:heartbeat, ref}})
  end

  defimpl ApathyDrive.Mobile, for: Companion do

    def ability_value(companion, ability) do
      Systems.Effect.effect_bonus(companion, ability)
    end

    def accuracy_at_level(companion, level) do
      agi = attribute_at_level(companion, :agility, level)
      cha = attribute_at_level(companion, :charm, level)
      agi = agi + (cha / 10)
      modifier = ability_value(companion, "Accuracy")
      trunc(agi * (1 + (modifier / 100)))
    end

    def attribute_at_level(%Companion{} = companion, attribute, level) do
      base = Map.get(companion, attribute)

      trunc(base + ((base / 10) * (level - 1)))
    end

    def attack_interval(companion) do
      trunc(round_length_in_ms(companion) / attacks_per_round(companion))
    end

    def attack_spell(companion) do
      companion.spells
      |> Map.values
      |> Enum.filter(&(&1.kind == "auto attack"))
      |> Enum.random
      |> Map.put(:kind, "attack")
      |> Map.put(:ignores_round_cooldown?, true)
    end

    def attacks_per_round(companion) do
      1
    end

    def auto_attack_target(%Companion{} = companion, room, attack_spell) do
      character_target =
        companion
        |> Companion.character(room)
        |> Mobile.auto_attack_target(room, attack_spell)

      character_target || companion.attack_target
    end

    def caster_level(%Companion{level: caster_level}, %{} = _target), do: caster_level

    def colored_name(%Companion{name: name} = companion, %Character{} = observer) do
      level = target_level(companion, observer)
      companion_power = Mobile.power_at_level(companion, level)
      observer_power = Mobile.power_at_level(observer, level)

      color =
        cond do
          companion_power < (observer_power * 0.75) ->
            "teal"
          companion_power < (observer_power * 1.5) ->
            "chartreuse"
          companion_power < (observer_power * 3.0) ->
            "blue"
          companion_power < (observer_power * 6.0) ->
            "darkmagenta"
          :else ->
            "red"
        end
      "<span style='color: #{color};'>#{name}</span>"
    end

    def confused(%Companion{effects: effects} = companion, %Room{} = room) do
      effects
      |> Map.values
      |> Enum.find(fn(effect) ->
           Map.has_key?(effect, "confused") && (effect["confused"] >= :rand.uniform(100))
         end)
      |> confused(companion, room)
    end
    def confused(nil, %Companion{}, %Room{}), do: false
    def confused(%{"confusion_message" => %{"user" => user_message} = message}, %Companion{} = companion, %Room{} = room) do
      if message["spectator"], do: Room.send_scroll(room, "#{Text.interpolate(message["spectator"], %{"user" => companion})}", [companion])
      true
    end
    def confused(%{}, %Companion{} = companion, %Room{} = room) do
      Room.send_scroll(room, "<p><span class='cyan'>#{Text.interpolate("{{user}} fumbles in confusion!</span></p>", %{"user" => companion})}</span></p>", [companion])
      true
    end

    def crits_at_level(companion, level) do
      int = attribute_at_level(companion, :intellect, level)
      cha = attribute_at_level(companion, :charm, level)
      int = int + (cha / 10)
      modifier = ability_value(companion, "Crits")
      trunc(int * (1 + (modifier / 100)))
    end

    def description(companion, _observer) do
      companion.description
    end

    def die(companion, room) do
      message =
        companion.death_message
        |> Text.interpolate(%{"name" => companion.name})
        |> Text.capitalize_first

      Room.send_scroll(room, "<p>#{message}</p>")

      ApathyDrive.Repo.delete!(%RoomMonster{id: companion.room_monster_id})

      put_in(room.mobiles, Map.delete(room.mobiles, companion.ref))
    end

    def dodge_at_level(companion, level) do
      agi = attribute_at_level(companion, :agility, level)
      cha = attribute_at_level(companion, :charm, level)
      agi = agi + (cha / 10)
      modifier = ability_value(companion, "Dodge")
      trunc(agi * (1 + (modifier / 100)))
    end

    def enough_mana_for_spell?(companion, %Spell{} =  spell) do
      mana = Mobile.max_mana_at_level(companion, companion.level)
      cost = Spell.mana_cost_at_level(spell, companion.level)

      companion.mana >= (cost / mana)
    end

    def enter_message(%Companion{enter_message: enter_message}) do
      enter_message
    end

    def exit_message(%Companion{exit_message: exit_message}) do
      exit_message
    end

    def has_ability?(%Companion{} = companion, ability_name) do
      # TODO: check abilities from race, class, and spell effects
      false
    end

    def heartbeat(%Companion{} = companion, %Room{} = room) do
      Room.update_mobile(room, companion.ref, fn companion ->
        companion
        |> regenerate_hp_and_mana(room)
        |> Companion.toggle_combat(room)
        |> TimerManager.send_after({:heartbeat, round_length_in_ms(companion), {:heartbeat, companion.ref}})
      end)
    end

    def held(%{effects: effects} = mobile) do
      effects
      |> Map.values
      |> Enum.find(fn(effect) ->
           Map.has_key?(effect, "held")
         end)
      |> held(mobile)
    end
    def held(nil, %{}), do: false
    def held(%{"effect_message" => message}, %{} = mobile) do
      send_scroll(mobile, "<p>#{message}</p>")
      true
    end

    def hp_description(%Companion{hp: hp}) when hp >= 1.0, do: "unwounded"
    def hp_description(%Companion{hp: hp}) when hp >= 0.9, do: "slightly wounded"
    def hp_description(%Companion{hp: hp}) when hp >= 0.6, do: "moderately wounded"
    def hp_description(%Companion{hp: hp}) when hp >= 0.4, do: "heavily wounded"
    def hp_description(%Companion{hp: hp}) when hp >= 0.2, do: "severely wounded"
    def hp_description(%Companion{hp: hp}) when hp >= 0.1, do: "critically wounded"
    def hp_description(%Companion{hp: hp}), do: "very critically wounded"

    def magical_damage_at_level(companion, level) do
      damage = attribute_at_level(companion, :intellect, level)
      modifier = ability_value(companion, "ModifyDamage") + ability_value(companion, "ModifyMagicalDamage")
      trunc(damage * (1 + (modifier / 100)))
    end

    def magical_resistance_at_level(companion, level) do
      resist = attribute_at_level(companion, :willpower, level)
      modifier = ability_value(companion, "MagicalResist")
      trunc(resist * (modifier / 100))
    end

    def max_hp_at_level(%Companion{} = companion, level) do
      base = 8
      base = trunc((base + ability_value(companion, "HPPerHealth")) * attribute_at_level(companion, :health, level))
      modifier = ability_value(companion, "MaxHP")
      trunc(base * (1 + (modifier / 100)))
    end

    def max_mana_at_level(mobile, level) do
      base = trunc(4 * attribute_at_level(mobile, :intellect, level))
      modifier = ability_value(mobile, "MaxMana")
      trunc(base * (1 + (modifier / 100)))
    end

    def party_refs(companion, room) do
      Party.refs(room, companion)
    end

    def perception_at_level(companion, level) do
      int = attribute_at_level(companion, :intellect, level)
      cha = attribute_at_level(companion, :charm, level)
      int = int + (cha / 10)
      modifier = ability_value(companion, "Perception")
      trunc(int * (1 + (modifier / 100)))
    end

    def physical_damage_at_level(companion, level) do
      damage = attribute_at_level(companion, :strength, level)
      modifier = ability_value(companion, "ModifyDamage") + ability_value(companion, "ModifyPhysicalDamage")
      trunc(damage * (1 + (modifier / 100)))
    end

    def physical_resistance_at_level(companion, level) do
      resist = attribute_at_level(companion, :strength, level)
      modifier = ability_value(companion, "AC")
      trunc(resist * (modifier / 100))
    end

    def power_at_level(%Companion{} = companion, level) do
      [:strength, :agility, :intellect, :willpower, :health, :charm]
      |> Enum.reduce(0, & &2 + Mobile.attribute_at_level(companion, &1, level))
    end

    def regenerate_hp_and_mana(%Companion{hp: hp, mana: mana} = companion, room) do
      max_hp = max_hp_at_level(companion, companion.level)
      max_mana = max_mana_at_level(companion, companion.level)

      base_regen_per_round = attribute_at_level(companion, :willpower, companion.level) / 5

      hp_regen_percentage_per_round = base_regen_per_round * (1 + ability_value(companion, "HPRegen")) / max_hp
      mana_regen_percentage_per_round = base_regen_per_round * (1 + ability_value(companion, "ManaRegen")) / max_mana

      companion
      |> shift_hp(hp_regen_percentage_per_round, room)
      |> Map.put(:mana, min(mana + mana_regen_percentage_per_round, 1.0))
    end

    def round_length_in_ms(companion) do
      agility = attribute_at_level(companion, :agility, companion.level)

      base =
        if agility > 1000 do
          4000 * :math.pow(0.9997, 1000) * :math.pow(0.999925, agility - 1000)
        else
          4000 * :math.pow(0.9997, agility)
        end

      speed_mods =
        companion.effects
        |> Map.values
        |> Enum.filter(&(Map.has_key?(&1, "Speed")))
        |> Enum.map(&(Map.get(&1, "Speed")))

      count = length(speed_mods)

      if count > 0 do
        trunc(base * (Enum.sum(speed_mods) / count / 100))
      else
        base
      end
    end

    def send_scroll(%Companion{} = companion, _html) do
      companion
    end

    def set_room_id(%Companion{} = companion, room_id) do
      %RoomMonster{id: companion.room_monster_id}
      |> Ecto.Changeset.change(%{room_id: room_id})
      |> Repo.update!

      companion
      |> Map.put(:room_id, room_id)
    end

    def shift_hp(companion, percentage, room) do
      hp_description = hp_description(companion)
      companion = update_in(companion.hp, &(min(1.0, &1 + percentage)))
      updated_hp_description = hp_description(companion)

      if companion.hp > 0 and hp_description != updated_hp_description do
        room.mobiles
        |> Map.values
        |> List.delete(companion)
        |> Enum.each(fn
             %Character{} = observer ->
               Mobile.send_scroll(observer, "<p>#{Mobile.colored_name(companion, observer)} is #{updated_hp_description}.</p>")
             _ ->
               :noop
           end)
      end

      companion
    end

    def silenced(%Companion{effects: effects} = companion, %Room{} = room) do
      effects
      |> Map.values
      |> Enum.find(fn(effect) ->
           Map.has_key?(effect, "Silence")
         end)
      |> silenced(companion, room)
    end
    def silenced(nil, %Companion{}, %Room{}), do: false
    def silenced(%{}, %Companion{} = companion, %Room{} = room) do
      Mobile.send_scroll(companion, "<p><span class='cyan'>You are silenced!</span></p>")
      true
    end

    def spellcasting_at_level(companion, level) do
      will = attribute_at_level(companion, :willpower, level)
      cha = attribute_at_level(companion, :charm, level)
      will = will + (cha / 10)
      modifier = ability_value(companion, "Spellcasting")
      trunc(will * (1 + (modifier / 100)))
    end

    def spells_at_level(%Companion{spells: spells}, level) do
      spells
      |> Map.values
      |> Enum.filter(& &1.level <= level)
      |> Enum.sort_by(& &1.level)
    end

    def stealth_at_level(companion, level) do
      agi = attribute_at_level(companion, :agility, level)
      cha = attribute_at_level(companion, :charm, level)
      agi = agi + (cha / 10)
      modifier = ability_value(companion, "Stealth")
      trunc(agi * (modifier / 100))
    end

    def subtract_mana(companion, spell) do
      cost = Spell.mana_cost_at_level(spell, companion.level)
      percentage = cost / Mobile.max_mana_at_level(companion, companion.level)
      update_in(companion.mana, &(max(0, &1 - percentage)))
    end

    def target_level(%Companion{level: _caster_level}, %Character{level: target_level}), do: target_level
    def target_level(%Companion{level: _caster_level}, %Companion{level: target_level}), do: target_level
    def target_level(%Companion{level: caster_level}, %{level: _target_level}), do: caster_level

    def tracking_at_level(companion, level) do
      perception = perception_at_level(companion, level)
      modifier = ability_value(companion, "Tracking")
      trunc(perception * (modifier / 100))
    end

    def update_prompt(%Companion{} = companion) do
      companion
    end

  end

end