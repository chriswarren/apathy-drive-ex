defmodule ApathyDrive.Exit do

  def direction_description(direction) do
    case direction do
    "up" ->
      "above you"
    "down" ->
      "below you"
    direction ->
      "to the #{direction}"
    end
  end

  def reverse_direction("north"),     do: "south"
  def reverse_direction("northeast"), do: "southwest"
  def reverse_direction("east"),      do: "west"
  def reverse_direction("southeast"), do: "northwest"
  def reverse_direction("south"),     do: "north"
  def reverse_direction("southwest"), do: "northeast"
  def reverse_direction("west"),      do: "east"
  def reverse_direction("northwest"), do: "southeast"
  def reverse_direction("up"),        do: "down"
  def reverse_direction("down"),      do: "up"

end
