defmodule NervesView.CameraTest do
  use ExUnit.Case, async: true

  alias NervesView.Camera

  describe "new/1" do
    test "builds a camera struct from valid attrs" do
      attrs = %{
        id: "front-door",
        name: "Front Door",
        source_type: :libcamera,
        status: :streaming,
        device_path: "/dev/video0",
        location: "Porch"
      }

      assert {:ok, %Camera{} = camera} = Camera.new(attrs)
      assert camera.id == "front-door"
      assert camera.name == "Front Door"
      assert camera.source_type == :libcamera
      assert camera.status == :streaming
    end

    test "rejects invalid source type" do
      attrs = %{id: "cam-1", name: "Cam", source_type: :unknown, status: :streaming}
      assert {:error, {:invalid_field, :source_type}} = Camera.new(attrs)
    end

    test "rejects missing required fields" do
      assert {:error, :missing_required_fields} = Camera.new(%{id: "cam-1"})
    end
  end
end
