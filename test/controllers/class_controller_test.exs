defmodule ApathyDrive.ClassControllerTest do
  use ApathyDrive.ConnCase

  alias ApathyDrive.Class
  @valid_attrs %{abilities: "some content", agility: 42, agility_per_level: 42, alignment: "some content", name: "some content", strength: 42, strength_per_level: 42, will: 42, will_per_level: 42}
  @invalid_attrs %{}

  setup do
    conn = conn()
    {:ok, conn: conn}
  end

  test "lists all entries on index", %{conn: conn} do
    conn = get conn, class_path(conn, :index)
    assert html_response(conn, 200) =~ "Listing classes"
  end

  test "renders form for new resources", %{conn: conn} do
    conn = get conn, class_path(conn, :new)
    assert html_response(conn, 200) =~ "New class"
  end

  test "creates resource and redirects when data is valid", %{conn: conn} do
    conn = post conn, class_path(conn, :create), class: @valid_attrs
    assert redirected_to(conn) == class_path(conn, :index)
    assert Repo.get_by(Class, @valid_attrs)
  end

  test "does not create resource and renders errors when data is invalid", %{conn: conn} do
    conn = post conn, class_path(conn, :create), class: @invalid_attrs
    assert html_response(conn, 200) =~ "New class"
  end

  test "shows chosen resource", %{conn: conn} do
    class = Repo.insert! %Class{}
    conn = get conn, class_path(conn, :show, class)
    assert html_response(conn, 200) =~ "Show class"
  end

  test "renders page not found when id is nonexistent", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      get conn, class_path(conn, :show, -1)
    end
  end

  test "renders form for editing chosen resource", %{conn: conn} do
    class = Repo.insert! %Class{}
    conn = get conn, class_path(conn, :edit, class)
    assert html_response(conn, 200) =~ "Edit class"
  end

  test "updates chosen resource and redirects when data is valid", %{conn: conn} do
    class = Repo.insert! %Class{}
    conn = put conn, class_path(conn, :update, class), class: @valid_attrs
    assert redirected_to(conn) == class_path(conn, :show, class)
    assert Repo.get_by(Class, @valid_attrs)
  end

  test "does not update chosen resource and renders errors when data is invalid", %{conn: conn} do
    class = Repo.insert! %Class{}
    conn = put conn, class_path(conn, :update, class), class: @invalid_attrs
    assert html_response(conn, 200) =~ "Edit class"
  end

  test "deletes chosen resource", %{conn: conn} do
    class = Repo.insert! %Class{}
    conn = delete conn, class_path(conn, :delete, class)
    assert redirected_to(conn) == class_path(conn, :index)
    refute Repo.get(Class, class.id)
  end
end
