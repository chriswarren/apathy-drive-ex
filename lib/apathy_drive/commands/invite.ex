defmodule ApathyDrive.Commands.Invite do
  use ApathyDrive.Command
  alias ApathyDrive.{Character, TimerManager}

  def keywords, do: ["invite", "inv"]

  def execute(%Room{} = room, %Character{} = character, arguments) do
    query = Enum.join(arguments)

    case Room.find_mobile_in_room(room, character, query) do
      %Character{ref: ref, name: name} = target ->
        Room.update_mobile(room, character.ref, fn(character) ->
          Mobile.send_scroll(character, "<p><span class='blue'>You have invited #{name} to follow you.</span></p>")
          Mobile.send_scroll(target, "<p><span class='blue'>#{character.name} have invited you to follow them.</span></p>")
          character
          |> update_in([:invitees], &Enum.uniq([ref | &1]))
          |> put_in([:leader], character.ref)
          |> TimerManager.send_after({{:expire_invite, ref}, 60_000, {:expire_invite, character.ref, ref}})
        end)
      mobile ->
        Mobile.send_scroll(character, "<p>You don't see #{query} here!</p>")
        room
    end
  end
end
