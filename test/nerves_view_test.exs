defmodule NervesViewTest do
  use ExUnit.Case, async: false

  alias NervesView.Camera.Registry
  alias NervesView.Recording.Store

  setup do
    for camera <- Registry.list() do
      Registry.remove(camera.id)
    end

    :ok = Store.clear()

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

  test "phase-2 signaling flow creates session and accepts answer" do
    assert {:ok, _camera} =
             NervesView.register_camera(%{
               id: "entry",
               name: "Entry",
               source_type: :libcamera,
               status: :streaming
             })

    assert {:ok, %{session_id: session_id, sdp: sdp}} = NervesView.create_stream_offer("entry")
    assert is_binary(session_id)
    assert is_binary(sdp)

    assert :ok = NervesView.apply_stream_answer(session_id, "v=0")
    assert :ok = NervesView.add_stream_ice_candidate(session_id, %{"candidate" => "c1"})
  end

  test "phase-3 motion + recording flow" do
    prev = [0, 0, 0, 0, 0]
    curr = [0, 1, 1, 0, 0]

    assert {:ok, %{motion?: true}} = NervesView.detect_motion(prev, curr, threshold: 0.3)

    assert {:ok, _rec} =
             NervesView.store_recording(%{
               id: "motion-1",
               camera_id: "entry",
               started_at: 100,
               ended_at: 110,
               mode: :motion,
               path: "/data/motion-1.mp4",
               motion_score: 0.4
             })

    assert [%{id: "motion-1"}] = NervesView.list_recordings(camera_id: "entry")
    assert 0 = NervesView.trim_recordings(10)
  end
end
