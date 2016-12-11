defmodule ApathyDrive.Stealth do
  alias ApathyDrive.Mobile

  def visible?(sneaker, observer, room) do
    sneaker_level = Mobile.target_level(sneaker, observer)
    stealth = Mobile.stealth_at_level(sneaker, sneaker_level, room)

    observer_level = Mobile.caster_level(observer, sneaker)
    perception = Mobile.perception_at_level(observer, observer_level, room)

    stealth < perception
  end

  def invisible?(sneaker, observer, room) do
    !visible?(sneaker, observer, room)
  end

  def reveal(sneaker) do
    effect = %{
      "Revealed" => true,
      "stack_key" => :revealed,
      "stack_count" => 1,
      "RemoveMessage" => "<span class='dark-grey'>You step into the shadows.</span>"
    }

    Systems.Effect.add(sneaker, effect, 4000)
  end
end
