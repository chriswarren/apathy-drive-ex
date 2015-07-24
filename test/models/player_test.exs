defmodule ApathyDrive.PlayerTest do
  use ApathyDrive.ModelCase

  alias ApathyDrive.Player

  @valid_attrs %{email: "adam@apathydrive.com",
                 password: "awesome password",
                 password_confirmation: "awesome password"}

  @invalid_email %{email: "adamapathydrive.com",
                   password: "awesome password",
                   password_confirmation: "awesome password"}

  @short_password %{email: "adam@apathydrive.com",
                    password: "pswd",
                    password_confirmation: "pswd"}

  @pw_confirmation %{email: "adam@apathydrive.com",
                     password: "awesome password",
                     password_confirmation: "awesome pw"}

  test "sign_up changeset with valid attributes" do
    changeset = Player.sign_up_changeset(%Player{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with an invalid email address" do
    changeset = Player.sign_up_changeset(%Player{}, @invalid_email)
    assert changeset.errors == [email: "has invalid format"]
    refute changeset.valid?
  end

  test "changeset with a password that is too short" do
    changeset = Player.sign_up_changeset(%Player{}, @pw_confirmation)
    assert changeset.errors ==  [password: "does not match confirmation"]
    refute changeset.valid?
  end
end
