defmodule NervesView.Recording.SegmentWriterTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.StreamBus
  alias NervesView.Recording.SegmentWriter

  @camera_id "test-cam-sw"
  @tmp_dir "tmp/test_recordings_sw"

  # Synthetic NALs
  @sps <<0x67, 0x42, 0x00, 0x1E, 0xAB>>
  @pps <<0x68, 0xCE, 0x38, 0x80>>
  @idr <<0x65, 0x88>> <> :binary.copy(<<0xAA>>, 100)
  @slice <<0x41, 0x9A>> <> :binary.copy(<<0xBB>>, 50)

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "starts and subscribes to StreamBus" do
    {:ok, pid} =
      SegmentWriter.start_link(
        camera_id: @camera_id,
        recordings_path: @tmp_dir
      )

    assert Process.alive?(pid)
    GenServer.stop(pid, :normal)
  end

  test "creates camera directory on init" do
    {:ok, pid} =
      SegmentWriter.start_link(
        camera_id: @camera_id,
        recordings_path: @tmp_dir
      )

    assert File.dir?(Path.join(@tmp_dir, @camera_id))
    GenServer.stop(pid, :normal)
  end

  test "buffers NALs and flushes on keyframe boundary" do
    {:ok, pid} =
      SegmentWriter.start_link(
        camera_id: @camera_id,
        recordings_path: @tmp_dir
      )

    now = System.system_time(:second)

    # Send SPS, PPS, then IDR to start buffering
    publish_nal(@sps, now)
    publish_nal(@pps, now)
    publish_nal(@idr, now)
    Process.sleep(50)

    # Send some P-frames
    for i <- 1..5 do
      publish_nal(@slice, now + i * 3000)
    end

    Process.sleep(50)

    # No segment written yet — target duration (6s) not elapsed
    cam_dir = Path.join(@tmp_dir, @camera_id)
    segments = list_segments(cam_dir)
    assert segments == []

    # Stop the writer — should flush remaining buffer as a final segment
    GenServer.stop(pid, :normal)
    Process.sleep(100)

    segments = list_segments(cam_dir)
    assert length(segments) >= 1

    # Verify segment is valid MPEG-TS (188-byte aligned, starts with 0x47)
    [first_seg | _] = segments
    content = File.read!(Path.join(cam_dir, first_seg))
    assert rem(byte_size(content), 188) == 0
    assert <<0x47, _::binary>> = content
  end

  test "ignores frames before first keyframe" do
    {:ok, pid} =
      SegmentWriter.start_link(
        camera_id: @camera_id,
        recordings_path: @tmp_dir
      )

    # Send P-frames without any preceding IDR
    for _ <- 1..10 do
      publish_nal(@slice, 0)
    end

    Process.sleep(50)
    GenServer.stop(pid, :normal)
    Process.sleep(50)

    # No segments should be written
    cam_dir = Path.join(@tmp_dir, @camera_id)
    assert list_segments(cam_dir) == []
  end

  test "ignores empty payloads" do
    {:ok, pid} =
      SegmentWriter.start_link(
        camera_id: @camera_id,
        recordings_path: @tmp_dir
      )

    StreamBus.publish(@camera_id, %{payload: <<>>, timestamp: 0, inserted_at: 0})
    StreamBus.publish(@camera_id, %{timestamp: 0, inserted_at: 0})
    Process.sleep(50)

    GenServer.stop(pid, :normal)

    cam_dir = Path.join(@tmp_dir, @camera_id)
    assert list_segments(cam_dir) == []
  end

  test "caches SPS and PPS for segment self-containment" do
    {:ok, pid} =
      SegmentWriter.start_link(
        camera_id: @camera_id,
        recordings_path: @tmp_dir
      )

    # Send SPS + PPS + IDR + slices + another IDR (to force flush)
    publish_nal(@sps, 0)
    publish_nal(@pps, 0)
    publish_nal(@idr, 0)

    for _ <- 1..5, do: publish_nal(@slice, 3000)
    Process.sleep(50)

    # Stop to flush
    GenServer.stop(pid, :normal)
    Process.sleep(50)

    cam_dir = Path.join(@tmp_dir, @camera_id)
    segments = list_segments(cam_dir)
    assert length(segments) >= 1

    # The segment should contain SPS+PPS at the beginning (inside the TS)
    content = File.read!(Path.join(cam_dir, hd(segments)))
    # SPS bytes should appear somewhere in the TS binary (wrapped in PES/TS packets)
    assert :binary.match(content, <<0x67, 0x42, 0x00, 0x1E, 0xAB>>) != :nomatch
  end

  # ── Helpers ──

  defp publish_nal(nal, timestamp) do
    StreamBus.publish(@camera_id, %{
      payload: nal,
      timestamp: timestamp,
      sequence_number: 0,
      inserted_at: System.system_time(:second)
    })
  end

  defp list_segments(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.match?(&1, ~r/^seg-\d+\.ts$/))
        |> Enum.sort()

      _ ->
        []
    end
  end
end
