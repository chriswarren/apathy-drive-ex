defmodule ApathyDrive.CharacterController do
  use ApathyDrive.Web, :controller

  alias ApathyDrive.Character

  plug :scrub_params, "character" when action in [:create, :update]

  def index(conn, _params) do
    case conn.assigns[:current_player] do
      nil ->
        conn
        |> redirect(to: session_path(conn, :new))
      player_id ->
        player = Repo.get ApathyDrive.Player, player_id
        characters = Repo.all assoc(player, :characters)
        render(conn, "index.html", characters: characters)
    end
  end

  def new(conn, _params) do
    changeset = Character.changeset(%Character{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"character" => character_params}) do
    changeset = Character.changeset(%Character{}, character_params)

    if changeset.valid? do
      Repo.insert!(changeset)

      conn
      |> put_flash(:info, "Character created successfully.")
      |> redirect(to: character_path(conn, :index))
    else
      render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    character = Repo.get!(Character, id)
    render(conn, "show.html", character: character)
  end

  def edit(conn, %{"id" => id}) do
    character = Repo.get!(Character, id)
    changeset = Character.changeset(character)
    render(conn, "edit.html", character: character, changeset: changeset)
  end

  def update(conn, %{"id" => id, "character" => character_params}) do
    character = Repo.get!(Character, id)
    changeset = Character.changeset(character, character_params)

    if changeset.valid? do
      Repo.update!(changeset)

      conn
      |> put_flash(:info, "Character updated successfully.")
      |> redirect(to: character_path(conn, :index))
    else
      render(conn, "edit.html", character: character, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    character = Repo.get!(Character, id)
    Repo.delete!(character)

    conn
    |> put_flash(:info, "Character deleted successfully.")
    |> redirect(to: character_path(conn, :index))
  end
end
