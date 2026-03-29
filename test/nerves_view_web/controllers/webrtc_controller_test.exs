defmodule NervesViewWeb.WebRTCControllerTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Camera.Registry
  alias NervesView.Streaming.Signaling

  setup do
    :ok = Signaling.clear()

    assert {:ok, _camera} =
             Registry.upsert(%{
               id: "front-door",
               name: "Front Door",
               source_type: :libcamera,
               status: :streaming
             })

    token = Phoenix.Token.sign(NervesViewWeb.Endpoint, "webrtc_stream", "test-user")
    %{token: token}
  end

  test "offer, answer and ice flow", %{conn: conn, token: token} do
    conn =
      post(conn, ~p"/api/webrtc/offer", %{
        camera_id: "front-door",
        viewer_id: "viewer-1",
        token: token
      })

    assert %{"session_id" => session_id, "offer_sdp" => offer} = json_response(conn, 200)
    assert offer =~ "m=video"

    conn =
      post(build_conn(), ~p"/api/webrtc/answer", %{session_id: session_id, answer_sdp: "v=0"})

    assert %{"ok" => true} = json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/api/webrtc/ice-candidate", %{
        session_id: session_id,
        role: "viewer",
        candidate: %{"candidate" => "c1"}
      })

    assert %{"ok" => true} = json_response(conn, 200)
  end

  test "returns not found for unknown camera", %{conn: conn, token: token} do
    conn =
      post(conn, ~p"/api/webrtc/offer", %{
        camera_id: "missing",
        viewer_id: "viewer-1",
        token: token
      })

    assert %{"error" => "camera_not_found"} = json_response(conn, 404)
  end

  test "rejects offer without token", %{conn: conn} do
    conn = post(conn, ~p"/api/webrtc/offer", %{camera_id: "front-door", viewer_id: "viewer-1"})
    assert json_response(conn, 400)
  end

  test "rejects offer with invalid token", %{conn: conn} do
    conn =
      post(conn, ~p"/api/webrtc/offer", %{
        camera_id: "front-door",
        viewer_id: "viewer-1",
        token: "bad-token"
      })

    assert %{"error" => "invalid_or_expired_token"} = json_response(conn, 401)
  end
end
