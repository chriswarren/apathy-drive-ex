defmodule Commands.BashTest do
  use ApathyDrive.ChannelCase

  setup do
    {:ok, spirit: test_spirit()}
  end

  test "receives an error message", %{spirit: spirit} do
    Commands.Bash.execute(spirit, ["north"])
    assert_push "scroll", %{html: "<p>You need a body to do that.</p>"}
  end
end
