defmodule NervesView.Camera.RegistryTest do
  use ExUnit.Case, async: false

  alias NervesView.Camera.Registry

  setup do
    File.rm_rf!("tmp/persistence")

    for camera <- Registry.list() do
      Registry.remove(camera.id)
    end

    :ok
  end

  test "upsert and list cameras" do
    assert {:ok, camera} =
             Registry.upsert(%{
               id: "living-room",
               name: "Living Room",
               source_type: :v4l2,
               status: :initializing
             })

    assert camera.id == "living-room"
    assert [%{id: "living-room"}] = Registry.list()
  end

  test "get existing and missing camera" do
    assert {:ok, _camera} =
             Registry.upsert(%{
               id: "garage",
               name: "Garage",
               source_type: :rtsp,
               status: :offline
             })

    assert {:ok, camera} = Registry.get("garage")
    assert camera.name == "Garage"
    assert {:error, :not_found} = Registry.get("missing")
  end

  test "persists registry state to disk" do
    assert {:ok, camera} =
             Registry.upsert(%{
               id: "cam-persist",
               name: "Persisted",
               source_type: :libcamera,
               status: :streaming
             })

    path = NervesView.Persistence.path_for("cameras.term")
    assert File.exists?(path)
    assert {:ok, bin} = File.read(path)
    persisted = :erlang.binary_to_term(bin)
    assert persisted[camera.id].id == "cam-persist"
  end
end
