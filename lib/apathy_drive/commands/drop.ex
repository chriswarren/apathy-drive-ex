defmodule ApathyDrive.Commands.Drop do
  use ApathyDrive.Command
  alias ApathyDrive.{Character, Match, Mobile, Item, Repo, RoomItem}

  def keywords, do: ["drop"]

  def execute(%Room{} = room, %Character{} = character, []) do
    Mobile.send_scroll(character, "<p>Drop what?</p>")
    room
  end

  def execute(%Room{} = room, %Character{} = character, arguments) do
    inventory = Character.inventory(character)

    item_name = Enum.join(arguments, " ")

    inventory
    |> Enum.map(& %{name: &1.item.name, character_item: &1})
    |> Match.one(:name_contains, item_name)
    |> case do
         nil ->
           Mobile.send_scroll(character, "<p>You don't have \"#{item_name}\" to drop!</p>")

           room
         %{character_item: %{level: level, item: %Item{} = item} = character_item} ->

           Ecto.Multi.new
           |> Ecto.Multi.insert(:rooms_items, %RoomItem{room_id: room.id, item_id: item.id, level: level})
           |> Ecto.Multi.delete(:characters_items, character_item)
           |> Repo.transaction
           |> IO.inspect

           room
           |> Repo.preload([rooms_items: :item], [force: true])
           |> Room.update_mobile(character.ref, fn(char) ->
                char
                |> Repo.preload([characters_items: :item], [force: true])
                |> Mobile.send_scroll("<p>You drop #{Item.colored_name(item)}.</p>")
              end)
      end
  end
end
