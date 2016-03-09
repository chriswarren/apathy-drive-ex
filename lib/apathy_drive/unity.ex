defmodule ApathyDrive.Unity do
  use GenServer
  require Logger
  alias ApathyDrive.{Mobile, World}

  @interval 60_000

  def start_link do
    GenServer.start_link(__MODULE__, ["demon", "angel"], name: __MODULE__)
  end

  def init(unities) do
    Process.send_after(self, :redistribute_essence, @interval)

    {:ok, unities}
  end

  def handle_info(:redistribute_essence, unities) do
    Enum.each(unities, fn(unity) ->
      Logger.debug "Redstributing Essence for #{unity}"
      contributors = ApathyDrive.PubSub.subscribers("#{unity}-unity")

      if Enum.any?(contributors) do
       contributions = contributions(contributors)

        contributions
        |> calculate_distributions()
        |> distribute()

        average =
          contributions
          |> Map.values
          |> Enum.sum
          |> div(map_size(contributions))

        World.set_average_essence(unity, average)
      end
    end)

    Process.send_after(self, :redistribute_essence, @interval)

    {:noreply, unities}
  end

  def calculate_distributions(contributions) do
    exp_pool =
      contributions
      |> Map.values
      |> Enum.sum

    contributions
    |> Map.keys
    |> Enum.sort_by(&Map.get(contributions, &1))
    |> calculate_distributions(contributions, exp_pool)
  end

  defp calculate_distributions([], distributions, _exp_pool), do: distributions
  defp calculate_distributions([contributor | rest] = contributors, contributions, exp_pool) do
    contribution = contributions[contributor]
    share = min(contribution * 2, div(exp_pool, length(contributors)))

    difference = share - contribution

    contributions = Map.put(contributions, contributor, difference)

    calculate_distributions(rest, contributions, exp_pool - share)
  end

  defp distribute(distributions) do
    Enum.each(distributions, fn({member, amount}) ->
      entity = World.mobile(member) || World.room(member)

      Logger.debug "#{entity.name} essence changes by #{inspect amount}"
      adjust_essence(member, amount)
    end)
  end

  defp contributions(contributors) do
    contributors
    |> Enum.reduce(%{}, fn(member, contributions) ->
         entity = World.mobile(member) || World.room(member)

         case entity do
           %Mobile{} ->
             essence = entity.experience || entity.spirit.experience
             contribution = div(essence, 100)
             Logger.debug "#{entity.name} contributes #{inspect contribution}"
             Map.put(contributions, member, contribution)
           %Room{} ->
             essence = Room.essence(entity)
             contribution = div(essence, 100)
             Logger.debug "#{entity.name} contributes #{inspect contribution}"
             Map.put(contributions, member, contribution)
         end
       end)
  end

  defp adjust_essence(_member, amount) when amount == 0, do: :noop
  defp adjust_essence(member, amount) when amount > 0 do
    entity = World.mobile(member) || World.room(member)
    case entity do
      %Mobile{} ->
        Mobile.send_scroll(member, "<p>[<span class='yellow'>unity</span>]: You receive #{amount} essence.</p>")
        Mobile.add_experience(member, amount)
      %Room{} ->
        send(member, {:add_essence, amount})
    end
  end
  defp adjust_essence(member, amount) when amount < 0 do
    entity = World.mobile(member) || World.room(member)
    case entity do
      %Mobile{} ->
        Mobile.send_scroll(member, "<p>[<span class='yellow'>unity</span>]: You contribute #{abs(amount)} essence.</p>")
        Mobile.add_experience(member, amount)
      %Room{} ->
        send(member, {:add_essence, amount})
    end
  end

end