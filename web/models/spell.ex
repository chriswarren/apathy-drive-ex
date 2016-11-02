defmodule ApathyDrive.Spell do
  use ApathyDrive.Web, :model
  alias ApathyDrive.{Match, Mobile, Room, Spell, Text, TimerManager}

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
    field :duration_in_ms, :integer
    field :cooldown_in_ms, :integer

    field :level, :integer, virtual: true
    field :abilities, :map, virtual: true, default: %{}
    field :ignores_round_cooldown?, :boolean, virtual: true, default: false

    has_many :characters, ApathyDrive.Character

    has_many :spells_abilities, ApathyDrive.SpellAbility

    timestamps
  end

  @required_fields ~w(name targets kind mana command description user_message target_message spectator_message duration_in_ms)
  @optional_fields ~w()

  @valid_targets ["monster or single", "self", "self or single", "monster", "full party area", "full attack area", "single", "full area"]
  @target_required_targets ["monster or single", "monster", "single"]

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ %{}) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  def base_mana_at_level(level), do: 500 + ((level - 1) * 50)

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

        room = put_in(room.mobiles[caster_ref], caster)

        targets
        |> Enum.reduce(room, fn(target_ref, updated_room) ->
             Room.update_mobile(updated_room, target_ref, fn target ->
               if affects_target?(target, spell) do
                 apply_spell(updated_room, caster, target, spell)
               else
                 message = "#{target.name} is not affected by that ability." |> Text.capitalize_first
                 Mobile.send_scroll(caster, "<p><span class='dark-cyan'>#{message}</span></p>")
                 updated_room
               end
             end)
           end)
        #|> execute_multi_cast(caster_ref, ability, targets)
        room
      end)
    else
      room
    end
  end

  def apply_spell(%Room{} = room, %{} = caster, %{} = target, %Spell{} = spell) do
    display_cast_message(room, caster, target, spell)

    room
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
    Systems.Effect.add(caster, %{"cooldown" => name, "expiration_message" => "#{Text.capitalize_first(name)} is ready for use again."}, cooldown)
  end

  def apply_round_cooldown(caster, %Spell{ignores_round_cooldown?: true}), do: caster
  def apply_round_cooldown(caster, _spell) do
    cooldown = Mobile.round_length_in_ms(caster)
    Systems.Effect.add(caster, %{"cooldown" => :round}, cooldown)
  end

  def display_cast_message(%Room{} = room, %{} = caster, %{} = target, %Spell{user_message: message} = spell) when is_binary(message) do
    message =
      message
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first

    Mobile.send_scroll(caster, "<p><span class='#{message_color(spell)}'>#{message}</span></p>")

    display_cast_message(room, caster, target, Map.put(spell, :user_message, nil))
  end
  def display_cast_message(%Room{} = room, %{} = caster, %{} = target, %Spell{target_message: message} = spell) when is_binary(message) and caster != target do
    message =
      message
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first

    Mobile.send_scroll(target, "<p><span class='#{message_color(spell)}'>#{message}</span></p>")

    display_cast_message(room, caster, target, Map.put(spell, :target_message, nil))
  end
  def display_cast_message(%Room{} = room, %{} = caster, %{} = target, %Spell{spectator_message: message} = spell) when is_binary(message) do
    message = message
              |> Text.interpolate(%{"user" => caster, "target" => target})
              |> Text.capitalize_first

    Room.send_scroll(room, "<p><span class='#{message_color(spell)}'>#{message}</span></p>", [caster, target])
  end
  def display_cast_message(_room, _caster, _target, _spell), do: :noop

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
