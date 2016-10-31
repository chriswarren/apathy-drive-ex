defmodule ApathyDrive.Commands.Score do
  use ApathyDrive.Command
  alias ApathyDrive.{Character, Mobile}

  def keywords, do: ["score", "stats", "status", "st"]

  def execute(%Room{} = room, %Character{} = character, _arguments) do
    show_score(character)
    room
  end

  defp show_score(%Character{} = character) do
    score_data = Character.score_data(character)
    hits = Enum.join([score_data.hp, score_data.max_hp], "/") |> String.ljust(13)
    mana = Enum.join([score_data.mana, score_data.max_mana], "/") |> String.ljust(13)

    Mobile.send_scroll(character, "<p><span class='dark-green'>Name:</span> <span class='dark-cyan'>#{String.ljust(score_data.name, 13)}</span><span class='dark-green'>Level:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.level), 13)}</span><span class='dark-green'>Exp:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.experience), 13)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Race:</span> <span class='dark-cyan'>#{String.ljust(score_data.race, 13)}</span><span class='dark-green'>Physical Dmg:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.physical_damage), 6)}</span><span class='dark-green'>Perception:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.perception), 6)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Class:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.class), 12)}</span><span class='dark-green'>Physical Res:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.physical_resistance), 6)}</span><span class='dark-green'>Stealth:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.stealth), 9)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Hits:</span> <span class='dark-cyan'>#{hits}</span><span class='dark-green'>Magical Dmg:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.magical_damage), 7)}</span><span class='dark-green'>Tracking:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.tracking), 8)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Mana:</span> <span class='dark-cyan'>#{mana}</span><span class='dark-green'>Magical Res:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.magical_resistance), 7)}</span><span class='dark-green'>Accuracy:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.accuracy), 8)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>#{String.rjust("Dodge:", 45)}</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.dodge), 11)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Strength:</span>  <span class='dark-cyan'>#{String.ljust(to_string(score_data.strength), 7)}</span> <span class='dark-green'>Agility:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.agility), 11)}</span><span class='dark-green'>Spellcasting:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.spellcasting), 4)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Intellect:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.intellect), 7)}</span> <span class='dark-green'>Health:</span>  <span class='dark-cyan'>#{String.ljust(to_string(score_data.health), 11)}</span><span class='dark-green'>Crits:</span> <span class='dark-cyan'>#{String.rjust(to_string(score_data.crits), 11)}</span></p>")
    Mobile.send_scroll(character, "<p><span class='dark-green'>Willpower:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.willpower), 7)}</span> <span class='dark-green'>Charm:</span>   <span class='dark-cyan'>#{score_data.charm}</span></p>")

    Enum.each(score_data.effects, fn(effect_message) ->
      Mobile.send_scroll(character, "<p>#{effect_message}</p>")
    end)
  end

  defp show_score(%Monster{} = monster) do
    score_data = Monster.score_data(monster)

    hp = String.ljust("#{trunc(score_data.hp)}/#{score_data.max_hp}", 15)
    mana = "#{trunc(score_data.mana)}/#{score_data.max_mana}"

    Monster.send_scroll(monster, "<p> <span class='dark-green'>Name:</span> <span class='dark-cyan'>#{String.ljust(score_data.name, 15)}</span><span class='dark-green'>Class:</span> <span class='dark-cyan'>#{score_data.class}</span></p>")
    Monster.send_scroll(monster, "<p><span class='dark-green'>Level:</span> <span class='dark-cyan'>#{String.ljust(to_string(score_data.level), 15)}</span><span class='dark-green'>Essence:</span> <span class='dark-cyan'>#{trunc(score_data.experience)}</span></p>")
    Monster.send_scroll(monster, "<p> <span class='dark-green'>Hits:</span> <span class='dark-cyan'>#{hp}</span><span class='dark-green'>Mana:</span> <span class='dark-cyan'>#{mana}</span></p>")
    Monster.send_scroll(monster, "\n\n")
    Monster.send_scroll(monster, "<p><span class='dark-green'>Physical Damage:</span>  <span class='dark-cyan'>#{String.ljust(to_string(score_data.physical_damage), 6)}</span> <span class='dark-green'>Magical Damage:</span>  <span class='dark-cyan'>#{score_data.magical_damage}</span></p>")
    phys_def = Float.to_string(score_data.physical_defense, decimals: 2) <> "%"
    Monster.send_scroll(monster, "<p><span class='dark-green'>Physical Defense:</span> <span class='dark-cyan'>#{String.ljust(phys_def, 6)}</span> <span class='dark-green'>Magical Defense:</span> <span class='dark-cyan'>#{Float.to_string(score_data.magical_defense, decimals: 2)}%</span></p>")
    Monster.send_scroll(monster, "\n\n")
    Monster.send_scroll(monster, "<p><span class='dark-green'>Strength:</span> <span class='dark-cyan'>#{score_data.strength}</span></p>")
    Monster.send_scroll(monster, "<p><span class='dark-green'>Agility:</span>  <span class='dark-cyan'>#{score_data.agility}</span></p>")
    Monster.send_scroll(monster, "<p><span class='dark-green'>Will:</span>     <span class='dark-cyan'>#{score_data.will}</span></p>")

    limbs(monster)

    Enum.each(score_data.effects, fn(effect_message) ->
      Monster.send_scroll(monster, "<p>#{effect_message}</p>")
    end)
  end

  defp limbs(%Monster{missing_limbs: missing, crippled_limbs: crippled} = monster) do
    Enum.each crippled, fn limb ->
      Monster.send_scroll(monster, "<p>Your #{limb} is crippled!</p>")
    end

    Enum.each missing, fn limb ->
      Monster.send_scroll(monster, "<p>Your #{limb} has been severed!</p>")
    end
  end

end
