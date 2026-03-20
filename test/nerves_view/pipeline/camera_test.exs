defmodule NervesView.Pipeline.CameraTest do
  use ExUnit.Case, async: true

  alias NervesView.Pipeline.Camera

  test "builds pipeline descriptor for v4l2 camera" do
    camera = %{id: "cam-1", device_path: "/dev/video0", source_type: :v4l2}
    assert {:ok, desc} = Camera.build(camera, fps: 20, bitrate: 1_000_000)

    assert desc.camera_id == "cam-1"
    assert desc.source_type == :v4l2
    assert desc.encoder.codec == :h264
    assert desc.stream.fps == 20
  end
end
