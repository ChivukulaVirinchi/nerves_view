defmodule NervesViewWeb.RecordingControllerTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Recording.PlaylistManager

  @camera_id "cam-ctrl-test"
  @tmp_dir "tmp/test_recordings_ctrl"

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(Path.join(@tmp_dir, @camera_id))
    :ok = PlaylistManager.clear()
    Application.put_env(:nerves_view, :recordings_path, @tmp_dir)

    # Create a fake segment file
    now = System.system_time(:second)
    seg_file = "seg-#{now}.ts"
    seg_path = Path.join([@tmp_dir, @camera_id, seg_file])
    File.write!(seg_path, :binary.copy(<<0x47>>, 188))

    # Register it in PlaylistManager
    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: seg_path,
        filename: seg_file,
        started_at: now,
        duration: 6,
        size: 188
      })

    Process.sleep(50)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
      Application.put_env(:nerves_view, :recordings_path, "tmp/recordings")
    end)

    {:ok, seg_file: seg_file, now: now}
  end

  test "serves live m3u8 playlist", %{conn: conn, seg_file: seg_file} do
    conn = get(conn, "/cameras/#{@camera_id}/live.m3u8")
    body = response(conn, 200)

    assert body =~ "#EXTM3U"
    assert body =~ "/cameras/#{@camera_id}/segments/#{seg_file}"
  end

  test "serves segment file", %{conn: conn, seg_file: seg_file} do
    conn = get(conn, "/cameras/#{@camera_id}/segments/#{seg_file}")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "video/mp2t"
  end

  test "returns 404 for missing camera", %{conn: conn} do
    conn = get(conn, "/cameras/nonexistent/live.m3u8")
    assert response(conn, 404)
  end

  test "rejects invalid segment name", %{conn: conn} do
    conn = get(conn, "/cameras/#{@camera_id}/segments/not-a-segment.ts")
    assert response(conn, 400)
  end
end
