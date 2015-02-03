defmodule ApathyDrive.Command do
  defstruct name: nil, keywords: nil, module: nil
  use Systems.Reload
  import Utility

  def all do
    :code.all_loaded
    |> Enum.map(fn{module, _} -> to_string(module) end)
    |> Enum.filter(&(String.starts_with?(&1, "Elixir.Commands.") and !String.ends_with?(&1, "Test")))
    |> Enum.map(&String.to_atom/1)
  end

  def execute(%Spirit{} = spirit, command, arguments) do
    spirit
    |> Map.put(:idle, 0)
    |> Systems.Prompt.display

    room = Spirit.find_room(spirit)

    command_exit = room.exits
                   |> Enum.find(fn(ex) ->
                        ex.kind == "Command" and Enum.member?(ex.commands, [command | arguments] |> Enum.join(" "))
                      end)

    remote_action_exit = room.exits
                         |> Enum.find(fn(ex) ->
                              ex.kind == "RemoteAction" and Enum.member?(ex.commands, [command | arguments] |> Enum.join(" "))
                            end)

    cond do
      command_exit ->
        ApathyDrive.Exits.Command.move_via_command(room, spirit, command_exit)
      remote_action_exit ->
        ApathyDrive.Exits.RemoteAction.trigger_remote_action(room, spirit, remote_action_exit)
      true ->
        case Systems.Match.one(Enum.map(all, &(&1.to_struct)), :keyword_starts_with, command) do
          nil ->
            Spirit.send_scroll(spirit, "<p>What?</p>")
            spirit
          match ->
            match.module.execute(spirit, arguments)
        end
    end
  end

  def execute(%Monster{} = monster, command, arguments) do
    ability = monster.abilities
              |> Enum.find(fn(ability) ->
                   ability.properties(monster)[:command] == String.downcase(command)
                 end)

    if ability do
      Components.Module.value(ability).execute(monster, Enum.join(arguments, " "))
    else
      #execute_command(monster, command, arguments)
    end
  end

  defmacro __using__(_opts) do
    quote do
      use Systems.Reload
      import Utility
      import BlockTimer
      import Systems.Text

      def name do
        __MODULE__
        |> Atom.to_string
        |> String.split(".")
        |> List.last
        |> Inflex.underscore
      end

      def to_struct do
        %ApathyDrive.Command{name: name, keywords: keywords, module: __MODULE__}
      end
    end
  end

end
