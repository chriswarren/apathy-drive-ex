defmodule Commands.CloseTest do
  use ExUnit.Case
  use ShouldI
  import ApathyDrive.Matchers.Socket

  with "a spirit" do
    setup context do
      Dict.put(context, :spirit, %Spirit{socket: %Phoenix.Socket{pid: self}})
    end

    should_add_to_scroll "<p>You need a body to do that.</p>" do
      Commands.Close.execute(context.spirit, ["north"])
    end
  end

end
