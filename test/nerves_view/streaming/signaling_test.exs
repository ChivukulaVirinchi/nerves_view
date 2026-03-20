defmodule NervesView.Streaming.SignalingTest do
  use ExUnit.Case, async: false

  alias NervesView.Streaming.Signaling

  test "creates offer and stores session" do
    assert {:ok, session_id, sdp} = Signaling.create_offer("cam-1", "fake-offer")
    assert is_binary(session_id)
    assert sdp == "fake-offer"

    assert {:ok, session} = Signaling.get_session(session_id)
    assert session.camera_id == "cam-1"
    assert session.offer_sdp == "fake-offer"
  end

  test "applies answer and candidate to existing session" do
    assert {:ok, session_id, _} = Signaling.create_offer("cam-2", "offer")
    assert :ok = Signaling.apply_answer(session_id, "answer")

    candidate = %{"candidate" => "candidate:1 1 UDP 1 0.0.0.0 9 typ host"}
    assert :ok = Signaling.add_ice_candidate(session_id, candidate)

    assert {:ok, session} = Signaling.get_session(session_id)
    assert session.answer_sdp == "answer"
    assert session.ice_candidates == [candidate]
  end

  test "returns not found for unknown session" do
    assert {:error, :not_found} = Signaling.apply_answer("missing", "answer")
    assert {:error, :not_found} = Signaling.add_ice_candidate("missing", %{})
    assert {:error, :not_found} = Signaling.get_session("missing")
  end
end
