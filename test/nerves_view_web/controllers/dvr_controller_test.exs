defmodule NervesViewWeb.DVRControllerTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.DVR.SegmentIndex

  @camera_id "cam-dvr-test"
  @tmp_dir "tmp/test_recordings_dvr"

  setup do
    File.rm_rf!(@tmp_dir)
    dir = Path.join(@tmp_dir, @camera_id)
    File.mkdir_p!(dir)
    :ok = SegmentIndex.clear()
    Application.put_env(:nerves_view, :recordings_path, @tmp_dir)

    now = System.system_time(:second)

    # Create 3 segments on disk and register in index
    for i <- 0..2 do
      ts = now - 18 + i * 6
      filename = "seg-#{ts}.ts"
      path = Path.join(dir, filename)
      File.write!(path, :binary.copy(<<0x47>>, 188))

      SegmentIndex.register(@camera_id, ts, %{
        duration: 6,
        filename: filename,
        path: path,
        size: 188
      })
    end

    Process.sleep(50)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
      Application.put_env(:nerves_view, :recordings_path, "tmp/recordings")
    end)

    email = "dvr-#{System.unique_integer([:positive])}@example.com"
    conn = register_via_post(Phoenix.ConnTest.build_conn(), email, "password123")

    {:ok, conn: conn, now: now}
  end

  test "GET /api/dvr/:camera_id/playlist.m3u8 requires authentication", %{now: now} do
    from = now - 20
    conn = get(Phoenix.ConnTest.build_conn(), "/api/dvr/#{@camera_id}/playlist.m3u8?from=#{from}")
    assert json_response(conn, 401)["error"] == "unauthenticated"
  end

  test "GET /api/dvr/:camera_id/playlist.m3u8 returns valid playlist", %{conn: conn, now: now} do
    from = now - 20
    conn = get(conn, "/api/dvr/#{@camera_id}/playlist.m3u8?from=#{from}")
    body = response(conn, 200)

    assert body =~ "#EXTM3U"
    assert body =~ "#EXT-X-PLAYLIST-TYPE:EVENT"
    assert body =~ "#EXT-X-ENDLIST"
    assert body =~ "/api/dvr/#{@camera_id}/segments/seg-"
    assert body =~ "#EXTINF:6,"
  end

  test "GET /api/dvr/:camera_id/playlist.m3u8 returns 404 for empty range", %{conn: conn} do
    conn = get(conn, "/api/dvr/#{@camera_id}/playlist.m3u8?from=999999999999")
    assert json_response(conn, 404)["error"] == "no_segments_in_range"
  end

  test "GET /api/dvr/:camera_id/segments/:filename serves .ts file", %{conn: conn, now: now} do
    ts = now - 18
    conn = get(conn, "/api/dvr/#{@camera_id}/segments/seg-#{ts}.ts")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "video/mp2t"
    assert get_resp_header(conn, "cache-control") |> hd() =~ "immutable"
  end

  test "GET /api/dvr/:camera_id/segments/ rejects bad filenames", %{conn: conn} do
    conn = get(conn, "/api/dvr/#{@camera_id}/segments/evil-file.ts")
    assert json_response(conn, 400)["error"] == "invalid_segment_name"
  end

  test "GET /api/dvr/:camera_id/segments/ returns 404 for missing file", %{conn: conn} do
    conn = get(conn, "/api/dvr/#{@camera_id}/segments/seg-1.ts")
    assert json_response(conn, 404)["error"] == "segment_not_found"
  end

  test "GET /api/dvr/:camera_id/timeline returns metadata", %{conn: conn} do
    conn = get(conn, "/api/dvr/#{@camera_id}/timeline")
    body = json_response(conn, 200)

    assert body["camera_id"] == @camera_id
    assert is_integer(body["oldest_ts"])
    assert is_integer(body["newest_ts"])
    assert body["segment_count"] == 3
  end

  test "GET /api/dvr/:camera_id/timeline returns nulls for unknown camera", %{conn: conn} do
    conn = get(conn, "/api/dvr/unknown-cam/timeline")
    body = json_response(conn, 200)

    assert body["oldest_ts"] == nil
    assert body["segment_count"] == 0
  end
end
