defmodule ApathyDrive.Commands.Abilities do
  use ApathyDrive.Command

  def keywords, do: ["abilities", "spells"]

  def execute(%Room{} = room, %Mobile{} = mobile, _arguments) do
    Mobile.send_scroll(mobile, "<p><span class='white'>You have the following abilities:</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-magenta'>Mana   Command  Ability Name</span></p>")
    display_abilities(mobile)
    room
  end

  def display_abilities(%Mobile{} = mobile) do
    mobile
    |> Map.get(:abilities)
    |> Enum.reject(&(Map.get(&1, "command") == nil))
    |> Enum.uniq(&(Map.get(&1, "command")))
    |> Enum.sort_by(&(Map.get(&1, "level")))
    |> Enum.each(fn(%{"name" => name, "command" => command} = ability) ->
         mana_cost = ability["mana_cost"]
                     |> to_string
                     |> String.ljust(6)

         command = command
                   |> to_string
                   |> String.ljust(8)

         Mobile.send_scroll(mobile, "<p><span class='dark-cyan'>#{mana_cost} #{command} #{name}</span></p>")
       end)
  end

end
