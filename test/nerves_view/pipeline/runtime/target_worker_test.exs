defmodule NervesView.Pipeline.Runtime.TargetWorkerTest do
  use ExUnit.Case, async: true

  alias NervesView.Pipeline.Runtime.TargetWorker

  test "starts and reports health for libcamera" do
    assert {:ok, pid} =
             TargetWorker.start_link(source_type: :libcamera, source_path: "/dev/video0")

    snapshot = TargetWorker.snapshot(pid)
    assert snapshot.healthy
    assert snapshot.last_error == nil
  end

  test "frame publisher uses source-specific producer" do
    assert {:ok, publisher_pid} =
             NervesView.Pipeline.Runtime.FramePublisher.start_link(
               camera_id: "cam-local",
               source_type: :rtsp,
               source_path: "rtsp://example.local/stream"
             )

    Process.sleep(50)
    assert Process.alive?(publisher_pid)
  end

  test "rejects invalid rtsp source" do
    assert {:error, :invalid_source} =
             NervesView.Pipeline.Runtime.Target.start_pipeline(
               %{
                 camera_id: "cam-rtsp",
                 source_type: :rtsp,
                 source: %{device_path: "http://camera", backend: :rtsp}
               },
               []
             )
  end
end
