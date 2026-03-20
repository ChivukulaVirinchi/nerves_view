defmodule NervesView.Camera.SourceTest do
  use ExUnit.Case, async: true

  alias NervesView.Camera.Source

  test "infers source types from path" do
    assert Source.infer_source_type("rtsp://10.0.0.20/stream") == :rtsp
    assert Source.infer_source_type("/dev/video2") == :v4l2
    assert Source.infer_source_type("picam") == :libcamera
  end

  test "normalizes v4l2 camera" do
    assert {:ok, camera} = Source.normalize(%{id: "cam-v4l2", device_path: "/dev/video0"})
    assert camera.source_type == :v4l2
    assert camera.capture_backend == :v4l2
  end

  test "normalizes rtsp camera" do
    assert {:ok, camera} = Source.normalize(%{id: "cam-rtsp", device_path: "rtsp://cam/stream"})
    assert camera.source_type == :rtsp
  end
end
