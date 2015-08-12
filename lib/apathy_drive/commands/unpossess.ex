defmodule Commands.Unpossess do
  use ApathyDrive.Command

  def keywords, do: ["unpossess"]

  def execute(%Spirit{} = spirit, _arguments) do
    spirit
    |> Spirit.send_scroll("<p>You aren't possessing anything.</p>")
  end

  def execute(%Monster{spirit: spirit} = monster, _arguments) do

    ApathyDrive.PubSub.unsubscribe(self, "spirits:online")
    ApathyDrive.PubSub.unsubscribe(self, "spirits:hints")
    ApathyDrive.PubSub.unsubscribe(self, "chat:gossip")
    ApathyDrive.PubSub.unsubscribe(self, "chat:#{spirit.faction}")
    ApathyDrive.PubSub.unsubscribe(self, "spirits:#{spirit.faction}")
    ApathyDrive.PubSub.unsubscribe(self, "rooms:#{monster.room_id}:monsters:#{Monster.monster_alignment(monster)}")
    ApathyDrive.PubSub.subscribe(self, "rooms:#{monster.room_id}:monsters:#{monster.alignment}")

    :global.unregister_name(:"spirit_#{spirit.id}")

    spirit =
      spirit
      |> Map.put(:room_id, monster.room_id)
      |> Map.put(:mana, min(monster.mana, spirit.max_mana))
      |> Spirit.login
      |> Spirit.send_scroll("<p>You leave the body of #{monster.name}.</p>")
      |> Systems.Prompt.update
      |> Spirit.save

    send(spirit.socket_pid, {:set_entity, spirit})

    spirit
  end

end
