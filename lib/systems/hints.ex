defmodule Systems.Hints do
  use Systems.Reload
  import Utility

  def initialize do
    every 60, do: display_hint
  end

  def display_hint do
    Components.all(Components.Hints) |> Enum.each(fn(entity) ->
      unless Systems.Idle.idle?(entity) do
        :random.seed(:erlang.now)
        hint = Components.Hints.value(entity).active
               |> Map.values
               |> Enum.shuffle
               |> List.first
        if hint do
          Components.Player.send_message(entity, ["scroll", "<p>\n<span class='yellow'>Hint:</span> <em>#{hint}</em>\n\n<p>"])
        end
      end
    end)
  end
end