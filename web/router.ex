defmodule ApathyDrive.Router do
  use Phoenix.Router
  use ExAdmin.Router

  pipeline :browser do
    plug :accepts, ~w(html)
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :assign_character
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug :require_admin
  end

  scope "/", ApathyDrive do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
    get  "/game", PageController, :game, as: :game
    resources "/sessions", SessionController
    resources "/characters", CharacterController, only: [:create, :edit, :update],
                                                  singleton: true
  end

  scope "/system", ApathyDrive do
    pipe_through [:browser, :admin]

    resources "/classes",           ClassController
    resources "/items",             ItemController
    resources "/monsters",          MonsterController
    resources "/rooms",             RoomController
    resources "/item_drops",        ItemDropController
    resources "/lairs",             LairController
    resources "/monster_abilities", MonsterAbilityController
    resources "/abilities",         AbilityController
  end

  scope "/admin", ExAdmin do
    pipe_through [:browser, :admin]
    admin_routes
  end

  scope "/auth", alias: ApathyDrive do
    pipe_through :browser
    get "/", AuthController, :index
    get "/callback", AuthController, :callback
  end

  # Fetch the current user from the session and add it to `conn.assigns`. This
  # will allow you to have access to the current user in your views with
  # `@current_user`.
  defp assign_character(conn, _) do
    character_id =
      conn
      |> get_session(:character)

    if character_id do
      character = ApathyDrive.Repo.get(ApathyDrive.Character, character_id)

      if character do
        conn
        |> assign(:character, character_id)
        |> assign(:admin?, !!character.admin)
      else
        conn
        |> put_session(:character, nil)
      end
    else
      conn
      |> put_session(:character, nil)
    end
  end

  defp require_admin(conn, _) do
    case conn.assigns[:admin?] do
      true ->
        conn
      _ ->
        conn
        |> redirect(to: "/")
        |> halt
    end
  end

end
