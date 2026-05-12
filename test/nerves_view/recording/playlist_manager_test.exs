defmodule NervesView.Recording.PlaylistManagerTest do
  use ExUnit.Case, async: false

  alias NervesView.Recording.PlaylistManager

  @camera_id "test-cam-pm"
  @tmp_dir "tmp/test_recordings_pm"

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    :ok = PlaylistManager.clear()
    Application.put_env(:nerves_view, :recordings_path, @tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
      Application.put_env(:nerves_view, :recordings_path, "tmp/recordings")
    end)

    :ok
  end

  test "starts with no segments" do
    assert PlaylistManager.segments(@camera_id) == []
    assert PlaylistManager.retention_window(@camera_id) == nil
  end

  test "add_segment creates playlist file" do
    now = System.system_time(:second)

    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: Path.join([@tmp_dir, @camera_id, "seg-#{now}.ts"]),
        filename: "seg-#{now}.ts",
        started_at: now,
        duration: 6,
        size: 50_000
      })

    # Give the cast time to process
    Process.sleep(50)

    playlist_path = Path.join([@tmp_dir, @camera_id, "live.m3u8"])
    assert File.exists?(playlist_path)

    content = File.read!(playlist_path)
    assert content =~ "#EXTM3U"
    assert content =~ "#EXT-X-VERSION:3"
    assert content =~ "#EXT-X-TARGETDURATION:"
    assert content =~ "#EXTINF:6,"
    assert content =~ "seg-#{now}.ts"
  end

  test "segments returns added segments in order" do
    now = System.system_time(:second)

    for i <- 0..2 do
      :ok =
        PlaylistManager.add_segment(@camera_id, %{
          path: "seg-#{now + i * 6}.ts",
          filename: "seg-#{now + i * 6}.ts",
          started_at: now + i * 6,
          duration: 6,
          size: 50_000
        })
    end

    Process.sleep(50)

    segs = PlaylistManager.segments(@camera_id)
    assert length(segs) == 3
    assert Enum.at(segs, 0).started_at == now
    assert Enum.at(segs, 2).started_at == now + 12
  end

  test "retention_window returns oldest and newest timestamps" do
    now = System.system_time(:second)

    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: "seg-#{now}.ts",
        filename: "seg-#{now}.ts",
        started_at: now,
        duration: 6,
        size: 1000
      })

    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: "seg-#{now + 6}.ts",
        filename: "seg-#{now + 6}.ts",
        started_at: now + 6,
        duration: 6,
        size: 1000
      })

    Process.sleep(50)

    assert {oldest, newest} = PlaylistManager.retention_window(@camera_id)
    assert oldest == now
    assert newest == now + 12
  end

  test "remove_segment updates playlist" do
    now = System.system_time(:second)

    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: "seg-#{now}.ts",
        filename: "seg-#{now}.ts",
        started_at: now,
        duration: 6,
        size: 1000
      })

    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: "seg-#{now + 6}.ts",
        filename: "seg-#{now + 6}.ts",
        started_at: now + 6,
        duration: 6,
        size: 1000
      })

    Process.sleep(50)
    assert length(PlaylistManager.segments(@camera_id)) == 2

    :ok = PlaylistManager.remove_segment(@camera_id, now)
    Process.sleep(50)

    segs = PlaylistManager.segments(@camera_id)
    assert length(segs) == 1
    assert hd(segs).started_at == now + 6

    # Playlist file should be updated
    playlist_path = Path.join([@tmp_dir, @camera_id, "live.m3u8"])
    content = File.read!(playlist_path)
    refute content =~ "seg-#{now}.ts"
    assert content =~ "seg-#{now + 6}.ts"
    # Media sequence should have incremented
    assert content =~ "#EXT-X-MEDIA-SEQUENCE:1"
  end

  test "playlist TARGETDURATION reflects longest segment" do
    now = System.system_time(:second)

    :ok =
      PlaylistManager.add_segment(@camera_id, %{
        path: "seg-#{now}.ts",
        filename: "seg-#{now}.ts",
        started_at: now,
        duration: 9,
        size: 1000
      })

    Process.sleep(50)

    playlist_path = Path.join([@tmp_dir, @camera_id, "live.m3u8"])
    content = File.read!(playlist_path)
    assert content =~ "#EXT-X-TARGETDURATION:9"
  end

  test "handles multiple cameras independently" do
    now = System.system_time(:second)

    :ok =
      PlaylistManager.add_segment("cam-a", %{
        path: "seg-#{now}.ts",
        filename: "seg-#{now}.ts",
        started_at: now,
        duration: 6,
        size: 1000
      })

    :ok =
      PlaylistManager.add_segment("cam-b", %{
        path: "seg-#{now}.ts",
        filename: "seg-#{now}.ts",
        started_at: now,
        duration: 6,
        size: 2000
      })

    Process.sleep(50)

    assert length(PlaylistManager.segments("cam-a")) == 1
    assert length(PlaylistManager.segments("cam-b")) == 1
    assert PlaylistManager.segments("cam-c") == []
  end
end
