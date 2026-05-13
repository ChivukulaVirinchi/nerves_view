defmodule NervesViewWeb.RecordingsLiveTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts, as: Store
  alias NervesView.Recording.Store, as: RecordingStore

  setup do
    :ok = RecordingStore.clear()
    :ok = Store.clear()
    :ok = SessionStore.clear()
    assert {:ok, _} = Store.register("recordings@example.com", "password123", :viewer)
    :ok
  end

  test "recordings page renders when there are no clips", %{conn: conn} do
    NervesView.DVR.SegmentIndex.clear()

    conn = login_via_post(conn, "recordings@example.com", "password123")
    assert redirected_to(conn) == ~p"/dashboard"

    conn = get(conn, ~p"/recordings")
    html = html_response(conn, 200)
    assert html =~ "No recordings match your filters"
    assert html =~ "Recordings"
  end
end
