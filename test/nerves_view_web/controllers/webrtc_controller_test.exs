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

  # An offer_sdp is required by the controller. These bad-path tests use a
  # placeholder string that the controller rejects before SDP parsing because
  # of the earlier camera / auth checks. The happy path is exercised on-device
  # because it needs DTLS + a real ExWebRTC-built SDP.
  @placeholder_offer "v=0"

  test "returns not found for unknown camera", %{conn: conn, token: token} do
    conn =
      post(conn, ~p"/api/webrtc/offer", %{
        camera_id: "missing",
        viewer_id: "viewer-1",
        token: token,
        offer_sdp: @placeholder_offer
      })

    assert %{"error" => "camera_not_found"} = json_response(conn, 404)
  end

  test "rejects offer without offer_sdp", %{conn: conn, token: token} do
    conn =
      post(conn, ~p"/api/webrtc/offer", %{
        camera_id: "front-door",
        viewer_id: "viewer-1",
        token: token
      })

    assert json_response(conn, 400)
  end

  test "rejects offer with invalid token", %{conn: conn} do
    conn =
      post(conn, ~p"/api/webrtc/offer", %{
        camera_id: "front-door",
        viewer_id: "viewer-1",
        token: "bad-token",
        offer_sdp: @placeholder_offer
      })

    assert %{"error" => "invalid_or_expired_token"} = json_response(conn, 401)
  end

  test "rejects close without session_id", %{conn: conn} do
    conn = post(conn, ~p"/api/webrtc/close", %{})
    assert %{"error" => "session_id_required"} = json_response(conn, 400)
  end
end
