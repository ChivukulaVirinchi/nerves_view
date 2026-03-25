defmodule NervesView.Streaming.PeerManagerTest do
  use ExUnit.Case, async: false

  alias NervesView.Streaming.PeerConnection
  alias NervesView.Streaming.PeerManager

  test "starts session and stores signaling state" do
    session_id = "session-a"
    assert {:ok, _pid} = PeerManager.start_session(session_id, "cam-a", "viewer-a")
    assert {:ok, session} = PeerManager.get_session(session_id)
    assert session.camera_id == "cam-a"
    assert session.viewer_id == "viewer-a"

    assert :ok = PeerConnection.set_offer(session_id, "offer")
    assert :ok = PeerConnection.set_answer(session_id, "answer")
    assert :ok = PeerConnection.add_ice_candidate(session_id, :viewer, %{"candidate" => "v1"})

    assert {:ok, updated} = PeerManager.get_session(session_id)
    assert updated.offer_sdp == "offer"
    assert updated.answer_sdp == "answer"
    assert updated.ice_candidates.viewer == [%{"candidate" => "v1"}]
    assert updated.state in [:connecting, :new]

    assert :ok = PeerConnection.mark_connected(session_id)
    assert {:ok, connected} = PeerManager.get_session(session_id)
    assert connected.state == :connected

    assert :ok = PeerManager.stop_session(session_id)
    assert {:error, :not_found} = PeerManager.get_session(session_id)
  end
end
