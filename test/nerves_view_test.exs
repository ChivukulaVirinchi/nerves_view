defmodule NervesViewTest do
  use ExUnit.Case, async: false

  alias NervesView.Camera.Registry
  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts, as: AccountStore
  alias NervesView.Alerts
  alias NervesView.Cluster.NodeRegistry
  alias NervesView.Network.Discovery
  alias NervesView.Recording.Store
  alias NervesView.Streaming.Signaling

  setup do
    for camera <- Registry.list() do
      Registry.remove(camera.id)
    end

    :ok = Store.clear()
    :ok = NodeRegistry.clear()
    :ok = Discovery.clear()
    :ok = AccountStore.clear()
    :ok = SessionStore.clear()
    :ok = Alerts.clear()
    :ok = Signaling.clear()

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

    assert {:ok, %{session_id: session_id, sdp: sdp}} =
             NervesView.create_stream_offer("entry", "viewer-1")

    assert is_binary(session_id)
    assert is_binary(sdp)

    assert :ok = NervesView.apply_stream_answer(session_id, "v=0")
    assert :ok = NervesView.add_stream_ice_candidate(session_id, :viewer, %{"candidate" => "c1"})
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

  test "phase-4 node registration and service discovery flow" do
    now = 1_700_100_000

    assert {:ok, %{id: "hub-main"}} =
             NervesView.register_node(%{
               id: "hub-main",
               mode: :hub,
               host: "hub.local",
               port: 4000
             })

    assert {:ok, %{id: "node-east"}} =
             NervesView.register_node(%{
               id: "node-east",
               mode: :node,
               host: "east.local",
               port: 5000
             })

    assert :ok = NervesView.node_heartbeat("node-east", now)
    assert [%{id: "node-east"}] = NervesView.list_nodes(mode: :node)

    assert {:ok, %{service_id: "svc-east-front"}} =
             NervesView.announce_camera_service(%{
               service_id: "svc-east-front",
               node_id: "node-east",
               camera_id: "front-door",
               host: "east.local",
               port: 4100,
               last_seen_at: now
             })

    assert [%{service_id: "svc-east-front"}] = NervesView.list_camera_services()
    assert ["svc-east-front"] = NervesView.prune_stale_services(5, now + 10)
    assert ["node-east"] = NervesView.prune_stale_nodes(5, now + 10)
  end

  test "phase-5 account registration, auth and authorization flow" do
    assert {:ok, admin} =
             NervesView.register_user("admin@nervesview.local", "password123", :admin)

    assert {:ok, viewer} =
             NervesView.register_user("viewer@nervesview.local", "password123", :viewer)

    assert {:ok, %{user: logged_in, session: session}} =
             NervesView.login("admin@nervesview.local", "password123", now: 1_700_200_000)

    assert logged_in.id == admin.id
    assert {:ok, _session} = NervesView.validate_session(session.token, 1_700_200_001)
    assert :ok = NervesView.authorize(admin.role, :manage_users)
    assert {:error, :forbidden} = NervesView.authorize(viewer.role, :manage_users)

    assert :ok = NervesView.logout(session.token)
    assert {:error, :not_found} = NervesView.validate_session(session.token, 1_700_200_001)
  end

  test "phase-6 alerts flow with throttling" do
    now = 1_700_300_000

    assert {:ok, %{camera_id: "backyard"}} =
             NervesView.notify_motion_event("backyard", now, throttle_seconds: 10)

    assert {:error, :throttled} =
             NervesView.notify_motion_event("backyard", now + 3, throttle_seconds: 10)

    assert {:ok, _} = NervesView.notify_motion_event("backyard", now + 12, throttle_seconds: 10)

    assert [%{camera_id: "backyard"}, %{camera_id: "backyard"}] = NervesView.list_alerts()
  end
end
