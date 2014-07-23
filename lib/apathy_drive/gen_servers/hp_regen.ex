defmodule HPRegen do
  use Systems.Reload
  use GenServer

  # Public API
  def add(entity) do
    GenServer.cast(:hp_regen, {:add, entity})
  end

  def remove(entity) do
    GenServer.cast(:hp_regen, {:remove, entity})
  end

  def all do
    GenServer.call(:hp_regen, :all)
  end

  # GenServer API
  def start_link() do
    GenServer.start_link(__MODULE__, HashSet.new, name: :hp_regen)
  end

  def init(value) do
    {:ok, value}
  end

  def handle_cast({:add, entity}, entities) do
    {:noreply, HashSet.put(entities, entity) }
  end

  def handle_cast({:remove, entity}, entities) do
    {:noreply, HashSet.delete(entities, entity) }
  end

  def handle_call(:all, _from, entities) do
    {:reply, entities, entities}
  end

end