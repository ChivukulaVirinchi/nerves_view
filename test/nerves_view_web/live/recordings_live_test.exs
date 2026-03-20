defmodule NervesViewWeb.RecordingsLiveTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts.Store
  alias NervesView.Recording.Store, as: RecordingStore

  setup do
    :ok = RecordingStore.clear()
    :ok = Store.clear()
    :ok = SessionStore.clear()
    assert {:ok, _} = Store.register("recordings@example.com", "password123", :viewer)
    :ok
  end

  test "recordings page shows hls playback links", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "email" => "recordings@example.com",
        "password" => "password123"
      })

    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/recordings")
    html = html_response(conn, 200)
    assert html =~ "HLS recording browser"
    assert html =~ "playlist.m3u8"
  end
end
