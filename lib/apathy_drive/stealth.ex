defmodule ApathyDrive.Stealth do
  alias ApathyDrive.Mobile

  def visible?(sneaker, observer) do
    sneaker_level = Mobile.target_level(sneaker, observer)
    stealth = Mobile.stealth_at_level(sneaker, sneaker_level)

    observer_level = Mobile.caster_level(observer, sneaker)
    perception = Mobile.perception_at_level(observer, observer_level)

    IO.puts "stealth: #{inspect stealth}, perception: #{inspect perception}"

    stealth < perception
  end

  def invisible?(sneaker, observer) do
    !visible?(sneaker, observer)
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
