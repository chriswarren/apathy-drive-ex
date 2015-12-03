defmodule Commands.Ask do
  use ApathyDrive.Command
  alias ApathyDrive.PubSub

  def keywords, do: ["ask"]

  def execute(mobile, []) do
    Mobile.send_scroll(mobile, "<p>Ask whom?</p>")
  end
  def execute(mobile, [_]) do
    Mobile.send_scroll(mobile, "<p>Ask what?</p>")
  end
  def execute(mobile, arguments) do
    [target | question] = arguments

    target = find_mobile_in_room(mobile, target)

    question =
      question
      |> Enum.join(" ")
      |> String.downcase

    ask(mobile, target, question)
  end

  def ask(mobile, nil, _question) do
    Mobile.send_scroll(mobile, "<p>Ask whom?</p>")
  end

  def ask(mobile, target, _question) when mobile == target do
    Mobile.send_scroll(mobile, "<p>Ask yourself?</p>")
  end

  def ask(mobile, target, question) do
    questions = Mobile.questions(target)

    if questions |> Map.keys |> Enum.member?(question) do
      Mobile.execute_script(mobile, questions[question])
    else
      Mobile.send_scroll(mobile, "<p><span class='dark-green'>#{Mobile.name(target)} has nothing to tell you!</span></p>")
    end
  end

  defp find_mobile_in_room(mobile, string) do
    PubSub.subscribers("rooms:#{Mobile.room_id(mobile)}:mobiles")
    |> Systems.Match.one(:name_contains, string)
  end

end
