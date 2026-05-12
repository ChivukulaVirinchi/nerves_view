defmodule NervesViewWeb.DashboardLiveTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts.Store
  alias NervesView.Camera.Registry

  setup do
    :ok = Store.clear()
    :ok = SessionStore.clear()

    for camera <- Registry.list() do
      Registry.remove(camera.id)
    end

    assert {:ok, _} = Store.register("grid@example.com", "password123", :viewer)

    assert {:ok, _} =
             Registry.upsert(%{
               id: "cam-grid",
               name: "Grid Cam",
               source_type: :libcamera,
               status: :streaming
             })

    :ok
  end

  test "layout buttons render and dashboard shows cameras", %{conn: conn} do
    conn = login_via_post(conn, "grid@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/dashboard")
    html = html_response(conn, 200)
    assert html =~ "Live Feed"
    assert html =~ "cam-grid"
    assert html =~ "phx-value-n=\"9\""
    assert html =~ "Grid Cam"
  end
end
