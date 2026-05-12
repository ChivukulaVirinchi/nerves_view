defmodule NervesView.DVR.SegmentIndexTest do
  use ExUnit.Case, async: false

  alias NervesView.DVR.SegmentIndex

  setup do
    :ok = SegmentIndex.clear()
    :ok
  end

  test "starts empty" do
    assert SegmentIndex.all_segments("cam-1") == []
    assert SegmentIndex.retention_window("cam-1") == nil
  end

  test "registers and retrieves segments" do
    now = System.system_time(:second)

    SegmentIndex.register("cam-1", now, %{
      duration: 6,
      filename: "seg-#{now}.ts",
      path: "/tmp/seg-#{now}.ts",
      size: 5000
    })

    SegmentIndex.register("cam-1", now + 6, %{
      duration: 6,
      filename: "seg-#{now + 6}.ts",
      path: "/tmp/seg-#{now + 6}.ts",
      size: 5200
    })

    # Give casts time to process
    Process.sleep(50)

    segs = SegmentIndex.all_segments("cam-1")
    assert length(segs) == 2
    assert hd(segs).started_at == now
    assert List.last(segs).started_at == now + 6
  end

  test "segments_for filters by time range" do
    now = System.system_time(:second)

    for i <- 0..4 do
      SegmentIndex.register("cam-1", now + i * 6, %{
        duration: 6,
        filename: "seg-#{now + i * 6}.ts",
        size: 1000
      })
    end

    Process.sleep(50)

    # Query for the middle range
    segs = SegmentIndex.segments_for("cam-1", now + 10, now + 20)
    # Segments overlapping [now+10, now+20]:
    # seg at now+6 (ends now+12) — overlaps
    # seg at now+12 (ends now+18) — overlaps
    # seg at now+18 (ends now+24) — overlaps
    assert length(segs) == 3
    assert hd(segs).started_at == now + 6
  end

  test "retention_window returns oldest and newest" do
    now = System.system_time(:second)

    SegmentIndex.register("cam-1", now, %{duration: 6, size: 100})
    SegmentIndex.register("cam-1", now + 60, %{duration: 6, size: 100})
    Process.sleep(50)

    assert {oldest, newest} = SegmentIndex.retention_window("cam-1")
    assert oldest == now
    assert newest == now + 66
  end

  test "removes segments" do
    now = System.system_time(:second)

    SegmentIndex.register("cam-1", now, %{duration: 6, size: 100})
    SegmentIndex.register("cam-1", now + 6, %{duration: 6, size: 100})
    Process.sleep(50)

    assert length(SegmentIndex.all_segments("cam-1")) == 2

    SegmentIndex.remove("cam-1", now)
    Process.sleep(50)

    segs = SegmentIndex.all_segments("cam-1")
    assert length(segs) == 1
    assert hd(segs).started_at == now + 6
  end

  test "handles multiple cameras independently" do
    now = System.system_time(:second)

    SegmentIndex.register("cam-a", now, %{duration: 6, size: 100})
    SegmentIndex.register("cam-b", now, %{duration: 6, size: 200})
    Process.sleep(50)

    assert length(SegmentIndex.all_segments("cam-a")) == 1
    assert length(SegmentIndex.all_segments("cam-b")) == 1
    assert SegmentIndex.all_segments("cam-c") == []
  end

  test "maintains ascending order when segments arrive out of order" do
    now = System.system_time(:second)

    SegmentIndex.register("cam-1", now + 12, %{duration: 6, size: 100})
    SegmentIndex.register("cam-1", now, %{duration: 6, size: 100})
    SegmentIndex.register("cam-1", now + 6, %{duration: 6, size: 100})
    Process.sleep(50)

    segs = SegmentIndex.all_segments("cam-1")
    timestamps = Enum.map(segs, & &1.started_at)
    assert timestamps == [now, now + 6, now + 12]
  end
end
