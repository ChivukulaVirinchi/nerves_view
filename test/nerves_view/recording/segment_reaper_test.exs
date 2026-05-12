defmodule NervesView.Recording.SegmentReaperTest do
  use ExUnit.Case, async: false

  @tmp_dir "tmp/test_recordings_reaper"

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    Application.put_env(:nerves_view, :recordings_path, @tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
      Application.put_env(:nerves_view, :recordings_path, "tmp/recordings")
    end)

    :ok
  end

  test "deletes segments older than retention window" do
    cam_dir = Path.join(@tmp_dir, "cam-reap")
    File.mkdir_p!(cam_dir)

    now = System.system_time(:second)
    old_ts = now - 3600 * 25
    recent_ts = now - 60

    # Create an old segment and a recent one
    File.write!(Path.join(cam_dir, "seg-#{old_ts}.ts"), "old data")
    File.write!(Path.join(cam_dir, "seg-#{recent_ts}.ts"), "recent data")

    # Set retention to 1 hour for this test
    Application.put_env(:nerves_view, :recording_retention_hours, 1)

    # Trigger reap manually via send
    send(NervesView.Recording.SegmentReaper, :check)
    Process.sleep(100)

    # Old segment should be gone
    refute File.exists?(Path.join(cam_dir, "seg-#{old_ts}.ts"))
    # Recent segment should survive
    assert File.exists?(Path.join(cam_dir, "seg-#{recent_ts}.ts"))

    # Restore default
    Application.put_env(:nerves_view, :recording_retention_hours, 720)
  end

  test "ignores non-segment files" do
    cam_dir = Path.join(@tmp_dir, "cam-reap2")
    File.mkdir_p!(cam_dir)

    File.write!(Path.join(cam_dir, "live.m3u8"), "#EXTM3U")
    File.write!(Path.join(cam_dir, "notes.txt"), "hello")

    Application.put_env(:nerves_view, :recording_retention_hours, 0)
    send(NervesView.Recording.SegmentReaper, :check)
    Process.sleep(100)

    # Non-segment files should remain
    assert File.exists?(Path.join(cam_dir, "live.m3u8"))
    assert File.exists?(Path.join(cam_dir, "notes.txt"))

    Application.put_env(:nerves_view, :recording_retention_hours, 720)
  end

  test "handles missing recordings directory gracefully" do
    Application.put_env(:nerves_view, :recordings_path, "/nonexistent/path")

    # Should not crash
    send(NervesView.Recording.SegmentReaper, :check)
    Process.sleep(100)

    assert Process.alive?(Process.whereis(NervesView.Recording.SegmentReaper))
  end
end
