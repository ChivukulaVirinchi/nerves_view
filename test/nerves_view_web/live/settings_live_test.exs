defmodule NervesViewWeb.SettingsLiveTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts, as: Store
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
    conn = login_via_post(conn, "settings@example.com", "password123")

    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/settings")
    html = html_response(conn, 200)
    assert html =~ "Add Camera"
    assert html =~ "camera[source_type]"
    assert html =~ "Diagnostics"
    assert html =~ "Recording Storage"
    assert html =~ "Clear all recordings"
  end
end
