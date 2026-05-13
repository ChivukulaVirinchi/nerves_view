defmodule NervesView.Streaming.PeerConnectionBusTest do
  use ExUnit.Case, async: false

  alias NervesView.Streaming.PeerConnection

  test "creates offer and updates session state" do
    session_id = "bus-session"

    assert {:ok, _pid} =
             start_supervised(
               {PeerConnection, session_id: session_id, camera_id: "cam-bus", viewer_id: "viewer"}
             )

    assert {:ok, offer_sdp} = PeerConnection.create_offer(session_id, "v=0\r\n")
    assert String.contains?(offer_sdp, "m=video")

    # The returned SDP goes through `rewrite_h264_level_in_answer` (forging the
    # H.264 profile-level-id to 42e028 to match what libcamera-vid actually
    # encodes), so it differs from the original stored in state.
    assert {:ok, snapshot} = PeerConnection.snapshot(session_id)
    assert is_binary(snapshot.offer_sdp)
    assert String.contains?(snapshot.offer_sdp, "m=video")
    assert snapshot.state == :connecting
  end
end
