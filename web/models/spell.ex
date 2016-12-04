defmodule ApathyDrive.Spell do
  use ApathyDrive.Web, :model
  alias ApathyDrive.{EntityAbility, Match, Mobile, Room, Spell, Stealth, Text, TimerManager}

  schema "spells" do
    field :name, :string
    field :targets, :string
    field :kind, :string
    field :mana, :integer
    field :command, :string
    field :description, :string
    field :user_message, :string
    field :target_message, :string
    field :spectator_message, :string
    field :duration_in_ms, :integer, default: 0
    field :cooldown_in_ms, :integer

    field :level, :integer, virtual: true
    field :abilities, :map, virtual: true, default: %{}
    field :ignores_round_cooldown?, :boolean, virtual: true, default: false
    field :result, :any, virtual: true

    has_many :characters, ApathyDrive.Character

    timestamps
  end

  @required_fields ~w(name targets kind mana command description user_message target_message spectator_message duration_in_ms)
  @optional_fields ~w()

  @valid_targets ["monster or single", "self", "self or single", "monster", "full party area", "full attack area", "single", "full area"]
  @target_required_targets ["monster or single", "monster", "single"]

  @instant_abilities [
    "CurePoison", "DispelMagic", "Drain", "Enslave", "Freedom", "Heal", "HealMana", "KillSpell",
    "MagicalDamage", "PhysicalDamage", "Poison", "RemoveSpells", "Script", "Summon", "Teleport"
  ]

  @duration_abilities [
    "AC", "Accuracy", "Agility", "Charm", "Blind", "Charm", "Confusion", "ConfusionMessage", "ConfusionSpectatorMessage",
    "Crits", "Dodge", "Encumbrance", "EndCast", "EndCast%", "EnhanceSpell", "EnhanceSpellDamage", "Fear", "HPRegen",
    "Intellect", "MagicalResist", "ManaRegen", "MaxHP", "MaxMana", "ModifyDamage", "Perception", "Picklocks",
    "PoisonImmunity", "RemoveMessage", "ResistCold", "ResistFire", "ResistLightning", "ResistStone", "Root", "SeeHidden",
    "Shadowform", "Silence", "Speed", "Spellcasting", "StatusMessage", "Stealth", "Strength", "Tracking", "Willpower"
  ]

  @resist_message %{
    user: "You attempt to cast {{spell}} on {{target}}, but they resist!",
    target: "{{user}} attempts to cast {{spell}} on you, but you resist!",
    spectator: "{{user}} attempts to cast {{spell}} on {{target}}, but they resist!"
  }

  @deflect_message %{
    user: "{{target}}'s armour deflects your feeble attack!",
    target: "Your armour deflects {{user}}'s feeble attack!",
    spectator: "{{target}}'s armour deflects {{user}}'s feeble attack!"
  }

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ %{}) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  def find(id) do
    spell = ApathyDrive.Repo.get(__MODULE__, id)

    if spell do
      put_in(spell.abilities, EntityAbility.load_abilities("spells", id))
    end
  end

  def heal_spells(%{spells: spells} = mobile) do
    spells
    |> Map.values
    |> Enum.filter(&(&1.kind == "heal"))
  end

  # equivilent to a character with 2 ManaPerIntellect and 100 intellect
  def base_mana_at_level(level), do: 200 + ((level - 1) * 20)

  def mana_cost_at_level(%Spell{mana: mana} = spell, level) do
    trunc(base_mana_at_level(level) * (mana / 100))
  end

  def execute(%Room{} = room, caster_ref, %Spell{targets: targets}, "") when targets in @target_required_targets do
    room
    |> Room.get_mobile(caster_ref)
    |> Mobile.send_scroll("<p><span class='red'>You must specify a target for that spell.</span></p>")

    room
  end

  def execute(%Room{} = room, caster_ref, %Spell{} = spell, "") do
    execute(room, caster_ref, spell, List.wrap(caster_ref))
  end

  def execute(%Room{} = room, caster_ref, %Spell{} = spell, query) when is_binary(query) do
    case get_targets(room, caster_ref, spell, query) do
      [] ->
        room
        |> Room.get_mobile(caster_ref)
        |> Mobile.send_scroll("<p>Unable to cast #{spell.name} at \"#{query}\".</p>")
        room
      targets ->
        execute(room, caster_ref, spell, targets)
    end
  end

  def execute(%Room{} = room, caster_ref, %Spell{} = spell, targets) when is_list(targets) do
    if can_execute?(room, caster_ref, spell) do
      Room.update_mobile(room, caster_ref, fn caster ->
        display_pre_cast_message(room, caster, targets, spell)

        caster =
          caster
          |> apply_cooldowns(spell)
          |> Mobile.subtract_mana(spell)

        Mobile.update_prompt(caster)

        caster =
          if spell.kind in ["attack", "curse"] and !(caster.ref in targets) do
            [target_ref | _] = targets

            if Map.has_key?(caster, :attack_target) do
              if is_nil(caster.attack_target) do
                time = min(Mobile.attack_interval(caster), TimerManager.time_remaining(caster, :auto_attack_timer))

                caster
                |> Map.put(:attack_target, target_ref)
                |> TimerManager.send_after({:auto_attack_timer, time, {:execute_auto_attack, caster.ref}})
                |> Mobile.send_scroll("<p><span class='dark-yellow'>*Combat Engaged*</span></p>")
              else
                caster
                |> Map.put(:attack_target, target_ref)
              end
            else
              caster
            end
          else
            caster
          end

        caster = Stealth.reveal(caster)

        room = put_in(room.mobiles[caster_ref], caster)

        Enum.reduce(targets, room, fn(target_ref, updated_room) ->
          Room.update_mobile(updated_room, target_ref, fn target ->
            if affects_target?(target, spell) do
              target = 
                updated_room
                |> apply_spell(caster, target, spell)
                |> Stealth.reveal
              if target.hp < 0 do
                Mobile.die(target, updated_room)
              else
                target
              end
            else
              message = "#{target.name} is not affected by that ability." |> Text.capitalize_first
              Mobile.send_scroll(caster, "<p><span class='dark-cyan'>#{message}</span></p>")
              target
            end
          end)
        end)
        #|> execute_multi_cast(caster_ref, ability, targets)
      end)
    else
      room
    end
  end

  def duration(%Spell{duration_in_ms: duration, kind: kind}, %{} = caster, %{} = target) do
    caster_level = Mobile.caster_level(caster, target)
    target_level = Mobile.target_level(caster, target)

    caster_sc = Mobile.spellcasting_at_level(caster, caster_level)

    if kind == "curse" do
      target_mr = Mobile.magical_resistance_at_level(target, target_level)
      trunc(duration * :math.pow(1.005, caster_sc) * :math.pow(0.985, target_mr))
    else
      trunc(duration * :math.pow(1.005, caster_sc))
    end
  end

  def dodged?(%{} = caster, %{} = target) do
    caster_level = Mobile.caster_level(caster, target)
    accuracy = Mobile.accuracy_at_level(caster, caster_level)

    target_level = Mobile.target_level(caster, target)
    dodge = Mobile.dodge_at_level(target, target_level)

    chance = 30 + dodge - accuracy

    :rand.uniform(100) < chance
  end

  def apply_spell(%Room{} = room, %{} = caster, %{} = target, %Spell{abilities: %{"Dodgeable" => true}} = spell) do
    if dodged?(caster, target) do
      display_cast_message(room, caster, target, Map.put(spell, :result, :dodged))

      effects =
        %{"Dodge" => -10}
        |> Map.put("stack_key", "dodge-limiter")
        |> Map.put("stack_count", 5)

      target
      |> Systems.Effect.add(effects, Mobile.round_length_in_ms(target))
      |> aggro_target(spell, caster)
    else
      apply_spell(room, caster, target, update_in(spell.abilities, &Map.delete(&1, "Dodgeable")))
    end
  end
  def apply_spell(%Room{} = room, %{} = caster, %{} = target, %Spell{} = spell) do
    target =
      target
      |> apply_instant_abilities(spell, caster)
      |> aggro_target(spell, caster)

    room = put_in(room.mobiles[target.ref], target)

    duration = duration(spell, caster, target)

    if spell.kind == "curse" and duration < 1000 do
      display_cast_message(room, caster, target, Map.put(spell, :result, :resisted))

      target
      |> Map.put(:spell_shift, nil)
      |> Mobile.update_prompt
    else
      display_cast_message(room, caster, target, spell)

      target =
        if target.spell_shift do
          Mobile.shift_hp(target, target.spell_shift, room)
        else
          target
        end

      target
      |> Map.put(:spell_shift, nil)
      |> apply_duration_abilities(spell, caster, duration)
      |> Mobile.update_prompt
    end
  end

  def aggro_target(%{ref: target_ref} = target, %Spell{kind: kind}, %{ref: caster_ref} = caster) when kind in ["attack", "curse"] and target_ref != caster_ref do
    ApathyDrive.Aggression.attack(target, caster)
  end
  def aggro_target(%{} = target, %Spell{}, %{} = _caster), do: target

  def apply_instant_abilities(%{} = target, %Spell{} = spell, %{} = caster) do
    spell.abilities
    |> Map.take(@instant_abilities)
    |> Enum.reduce(target, fn ability, updated_target ->
         apply_instant_ability(ability, updated_target, spell, caster)
       end)
  end

  def apply_instant_ability({"RemoveSpells", spell_ids}, %{} = target, _spell, caster) do
    Enum.reduce(spell_ids, target, fn(spell_id, updated_target) ->
      Systems.Effect.remove_oldest_stack(updated_target, spell_id)
    end)
  end
  def apply_instant_ability({"Heal", value}, %{} = target, _spell, caster) do
    level = min(target.level, caster.level)
    healing = Mobile.magical_damage_at_level(caster, level) * (value / 100)
    percentage_healed = calculate_damage(healing, 0, value) / Mobile.max_hp_at_level(target, level)

    Map.put(target, :spell_shift, percentage_healed)
  end
  def apply_instant_ability({"MagicalDamage", value}, %{} = target, _spell, caster) do
    caster_level = Mobile.caster_level(caster, target)
    target_level = Mobile.target_level(caster, target)

    damage = Mobile.magical_damage_at_level(caster, caster_level)
    resist = Mobile.magical_resistance_at_level(target, target_level)
    damage_percent = calculate_damage(damage, resist, value) / Mobile.max_hp_at_level(target, target_level)

    Map.put(target, :spell_shift, -damage_percent)
  end
  def apply_instant_ability({"PhysicalDamage", value}, %{} = target, _spell, caster) do
    caster_level = Mobile.caster_level(caster, target)
    target_level = Mobile.target_level(caster, target)

    damage = Mobile.physical_damage_at_level(caster, caster_level)
    resist = Mobile.physical_resistance_at_level(target, target_level)

    damage =
      damage
      |> calculate_damage(resist, value)
      |> apply_crit(caster, caster_level, target, target_level)

    damage_percent =  damage / Mobile.max_hp_at_level(target, target_level)

    Map.put(target, :spell_shift, -damage_percent)
  end
  def apply_instant_ability({ability_name, _value}, %{} = target, _spell, caster) do
    Mobile.send_scroll(caster, "<p><span class='red'>Not Implemented: #{ability_name}")
    target
  end

  def apply_crit(damage, caster, caster_level, target, target_level) do
    if crit?(caster, caster_level, target, target_level) do
      damage * 2
    else
      damage
    end
  end

  def crit?(caster, caster_level, target, target_level) do
    caster_crit = Mobile.crits_at_level(caster, caster_level)
    target_crit = Mobile.crits_at_level(target, target_level)

    :rand.uniform(100) < crit_chance(caster_crit, target_crit)
  end

  def crit_chance(caster_crit, target_crit) do
    10 + caster_crit - target_crit
  end

  def calculate_damage(damage, resist, modifier) do
    (damage - resist) * (modifier / 100) * (Enum.random(85..115) / 100)
  end

  def apply_duration_abilities(%{} = target, %Spell{} = spell, %{} = caster, duration) do
    effects =
      spell.abilities
      |> Map.take(@duration_abilities)
      |> Map.put("stack_key", spell.id)
      |> Map.put("stack_count", 1)

    if message = effects["StatusMessage"] do
      Mobile.send_scroll(target, "<p><span class='#{message_color(spell)}'>#{message}</span></p>")
    end

    Systems.Effect.add(target, effects, duration)
  end

  def affects_target?(%{} = target, %Spell{} = spell) do
    cond do
      Spell.has_ability?(spell, "AffectsLiving") and Mobile.has_ability?(target, "NonLiving") ->
        false
      Spell.has_ability?(spell, "AffectsAnimals") and Mobile.has_ability?(target, "Animal") ->
        false
      Spell.has_ability?(spell, "AffectsUndead") and Mobile.has_ability?(target, "Undead") ->
        false
      Spell.has_ability?(spell, "Poison") and Mobile.has_ability?(target, "PoisonImmunity") ->
        false
      true ->
        true
    end
  end

  def has_ability?(%Spell{} = spell, ability_name) do
    spell.abilities
    |> Map.keys
    |> Enum.member?(ability_name)
  end

  def apply_cooldowns(caster, %Spell{} = spell) do
    caster
    |> apply_spell_cooldown(spell)
    |> apply_round_cooldown(spell)
  end

  def apply_spell_cooldown(caster, %Spell{cooldown_in_ms: nil}), do: caster
  def apply_spell_cooldown(caster, %Spell{cooldown_in_ms: cooldown, name: name}) do
    Systems.Effect.add(caster, %{"cooldown" => name, "RemoveMessage" => "#{Text.capitalize_first(name)} is ready for use again."}, cooldown)
  end

  def apply_round_cooldown(caster, %Spell{ignores_round_cooldown?: true}), do: caster
  def apply_round_cooldown(caster, _spell) do
    cooldown = Mobile.round_length_in_ms(caster)
    Systems.Effect.add(caster, %{"cooldown" => :round}, cooldown)
  end

  def caster_cast_message(%Spell{result: :dodged} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      spell.abilities["DodgeUserMessage"]
      |> Text.interpolate(%{"target" => target, "spell" => spell.name})
      |> Text.capitalize_first

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end
  def caster_cast_message(%Spell{result: :resisted} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      @resist_message.user
      |> Text.interpolate(%{"target" => target, "spell" => spell.name})
      |> Text.capitalize_first

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end
  def caster_cast_message(%Spell{result: :deflected} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      @deflect_message.user
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first

    "<p><span class='dark-red'>#{message}</span></p>"
  end
  def caster_cast_message(%Spell{} = spell, %{} = caster, %{spell_shift: nil} = target, _mobile) do
    message =
      spell.user_message
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first

    "<p><span class='#{message_color(spell)}'>#{message}</span></p>"
  end
  def caster_cast_message(%Spell{} = spell, %{} = caster, %{spell_shift: shift} = target, mobile) do
    amount = abs(trunc(shift * Mobile.max_hp_at_level(target, mobile.level)))

    cond do
      amount < 1 and has_ability?(spell, "PhysicalDamage") ->
        spell
        |> Map.put(:result, :deflected)
        |> caster_cast_message(caster, target, mobile)
      amount < 1 and has_ability?(spell, "MagicalDamage") ->
        spell
        |> Map.put(:result, :resisted)
        |> caster_cast_message(caster, target, mobile)
      :else ->
        message =
          spell.user_message
          |> Text.interpolate(%{"target" => target, "amount" => amount})
          |> Text.capitalize_first

        "<p><span class='#{message_color(spell)}'>#{message}</span></p>"
    end
  end

  def target_cast_message(%Spell{result: :dodged} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      spell.abilities["DodgeTargetMessage"]
      |> Text.interpolate(%{"user" => caster, "spell" => spell.name})
      |> Text.capitalize_first

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end
  def target_cast_message(%Spell{result: :resisted} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      @resist_message.target
      |> Text.interpolate(%{"user" => caster, "spell" => spell.name})
      |> Text.capitalize_first

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end
  def target_cast_message(%Spell{result: :deflected} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      @deflect_message.target
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first

    "<p><span class='dark-red'>#{message}</span></p>"
  end
  def target_cast_message(%Spell{} = spell, %{} = caster, %{spell_shift: nil} = target, _mobile) do
    message =
      spell.target_message
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first

    "<p><span class='#{message_color(spell)}'>#{message}</span></p>"
  end
  def target_cast_message(%Spell{} = spell, %{} = caster, %{spell_shift: shift} = target, mobile) do
    amount = abs(trunc(target.spell_shift * Mobile.max_hp_at_level(target, mobile.level)))

    cond do
      amount < 1 and has_ability?(spell, "PhysicalDamage") ->
        spell
        |> Map.put(:result, :deflected)
        |> target_cast_message(caster, target, mobile)
      amount < 1 and has_ability?(spell, "MagicalDamage") ->
        spell
        |> Map.put(:result, :resisted)
        |> target_cast_message(caster, target, mobile)
      :else ->
        message =
          spell.target_message
          |> Text.interpolate(%{"user" => caster, "amount" => amount})
          |> Text.capitalize_first

        "<p><span class='#{message_color(spell)}'>#{message}</span></p>"
    end
  end

  def spectator_cast_message(%Spell{result: :dodged} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      spell.abilities["DodgeSpectatorMessage"]
      |> Text.interpolate(%{"user" => caster, "target" => target, "spell" => spell.name})
      |> Text.capitalize_first

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end
  def spectator_cast_message(%Spell{result: :resisted} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      @resist_message.spectator
      |> Text.interpolate(%{"user" => caster, "target" => target, "spell" => spell.name})
      |> Text.capitalize_first

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end
  def spectator_cast_message(%Spell{result: :deflected} = spell, %{} = caster, %{} = target, _mobile) do
    message =
      @deflect_message.spectator
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first

    "<p><span class='dark-red'>#{message}</span></p>"
  end
  def spectator_cast_message(%Spell{} = spell, %{} = caster, %{spell_shift: nil} = target, _mobile) do
    message =
      spell.spectator_message
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first

    "<p><span class='#{message_color(spell)}'>#{message}</span></p>"
  end
  def spectator_cast_message(%Spell{} = spell, %{} = caster, %{spell_shift: shift} = target, mobile) do
    amount = abs(trunc(target.spell_shift * Mobile.max_hp_at_level(target, mobile.level)))

    cond do
      amount < 1 and has_ability?(spell, "PhysicalDamage") ->
        spell
        |> Map.put(:result, :deflected)
        |> spectator_cast_message(caster, target, mobile)
      amount < 1 and has_ability?(spell, "MagicalDamage") ->
        spell
        |> Map.put(:result, :resisted)
        |> spectator_cast_message(caster, target, mobile)
      :else ->
        message =
          spell.spectator_message
          |> Text.interpolate(%{"user" => caster, "target" => target, "amount" => amount})
          |> Text.capitalize_first

        "<p><span class='#{message_color(spell)}'>#{message}</span></p>"
    end
  end

  def display_cast_message(%Room{} = room, %{} = caster, %{} = target, %Spell{} = spell) do
    room.mobiles
    |> Map.values
    |> Enum.each(fn mobile ->
         cond do
           mobile.ref == caster.ref and not is_nil(spell.user_message) ->
             Mobile.send_scroll(mobile, caster_cast_message(spell, caster, target, mobile))
           mobile.ref == target.ref and not is_nil(spell.target_message) ->
             Mobile.send_scroll(mobile, target_cast_message(spell, caster, target, mobile))
           mobile && not is_nil(spell.spectator_message) ->
             Mobile.send_scroll(mobile, spectator_cast_message(spell, caster, target, mobile))
         end
       end)
  end

  def display_pre_cast_message(%Room{} = room, %{} = caster, [target_ref | _rest] = targets, %Spell{abilities: %{"PreCastMessage" => message}} = spell) do
    target = Room.get_mobile(target_ref)

    message =
      message
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first

    Mobile.send_scroll(caster, "<p><span class='#{message_color(spell)}'>#{message}</span></p>")

    display_pre_cast_message(room, caster, targets, update_in(spell.abilities, &Map.delete(&1, "PreCastMessage")))
  end
  def display_pre_cast_message(%Room{} = room, %{} = caster, [target_ref | _rest], %Spell{abilities: %{"PreCastSpectatorMessage" => message}} = spell) do
    target = Room.get_mobile(target_ref)

    message = message
              |> Text.interpolate(%{"user" => caster, "target" => target})
              |> Text.capitalize_first

    Room.send_scroll(room, "<p><span class='#{message_color(spell)}'>#{message}</span></p>", caster)
  end
  def display_pre_cast_message(_room, _caster, _targets, _spell), do: :noop

  def message_color(%Spell{kind: kind}) when kind in ["attack", "curse"], do: "red"
  def message_color(%Spell{}), do: "blue"

  def can_execute?(%Room{} = room, caster_ref, spell) do
    mobile = Room.get_mobile(room, caster_ref)

    cond do
      cd = on_cooldown?(mobile, spell) ->
        Mobile.send_scroll(mobile, "<p>#{spell.name} is on cooldown: #{time_remaining(mobile, cd)} seconds remaining.</p>")
        false
      cd = on_round_cooldown?(mobile, spell) ->
        Mobile.send_scroll(mobile, "<p>You have already used an ability this round: #{time_remaining(mobile, cd)} seconds remaining.</p>")
        false
      Mobile.confused(mobile, room) ->
        false
      Mobile.silenced(mobile, room) ->
        false
      not_enough_mana?(mobile, spell) ->
        false
      true ->
        true
    end
  end

  def time_remaining(mobile, cd) do
    timer =
      cd
      |> Map.get("timers")
      |> Enum.at(0)

    time = TimerManager.time_remaining(mobile, timer)
    Float.round(time / 1000, 2)
  end

  def on_cooldown?(%{} = mobile, %Spell{cooldown_in_ms: nil} = spell), do: false
  def on_cooldown?(%{effects: effects} = mobile, %Spell{name: name} = spell) do
    effects
    |> Map.values
    |> Enum.any?(&(&1["cooldown"] == name))
  end

  def on_round_cooldown?(_mobile, %{ignores_round_cooldown?: true}), do: false
  def on_round_cooldown?(mobile, %{}), do: on_round_cooldown?(mobile)
  def on_round_cooldown?(%{effects: effects}) do
    effects
    |> Map.values
    |> Enum.find(&(&1["cooldown"] == :round))
  end

  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "monster or single"}, query) do
    match =
      room.mobiles
      |> Map.values
      |> Enum.reject(& &1.ref == caster_ref)
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end
  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "self"}, _query) do
    List.wrap(caster_ref)
  end
  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "monster"}, query) do
    match =
      room.mobiles
      |> Map.values
      |> Enum.filter(& &1.__struct__ == Monster)
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end
  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "full party area"}, _query) do
    caster_ref
    |> Room.get_mobile
    |> Mobile.party_refs(room)
  end
  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "full attack area"}, _query) do
    party =
      caster_ref
      |> Room.get_mobile
      |> Mobile.party_refs(room)

    room.mobiles
    |> Map.values
    |> Kernel.--(party)
  end
  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "self or single"}, query) do
    match =
      room.mobiles
      |> Map.values
      |> Enum.reject(& &1.__struct__ == Monster)
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end
  def get_targets(%Room{} = room, caster_ref, %Spell{targets: "single"}, query) do
    match =
      room.mobiles
      |> Map.values
      |> Enum.reject(& &1.__struct__ == Monster || &1.ref == caster_ref)
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end

  def not_enough_mana?(%{} = mobile, %Spell{ignores_round_cooldown?: true}), do: false
  def not_enough_mana?(%{} = mobile, %Spell{} = spell) do
    if !Mobile.enough_mana_for_spell?(mobile, spell) do
      Mobile.send_scroll(mobile, "<p><span class='red'>You do not have enough mana to use that ability.</span></p>")
    end
  end

end
