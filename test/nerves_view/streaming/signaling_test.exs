defmodule NervesView.Streaming.SignalingTest do
  use ExUnit.Case, async: false

  alias NervesView.Streaming.Signaling

  setup do
    :ok = Signaling.clear()
    :ok
  end

  test "creates offer and stores session" do
    assert {:ok, session_id, sdp} = Signaling.create_offer("cam-1", "viewer-1", "fake-offer")
    assert is_binary(session_id)
    assert String.contains?(sdp, "m=video")

    assert {:ok, session} = Signaling.get_session(session_id)
    assert session.camera_id == "cam-1"
    assert session.viewer_id == "viewer-1"
    assert String.contains?(session.offer_sdp, "m=video")
    assert session.state == :connecting
  end

  test "applies answer and candidate to existing session" do
    assert {:ok, session_id, _} = Signaling.create_offer("cam-2", "viewer-2", "offer")
    assert :ok = Signaling.apply_answer(session_id, "answer")
    assert :ok = Signaling.mark_connected(session_id)

    candidate = %{"candidate" => "candidate:1 1 UDP 1 0.0.0.0 9 typ host"}
    assert :ok = Signaling.add_ice_candidate(session_id, :viewer, candidate)

    assert {:ok, session} = Signaling.get_session(session_id)
    assert session.answer_sdp == "answer"
    assert session.ice_candidates.viewer == [candidate]
    assert session.state == :connected
  end

  test "reaps expired sessions that are not connected" do
    assert {:ok, session_id, _} = Signaling.create_offer("cam-3", "viewer-3", "offer")
    assert [^session_id] = Signaling.reap_expired(System.system_time(:second) + 120)
    assert {:error, :not_found} = Signaling.get_session(session_id)
  end

  test "returns not found for unknown session" do
    assert {:error, :not_found} = Signaling.apply_answer("missing", "answer")
    assert {:error, :not_found} = Signaling.add_ice_candidate("missing", :viewer, %{})
    assert {:error, :not_found} = Signaling.get_session("missing")
  end
end
