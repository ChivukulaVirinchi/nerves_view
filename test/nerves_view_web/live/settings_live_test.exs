defmodule NervesViewWeb.SettingsLiveTest do
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

    assert {:ok, _} = Store.register("settings@example.com", "password123", :admin)
    :ok
  end

  test "settings page shows add camera form", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "email" => "settings@example.com",
        "password" => "password123"
      })

    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/settings")
    html = html_response(conn, 200)
    assert html =~ "Add camera"
    assert html =~ "camera[source_type]"
  end
end
