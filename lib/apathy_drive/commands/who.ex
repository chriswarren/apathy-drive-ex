defmodule Commands.Who do
  use ApathyDrive.Command
  alias ApathyDrive.Mobile

  def keywords, do: ["who"]

  def execute(mobile, _arguments) do
    Mobile.send_scroll(mobile, "<p><span class='dark-cyan'>Name                Faction               Possessing</span></p>")
    Mobile.send_scroll(mobile, "<p><span class='dark-green'>==============================================================</span></p>")

    ApathyDrive.PubSub.subscribers("spirits:online")
    |> Enum.map(fn(pid) ->
         Mobile.data_for_who_list(pid)
       end)
    |> Enum.each(fn(line) ->
         Mobile.send_scroll(mobile, format_line(line))
       end)
  end

  def format_line(%{name: name, possessing: "", faction: faction} = line) do
    color = Mobile.alignment_color(line)

    "<p><span class='#{color}'>#{String.ljust(name, 20)}</span><span class='#{color}'>#{faction}</span></p>"
  end

  def format_line(%{name: name, possessing: monster, faction: faction} = line) do
    color = Mobile.alignment_color(line)
    faction = String.ljust(faction, 20)

    "<p><span class='#{color}'>#{String.ljust(name, 20)}</span><span class='#{color}'>#{faction}</span><span class='#{color}'>#{monster}</span></p>"
  end

end
