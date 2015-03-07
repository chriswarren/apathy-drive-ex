defmodule Commands.Possess do
  use ApathyDrive.Command

  def keywords, do: ["possess"]

  def execute(%Spirit{} = spirit, []) do
    spirit
    |> Spirit.send_scroll("<p>Possess what?</p>")
  end

  def execute(%Spirit{room_id: room_id} = spirit, arguments) do
    monsters = Phoenix.PubSub.subscribers("rooms:#{room_id}:monsters")

    case Systems.Match.one(monsters, :name_contains, Enum.join(arguments, " ")) do
      nil ->
        Spirit.send_scroll(spirit, "<p>You do not notice that here.</p>")
      monster ->
        possess(spirit, Monster.value(monster))
    end
  end

  def possess(%Spirit{level: level} = spirit, %Monster{possession_level: possession_level} = monster)
    when level < possession_level do
    spirit
    |> Spirit.send_scroll("<p>You must be at least level #{possession_level} to possess #{monster.name}.")
  end

  def possess(%Spirit{} = spirit, %Monster{} = monster) do
    Phoenix.PubSub.subscribe(spirit.pid, "monsters:#{monster.id}")
    Phoenix.PubSub.unsubscribe(spirit.pid, "rooms:#{spirit.room_id}")

    spirit = spirit
             |> Map.put(:monster, monster.pid)
             |> Spirit.send_scroll("<p>You possess #{monster.name}.")

    Systems.Prompt.update(monster)
    spirit
  end

  def execute(%Monster{} = monster, _arguments) do
    Monster.send_scroll(monster, "<p>You must unpossess #{monster.name} first.</p>")
  end

end
