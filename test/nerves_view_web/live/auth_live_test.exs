defmodule NervesViewWeb.AuthLiveTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Accounts.SessionStore
  alias NervesView.Camera.Registry
  alias NervesView.Pipeline.Manager
  alias NervesView.Accounts.Store

  setup do
    File.rm_rf!("tmp/persistence")
    :ok = Store.clear()
    :ok = SessionStore.clear()
    :ok = Manager.clear()

    for camera <- Registry.list() do
      Registry.remove(camera.id)
    end

    assert {:ok, _camera} =
             Registry.upsert(%{
               id: "cam-ui",
               name: "UI Camera",
               source_type: :libcamera,
               status: :streaming
             })

    :ok
  end

  test "register first user promotes admin and redirects to dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/setup"

    {:ok, _view, html} = live(build_conn(), ~p"/register")
    assert html =~ "First account becomes admin"

    conn = register_via_post(conn, "owner@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"
    [user] = Store.list_users()
    assert user.role == :admin
  end

  test "login redirects to dashboard", %{conn: conn} do
    assert {:ok, _} = Store.register("viewer@example.com", "password123", :viewer)

    conn = login_via_post(conn, "viewer@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "protected route redirects to login", %{conn: conn} do
    conn = get(conn, ~p"/dashboard")
    assert redirected_to(conn) == ~p"/login"
  end

  test "full flow register then logout then login", %{conn: conn} do
    conn = register_via_post(conn, "ops@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/logout")
    assert redirected_to(conn) == ~p"/login"

    conn = login_via_post(conn, "ops@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "dashboard starts test pipeline", %{conn: conn} do
    assert {:ok, _} = Store.register("dash@example.com", "password123", :viewer)

    conn = login_via_post(conn, "dash@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/dashboard")
    assert html_response(conn, 200) =~ "Live Feed"
    assert {:ok, status} = Manager.status("cam-ui")
    assert status.status == :running
  end

  test "setup route redirects to login after first user exists", %{conn: conn} do
    assert {:ok, _} = Store.register("owner2@example.com", "password123", :admin)

    conn = get(conn, ~p"/setup")
    assert redirected_to(conn) == ~p"/login"
  end
end
