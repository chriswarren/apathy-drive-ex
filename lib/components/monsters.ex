defmodule Components.Monsters do
  use GenEvent.Behaviour

  ### Public API
  def value(entity) do
    :gen_event.call(entity, Components.Monsters, :value)
  end

  def value(entity, new_value) do
    ApathyDrive.Entity.notify(entity, {:set_monsters, new_value})
  end

  def add_monster(entity, monster) do
    ApathyDrive.Entity.notify(entity, {:add_monster, monster})
  end

  def serialize(_entity) do
    %{"Monsters" => []}
  end

  ### GenEvent API
  def init(_value) do
    {:ok, []}
  end

  def handle_call(:value, monsters) do
    {:ok, monsters, monsters}
  end

  def handle_event({:set_monsters, new_value}, _value) do
    {:ok, new_value }
  end

  def handle_event({:add_monster, monster}, value) do
    {:ok, [monster | value] |> Enum.uniq }
  end

  def handle_event({:remove_monster, monster}, value) do
    {:ok, List.delete(value, monster) }
  end

  def handle_event(_, current_value) do
    {:ok, current_value}
  end
end