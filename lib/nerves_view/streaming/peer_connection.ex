defmodule NervesView.Streaming.PeerConnection do
  @moduledoc """
  Per-viewer signaling state for a camera stream session.
  """

  use GenServer

  alias ExRTP.Packet
  alias ExWebRTC.ICECandidate
  alias ExWebRTC.MediaStreamTrack
  alias ExWebRTC.PeerConnection, as: WebRTCPeer
  alias ExWebRTC.SessionDescription
  alias NervesView.Pipeline.StreamBus

  @type role :: :viewer | :publisher
  @timeout_seconds 45
  @max_mailbox_len 30

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def set_offer(session_id, sdp), do: GenServer.call(via(session_id), {:set_offer, sdp})
  def set_answer(session_id, sdp), do: GenServer.call(via(session_id), {:set_answer, sdp})

  def create_offer(session_id, fallback_sdp),
    do: GenServer.call(via(session_id), {:create_offer, fallback_sdp})

  def add_ice_candidate(session_id, role, candidate)
      when role in [:viewer, :publisher] and is_map(candidate) do
    GenServer.call(via(session_id), {:add_ice, role, candidate})
  end

  def snapshot(session_id), do: GenServer.call(via(session_id), :snapshot)
  def mark_connected(session_id), do: GenServer.call(via(session_id), :mark_connected)
  def close(session_id, reason \\ :normal), do: GenServer.call(via(session_id), {:close, reason})
  def stop(session_id), do: GenServer.stop(via(session_id), :normal)

  @impl true
  def init(opts) do
    now = System.system_time(:second)
    {:ok, pc} = WebRTCPeer.start(controlling_process: self(), video_codecs: [:h264])

    state = %{
      session_id: Keyword.fetch!(opts, :session_id),
      camera_id: Keyword.fetch!(opts, :camera_id),
      viewer_id: Keyword.fetch!(opts, :viewer_id),
      offer_sdp: nil,
      answer_sdp: nil,
      ice_candidates: %{viewer: [], publisher: []},
      state: :new,
      state_reason: nil,
      timeout_at: now + @timeout_seconds,
      pc: pc,
      sender_track_id: nil,
      inserted_at: now,
      updated_at: now
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_offer, fallback_sdp}, _from, state) do
    with {:ok, state} <- ensure_sender_track(state),
         {:ok, %SessionDescription{} = offer} <- WebRTCPeer.create_offer(state.pc),
         :ok <- WebRTCPeer.set_local_description(state.pc, offer) do
      now = System.system_time(:second)

      next = %{
        state
        | offer_sdp: offer.sdp,
          state: :connecting,
          updated_at: now,
          timeout_at: now + @timeout_seconds
      }

      {:reply, {:ok, offer.sdp}, next}
    else
      _ ->
        now = System.system_time(:second)

        next = %{
          state
          | offer_sdp: fallback_sdp,
            state: :connecting,
            state_reason: :offer_fallback,
            updated_at: now,
            timeout_at: now + @timeout_seconds
        }

        {:reply, {:ok, fallback_sdp}, next}
    end
  end

  def handle_call({:set_offer, sdp}, _from, state) do
    now = System.system_time(:second)

    next = %{
      state
      | offer_sdp: sdp,
        state: :connecting,
        updated_at: now,
        timeout_at: now + @timeout_seconds
    }

    {:reply, :ok, next}
  end

  def handle_call({:set_answer, sdp}, _from, state) do
    _ = WebRTCPeer.set_remote_description(state.pc, %SessionDescription{type: :answer, sdp: sdp})
    now = System.system_time(:second)

    next = %{
      state
      | answer_sdp: sdp,
        state: :connecting,
        updated_at: now,
        timeout_at: now + @timeout_seconds
    }

    {:reply, :ok, next}
  end

  def handle_call({:add_ice, role, candidate}, _from, state) do
    _ = maybe_add_ice_candidate(state.pc, candidate)
    next_candidates = Map.update!(state.ice_candidates, role, &[candidate | &1])
    now = System.system_time(:second)

    next = %{
      state
      | ice_candidates: next_candidates,
        updated_at: now,
        timeout_at: now + @timeout_seconds
    }

    {:reply, :ok, next}
  end

  def handle_call(:mark_connected, _from, state) do
    next = %{
      state
      | state: :connected,
        state_reason: nil,
        updated_at: System.system_time(:second)
    }

    {:reply, :ok, next}
  end

  def handle_call({:close, reason}, _from, state) do
    _ = StreamBus.unsubscribe(state.camera_id)
    _ = WebRTCPeer.close(state.pc)

    next = %{
      state
      | state: :closed,
        state_reason: reason,
        updated_at: System.system_time(:second)
    }

    {:reply, :ok, next}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:ice_candidate, candidate}}, state) do
    next_candidates =
      Map.update!(state.ice_candidates, :publisher, &[ICECandidate.to_json(candidate) | &1])

    {:noreply,
     %{state | ice_candidates: next_candidates, updated_at: System.system_time(:second)}}
  end

  def handle_info({:ex_webrtc, _from, {:connection_state_change, :connected}}, state) do
    :ok = StreamBus.subscribe(state.camera_id)

    {:noreply,
     %{state | state: :connected, state_reason: nil, updated_at: System.system_time(:second)}}
  end

  def handle_info({:ex_webrtc, _from, {:connection_state_change, conn_state}}, state) do
    {:noreply, %{state | state_reason: conn_state, updated_at: System.system_time(:second)}}
  end

  def handle_info({:pipeline_frame, camera_id, frame}, %{camera_id: camera_id} = state) do
    {:message_queue_len, qlen} = Process.info(self(), :message_queue_len)

    with true <- qlen < @max_mailbox_len,
         true <- state.state == :connected,
         track_id when is_integer(track_id) <- state.sender_track_id,
         payload when is_binary(payload) <- Map.get(frame, :payload) do
      packet =
        Packet.new(payload,
          sequence_number: Map.get(frame, :sequence_number, 0),
          timestamp: Map.get(frame, :timestamp, 0)
        )

      _ = WebRTCPeer.send_rtp(state.pc, track_id, packet)
      {:noreply, %{state | updated_at: System.system_time(:second)}}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp ensure_sender_track(%{sender_track_id: track_id} = state) when is_integer(track_id),
    do: {:ok, state}

  defp ensure_sender_track(state) do
    track = MediaStreamTrack.new(:video)

    case WebRTCPeer.add_track(state.pc, track) do
      {:ok, _sender} -> {:ok, %{state | sender_track_id: track.id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_add_ice_candidate(pc, candidate) when is_map(candidate) do
    c = %ICECandidate{
      candidate: Map.get(candidate, "candidate") || Map.get(candidate, :candidate) || "",
      sdp_mid: Map.get(candidate, "sdpMid") || Map.get(candidate, :sdp_mid),
      sdp_m_line_index:
        Map.get(candidate, "sdpMLineIndex") || Map.get(candidate, :sdp_m_line_index),
      username_fragment:
        Map.get(candidate, "usernameFragment") || Map.get(candidate, :username_fragment)
    }

    WebRTCPeer.add_ice_candidate(pc, c)
  end

  defp maybe_add_ice_candidate(_pc, _candidate), do: :ok

  defp via(session_id), do: {:via, Registry, {NervesView.Streaming.Registry, session_id}}

  @impl true
  def terminate(_reason, state) do
    _ = StreamBus.unsubscribe(state.camera_id)
    _ = WebRTCPeer.close(state.pc)
    :ok
  end
end
