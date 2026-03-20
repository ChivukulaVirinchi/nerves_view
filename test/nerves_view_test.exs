defmodule NervesViewTest do
  use ExUnit.Case, async: false

  alias NervesView.Camera.Registry

  setup do
    for camera <- Registry.list() do
      Registry.remove(camera.id)
    end

    :ok
  end

  test "register_camera/1 stores camera in registry" do
    assert {:ok, camera} =
             NervesView.register_camera(%{
               id: "kitchen",
               name: "Kitchen",
               source_type: :libcamera,
               status: :streaming
             })

    assert camera.id == "kitchen"
    assert [%{id: "kitchen"}] = NervesView.list_cameras()
  end
end
