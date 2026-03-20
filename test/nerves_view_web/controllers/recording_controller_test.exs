defmodule NervesViewWeb.RecordingControllerTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Pipeline.HLSWriter
  alias NervesView.Recording.Store

  setup do
    :ok = Store.clear()
    assert {:ok, rec} = HLSWriter.write("cam-r", now: 1_700_702_000, segments: 2)
    {:ok, recording: rec}
  end

  test "serves m3u8 playlist", %{conn: conn, recording: rec} do
    conn = get(conn, ~p"/recordings/#{rec.id}/playlist.m3u8")
    body = response(conn, 200)

    assert body =~ "#EXTM3U"
    assert body =~ ".ts"
  end
end
