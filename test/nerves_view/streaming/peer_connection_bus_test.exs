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

    assert {:ok, snapshot} = PeerConnection.snapshot(session_id)
    assert snapshot.offer_sdp == offer_sdp
    assert snapshot.state == :connecting
  end
end
