defmodule NervesViewWeb.WebRTCSignaling do
  @moduledoc """
  Shared WebRTC signaling handlers for LiveViews.
  Browser creates offer, server answers. Bidirectional ICE via LiveView events.
  """

  require Logger

  alias ExWebRTC.{ICECandidate, MediaStreamTrack, SessionDescription}
  alias ExWebRTC.PeerConnection, as: PC
  alias NervesView.Pipeline.StreamBus

  @ice_servers Application.compile_env(:nerves_view, :ice_servers, [
                 %{urls: "stun:stun.l.google.com:19302"}
               ])

  def handle_webrtc_event(
        "webrtc:offer",
        %{"camera_id" => camera_id, "offer_sdp" => offer_sdp},
        socket
      ) do
    # Tear down any existing connection
    if old_pc = socket.assigns[:webrtc_pc] do
      try do
        PC.close(old_pc)
      catch
        _, _ -> :ok
      end
    end

    # Spawn a Task to avoid blocking the LiveView with slow GenServer calls
    lv_pid = self()

    Task.start(fn ->
      try do
        do_negotiate(camera_id, offer_sdp, lv_pid)
      rescue
        e -> Logger.error("WebRTC negotiation failed: #{inspect(e)}")
      end
    end)

    {:noreply, socket}
  end

  def handle_webrtc_event(
        "webrtc:ice",
        %{"candidate" => candidate},
        socket
      ) do
    pc = socket.assigns[:webrtc_pc]

    if pc && Process.alive?(pc) do
      candidate = resolve_mdns_candidate(candidate, socket)

      c = %ICECandidate{
        candidate: Map.get(candidate, "candidate", ""),
        sdp_mid: Map.get(candidate, "sdpMid"),
        sdp_m_line_index: Map.get(candidate, "sdpMLineIndex"),
        username_fragment: Map.get(candidate, "usernameFragment")
      }

      PC.add_ice_candidate(pc, c)
    end

    {:noreply, socket}
  end

  def handle_webrtc_event(_event, _params, socket), do: {:noreply, socket}

  # Negotiation result from the Task
  def handle_webrtc_info({:webrtc_negotiated, pc, track_id, camera_id, answer_sdp}, socket) do
    session_id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    {:noreply,
     socket
     |> Phoenix.Component.assign(:webrtc_pc, pc)
     |> Phoenix.Component.assign(:webrtc_track_id, track_id)
     |> Phoenix.Component.assign(:webrtc_camera_id, camera_id)
     |> Phoenix.LiveView.push_event("webrtc:answer", %{
       session_id: session_id,
       answer_sdp: answer_sdp
     })}
  end

  # Server ICE candidate → push to browser
  def handle_webrtc_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, socket) do
    {:noreply,
     Phoenix.LiveView.push_event(socket, "webrtc:ice", %{
       candidate: ICECandidate.to_json(candidate)
     })}
  end

  # Connection established — subscribe to camera frames
  def handle_webrtc_info({:ex_webrtc, _pc, {:connection_state_change, :connected}}, socket) do
    camera_id = socket.assigns[:webrtc_camera_id]
    Logger.info("WebRTC CONNECTED for camera #{camera_id}")

    if camera_id do
      StreamBus.subscribe(camera_id)
    end

    {:noreply, socket}
  end

  def handle_webrtc_info({:ex_webrtc, _pc, {:connection_state_change, state}}, socket) do
    Logger.info("WebRTC state: #{state}")
    {:noreply, socket}
  end

  # Forward video frames to WebRTC
  def handle_webrtc_info({:pipeline_frame, _camera_id, frame}, socket) do
    pc = socket.assigns[:webrtc_pc]
    track_id = socket.assigns[:webrtc_track_id]

    if pc && track_id && Process.alive?(pc) do
      payload = Map.get(frame, :payload, <<>>)

      if byte_size(payload) > 0 do
        seq = Map.get(frame, :sequence_number, 0)
        ts = Map.get(frame, :timestamp, 0)
        packet = ExRTP.Packet.new(payload, sequence_number: seq, timestamp: ts, marker: true)
        PC.send_rtp(pc, track_id, packet)
      end
    end

    {:noreply, socket}
  end

  # Catch-all for other ex_webrtc messages
  def handle_webrtc_info({:ex_webrtc, _, _}, socket), do: {:noreply, socket}
  def handle_webrtc_info(_msg, socket), do: {:noreply, socket}

  @doc "Call from mount/3 to store the browser's real IP for mDNS resolution."
  def assign_peer_ip(socket) do
    peer_ip =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: addr} -> addr |> :inet.ntoa() |> to_string()
        _ -> nil
      end

    Phoenix.Component.assign(socket, :peer_ip, peer_ip)
  end

  # ── Private ──

  defp do_negotiate(camera_id, offer_sdp, lv_pid) do
    {:ok, pc} =
      PC.start_link(
        controlling_process: lv_pid,
        video_codecs: [:h264],
        ice_servers: @ice_servers
      )

    offer = %SessionDescription{type: :offer, sdp: offer_sdp}
    :ok = PC.set_remote_description(pc, offer)

    stream_id = MediaStreamTrack.generate_stream_id()
    video_track = MediaStreamTrack.new(:video, [stream_id])
    {:ok, _sender} = PC.add_track(pc, video_track)

    {:ok, answer} = PC.create_answer(pc)
    :ok = PC.set_local_description(pc, answer)

    # Wait for ICE gathering
    gather_candidates(pc, 3_000)

    final_answer = PC.get_local_description(pc)

    send(lv_pid, {:webrtc_negotiated, pc, video_track.id, camera_id, final_answer.sdp})
  end

  defp gather_candidates(pc, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> :timeout
    end
  end

  defp resolve_mdns_candidate(%{"candidate" => sdp} = candidate, socket)
       when is_binary(sdp) do
    peer_ip = socket.assigns[:peer_ip]

    if peer_ip do
      resolved = Regex.replace(~r/[0-9a-f]{8,}-[0-9a-f-]+\.local/, sdp, peer_ip)
      Map.put(candidate, "candidate", resolved)
    else
      candidate
    end
  end

  defp resolve_mdns_candidate(candidate, _socket), do: candidate
end
