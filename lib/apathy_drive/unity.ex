defmodule ApathyDrive.Unity do
  use GenServer
  require Logger

  @interval 60_000

  def start_link do
    GenServer.start_link(__MODULE__, %{"evil" => [], "good" => []}, name: __MODULE__)
  end

  def init(essences) do
    Process.send_after(self(), :update_mobiles, @interval)
    {:ok, essences}
  end

  def contribute(unity, essence) do
    GenServer.cast(__MODULE__, {:contribute, unity, essence})
  end

  def handle_cast({:contribute, unity, essence}, essences) when unity in ["evil", "good"] do
    essences = update_in(essences, [unity], &([essence | &1]))

    {:noreply, essences}
  end

  def handle_info(:update_mobiles, essences) do
    essences
    |> Enum.each(fn
         {_unity, []} -> :noop
         {unity, list} ->
           average = Enum.sum(list) / length(list)
           ApathyDrive.PubSub.broadcast("mobiles", {:update_unity_essence, unity, average})
       end)

    Process.send_after(self(), :update_mobiles, @interval)

    {:noreply, %{"evil" => [], "good" => []}}
  end

end
