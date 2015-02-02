defmodule Commands.Search do
  use ApathyDrive.Command

  def keywords, do: ["sea", "search"]

  def execute(%Spirit{} = spirit, _arguments) do
    spirit
    |> Spirit.send_scroll("<p>You need a body to do that.</p>")
  end

  def execute(_spirit, monster, arguments) do
    current_room = Parent.of(monster)

    if Enum.any? arguments do
      direction = arguments
                  |> Enum.join(" ")
                  |> ApathyDrive.Exit.direction

      room_exit = ApathyDrive.Exit.get_exit_by_direction(current_room, direction)

      case room_exit do
        nil ->
          send_message(monster, "scroll", "<p>There is no exit in that direction!</p>")
        %{"kind" => "Hidden"} ->
          ApathyDrive.Exits.Hidden.search(monster, current_room, room_exit)
        %{"direction" => direction} ->
          send_message(monster, "scroll", "<p>You notice nothing different #{ApathyDrive.Exit.direction_description(direction)}.</p>")
      end
    else
      send_message(monster, "scroll", "<p>Your search revealed nothing.</p>")
    end
  end

end
