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
