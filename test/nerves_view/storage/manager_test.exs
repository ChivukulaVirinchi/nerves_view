defmodule NervesView.Storage.ManagerTest do
  use ExUnit.Case, async: false

  alias NervesView.Recording.Store
  alias NervesView.Recording.PlaylistManager
  alias NervesView.DVR.SegmentIndex
  alias NervesView.Storage.Manager

  setup do
    :ok = Store.clear()
    :ok = SegmentIndex.clear()
    :ok = PlaylistManager.clear()
    :ok
  end

  test "reports usage and enforces retention" do
    now = System.system_time(:second)

    for i <- 1..3 do
      {:ok, _} =
        Store.put(%{
          id: "rec-#{i}",
          camera_id: "cam-a",
          started_at: now + i * 10,
          ended_at: now + i * 10 + 9,
          mode: :continuous,
          path: "/fake/path/#{i}.m3u8",
          size_bytes: 1000 * i
        })
    end

    usage = Manager.usage()
    assert usage.recording_count == 3
    assert usage.total_bytes > 0

    result = Manager.enforce_retention(max_count: 2)
    assert result.trimmed == 1

    remaining = Store.list()
    assert length(remaining) == 2
  end

  test "clear_recordings removes recording files and resets indexes" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "nerves-view-clear-#{System.unique_integer([:positive])}")

    Application.put_env(:nerves_view, :recordings_path, tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      Application.put_env(:nerves_view, :recordings_path, "tmp/recordings")
    end)

    camera_dir = Path.join(tmp_dir, "cam-a")
    File.mkdir_p!(camera_dir)
    segment_path = Path.join(camera_dir, "seg-100.ts")
    File.write!(segment_path, :binary.copy(<<0x47>>, 188))

    SegmentIndex.register("cam-a", 100, %{
      duration: 6,
      filename: "seg-100.ts",
      path: segment_path,
      size: 188
    })

    PlaylistManager.add_segment("cam-a", %{
      started_at: 100,
      duration: 6,
      filename: "seg-100.ts",
      path: segment_path,
      size: 188
    })

    Process.sleep(50)

    assert {:ok, %{files: files, bytes: bytes}} = Manager.clear_recordings()
    assert files >= 1
    assert bytes >= 188
    assert SegmentIndex.all_segments("cam-a") == []
    assert PlaylistManager.segments("cam-a") == []
    assert File.ls!(tmp_dir) == []
  end
end
