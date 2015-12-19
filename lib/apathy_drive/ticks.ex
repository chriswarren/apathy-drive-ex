defmodule ApathyDrive.Ticks do
  use Timex
  use GenServer
  alias ApathyDrive.{PubSub, TimerManager}

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(state) do
    state = state
            |> TimerManager.call_every({:idle, 1_000, &idle/0})
            |> TimerManager.call_every({:hints, 60_000, &hints/0})

    {:ok, state}
  end

  def idle do
    PubSub.broadcast!("spirits:online", :increment_idle)
  end

  def hints do
    PubSub.broadcast!("spirits:hints",  :display_hint)
  end

  def handle_info({:timeout, _ref, {name, time, function}}, %{timers: timers} = state) do
    jitter = trunc(time / 2) + :random.uniform(time)

    new_ref = :erlang.start_timer(jitter, self, {name, time, function})

    timers = Map.put(timers, name, new_ref)

    TimerManager.execute_function(function)

    {:noreply, Map.put(state, :timers, timers)}
  end

  def handle_info({:timeout, _ref, {name, function}}, %{timers: timers} = state) do
    TimerManager.execute_function(function)

    timers = Map.delete(timers, name)

    {:noreply, Map.put(state, :timers, timers)}
  end
end
