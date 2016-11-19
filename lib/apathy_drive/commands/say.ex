defmodule ApathyDrive.Commands.Say do
  use ApathyDrive.Command

  def keywords, do: ["say"]

  def execute(%Room{} = room, %Character{} = character, args) do
    message =
      args
      |> Enum.join(" ")
      |> Monster.sanitize()

    room.mobiles
    |> Map.values
    |> List.delete(character)
    |> Enum.each(fn
         %Character{} = observer when character != observer ->
           message = "<p>#{Mobile.colored_name(character, observer)} says: <span class='dark-green'>\"#{message}\"</span></p>"

           Mobile.send_scroll(observer, "<p><span class='dark-magenta'>#{message}</span></p>")
         _ ->
           :noop
       end)

    Mobile.send_scroll(character, "<p>You say: <span class='dark-green'>\"#{message}\"</span></p>")
    room
  end

end
