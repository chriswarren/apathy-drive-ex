defmodule ApathyDrive.TimerManager do
  alias ApathyDrive.{Mobile, Room, RoomServer}
  require Logger

  def seconds(seconds), do: seconds |> :timer.seconds |> trunc

  def send_after(%{timers: timers} = entity, {name, time, term}) do
    send_at = time + (Timex.Time.now |> Timex.Time.to_milliseconds |> trunc)

    timers = Map.put(timers, name, %{send_at: send_at, message: term})

    send(self, :start_timer)

    Map.put(entity, :timers, timers)
  end

  def apply_timers(%Room{timers: timers} = room) do
    now = Timex.Time.now |> Timex.Time.to_milliseconds

    timers
    |> Enum.reduce(room, fn {name, %{send_at: send_at, message: message}}, updated_room ->
         if send_at < now do
           updated_room = update_in(updated_room.timers, &Map.delete(&1, name))

           {:noreply, updated_room} = RoomServer.handle_info(message, updated_room)
           updated_room
         else
           updated_room
         end
       end)
  end

  def apply_timers(%Room{} = room, mobile_ref) do
    now = Timex.Time.now |> Timex.Time.to_milliseconds

    Room.update_mobile(room, mobile_ref, fn %{timers: timers} = mobile ->
      timers
      |> Enum.reduce(room, fn {name, %{send_at: send_at, message: message}}, updated_room ->
           if send_at < now do
             updated_room = update_in(updated_room.mobiles[mobile_ref].timers, &Map.delete(&1, name))

             {:noreply, updated_room} = RoomServer.handle_info(message, updated_room)
             updated_room
           else
             updated_room
           end
         end)
    end)
  end

  def timers(%{timers: timers}) do
    Map.keys(timers)
  end

  def time_remaining(%{timers: timers}, name) do
    if timer = Map.get(timers, name) do
      timer.send_at - Timex.Time.to_milliseconds(Timex.Time.now)
    else
      0
    end
  end

  def cancel(%{timers: timers} = entity, name) do
    put_in(entity.timers, Map.delete(timers, name))
  end

  def next_timer(%{timers: timers}) do
    timers
    |> Map.values
    |> Enum.map(&(&1.send_at))
    |> Enum.sort
    |> List.first
  end

end
