defmodule Components.Strength do
  use GenEvent.Behaviour

  ### Public API
  def value(entity) do
    :gen_event.call(entity, Components.Strength, :value)
  end

  def value(entity, new_value) do
    ApathyDrive.Entity.notify(entity, {:set_strength, new_value})
  end

  def serialize(entity) do
    {"Strength", value(entity)}
  end

  ### GenEvent API
  def init(value) do
    {:ok, value}
  end

  def handle_call(:value, value) do
    {:ok, value, value}
  end

  def handle_event({:set_strength, value}, _value) do
    {:ok, value }
  end

  def handle_event(_, current_value) do
    {:ok, current_value}
  end
end
