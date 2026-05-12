defmodule NervesView.Streaming.PeerConnection do
  @moduledoc """
  Per-viewer signaling state for a camera stream session.
  """

  use GenServer

  require Logger

  alias ExRTP.Packet
  alias ExWebRTC.ICECandidate
  alias ExWebRTC.MediaStreamTrack
  alias ExWebRTC.PeerConnection, as: WebRTCPeer
  alias ExWebRTC.SessionDescription
  alias NervesView.Pipeline.StreamBus

  @type role :: :viewer | :publisher
  @timeout_seconds 45
  @max_mailbox_len 30
  # Max RTP payload size (leaving room for IP/UDP/RTP headers)
  @max_rtp_payload 1200

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def set_offer(session_id, sdp), do: GenServer.call(via(session_id), {:set_offer, sdp})
  def set_answer(session_id, sdp, opts \\ []),
    do: GenServer.call(via(session_id), {:set_answer, sdp, opts})

  def create_offer(session_id, fallback_sdp),
    do: GenServer.call(via(session_id), {:create_offer, fallback_sdp})

  def handle_browser_offer(session_id, offer_sdp, opts \\ []),
    do: GenServer.call(via(session_id), {:handle_browser_offer, offer_sdp, opts}, 10_000)

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
    ice_servers =
      Application.get_env(:nerves_view, :ice_servers, [%{urls: "stun:stun.l.google.com:19302"}])

    {:ok, pc} =
      WebRTCPeer.start(controlling_process: self(), video_codecs: [:h264], ice_servers: ice_servers)

    state = %{
      session_id: Keyword.fetch!(opts, :session_id),
      camera_id: Keyword.fetch!(opts, :camera_id),
      viewer_id: Keyword.fetch!(opts, :viewer_id),
      notify_pid: Keyword.get(opts, :notify_pid),
      offer_sdp: nil,
      answer_sdp: nil,
      ice_candidates: %{viewer: [], publisher: []},
      state: :new,
      state_reason: nil,
      timeout_at: now + @timeout_seconds,
      pc: pc,
      sender_track_id: nil,
      rtp_sequence: 0,
      rtp_timestamp: 0,
      pending_offer_from: nil,
      inserted_at: now,
      updated_at: now
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_offer, fallback_sdp}, from, state) do
    with {:ok, state} <- ensure_sender_track(state),
         {:ok, %SessionDescription{} = offer} <- WebRTCPeer.create_offer(state.pc),
         :ok <- WebRTCPeer.set_local_description(state.pc, offer) do
      # Don't reply yet — wait for ICE gathering to complete so the offer
      # includes all candidates. The reply happens in handle_info for
      # :ice_gathering_state_change or :ice_gather_timeout.
      Process.send_after(self(), :ice_gather_timeout, 3_000)
      now = System.system_time(:second)

      next = %{
        state
        | offer_sdp: offer.sdp,
          state: :connecting,
          updated_at: now,
          timeout_at: now + @timeout_seconds,
          pending_offer_from: from
      }

      {:noreply, next}
    else
      _ ->
        Logger.warning("WebRTC offer creation failed, using fallback SDP")
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

  def handle_call({:handle_browser_offer, offer_sdp, opts}, from, state) do
    # Browser-offers-server-answers flow: server is the controlled (answerer) side.
    # This avoids ICE controlling-agent nomination issues on resource-constrained devices.
    # Order matters: set_remote_description first, then add_track, then create_answer.
    # Strip the browser SDP to only keep the H.264 profile we support (42e01f,
    # packetization-mode=1) so the Pi Zero 2 W can parse it quickly.
    offer_sdp =
      offer_sdp
      |> resolve_mdns_in_sdp(Keyword.get(opts, :remote_ip))
      |> strip_unsupported_codecs()

    with :ok <-
           WebRTCPeer.set_remote_description(state.pc, %SessionDescription{
             type: :offer,
             sdp: offer_sdp
           }),
         {:ok, state} <- ensure_sender_track(state),
         {:ok, answer} <- WebRTCPeer.create_answer(state.pc),
         :ok <- WebRTCPeer.set_local_description(state.pc, answer) do
      # Wait for ICE gathering to include candidates in the answer SDP
      Process.send_after(self(), :ice_gather_timeout, 3_000)
      now = System.system_time(:second)

      next = %{
        state
        | offer_sdp: offer_sdp,
          answer_sdp: answer.sdp,
          state: :connecting,
          updated_at: now,
          timeout_at: now + @timeout_seconds,
          pending_offer_from: from
      }

      {:noreply, next}
    else
      error ->
        Logger.warning("WebRTC handle_browser_offer failed: #{inspect(error)}")
        {:reply, {:error, :negotiation_failed}, state}
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

  def handle_call({:set_answer, sdp, opts}, _from, state) do
    # Replace mDNS hostnames (*.local) in a=candidate lines with the
    # browser's real IP so ExICE can reach it without mDNS resolution.
    sdp = resolve_mdns_in_sdp(sdp, Keyword.get(opts, :remote_ip))

    candidates = sdp |> String.split("\r\n") |> Enum.filter(&String.starts_with?(&1, "a=candidate"))
    Logger.info("WebRTC answer has #{length(candidates)} candidates: #{inspect(candidates)}")
    result = WebRTCPeer.set_remote_description(state.pc, %SessionDescription{type: :answer, sdp: sdp})
    Logger.info("WebRTC set_answer result: #{inspect(result)}")
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
    Logger.info("WebRTC ICE #{role}: #{inspect(Map.get(candidate, "candidate", "?"))}")
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
    candidate_json = ICECandidate.to_json(candidate)
    next_candidates = Map.update!(state.ice_candidates, :publisher, &[candidate_json | &1])

    # Push server ICE candidate to the LiveView so it can forward to the browser
    if state.notify_pid do
      send(state.notify_pid, {:webrtc_ice_candidate, state.session_id, candidate_json})
    end

    {:noreply,
     %{state | ice_candidates: next_candidates, updated_at: System.system_time(:second)}}
  end

  def handle_info({:ex_webrtc, _from, {:connection_state_change, :connected}}, state) do
    Logger.info("WebRTC connected: camera=#{state.camera_id} viewer=#{state.viewer_id}")
    :ok = StreamBus.subscribe(state.camera_id)

    if state.notify_pid do
      send(state.notify_pid, {:webrtc_connected, state.session_id})
    end

    {:noreply,
     %{state | state: :connected, state_reason: nil, updated_at: System.system_time(:second)}}
  end

  def handle_info({:ex_webrtc, _from, {:connection_state_change, conn_state}}, state) do
    Logger.info("WebRTC #{conn_state}: camera=#{state.camera_id} viewer=#{state.viewer_id}")
    {:noreply, %{state | state_reason: conn_state, updated_at: System.system_time(:second)}}
  end

  def handle_info({:pipeline_frame, camera_id, frame}, %{camera_id: camera_id} = state) do
    {:message_queue_len, qlen} = Process.info(self(), :message_queue_len)

    nals =
      case Map.get(frame, :nals) do
        list when is_list(list) and list != [] -> list
        _ -> [Map.get(frame, :payload, <<>>)]
      end
      |> Enum.reject(&(&1 == <<>>))
      |> Enum.map(&rewrite_sps_profile_level/1)

    with true <- qlen < @max_mailbox_len,
         true <- state.state == :connected,
         track_id when is_integer(track_id) <- state.sender_track_id,
         [_ | _] <- nals do
      ts = Map.get(frame, :timestamp, state.rtp_timestamp)
      {seq, packets} = build_au_packets(nals, state.rtp_sequence, ts)

      Enum.each(packets, fn pkt ->
        _ = WebRTCPeer.send_rtp(state.pc, track_id, pkt)
      end)

      {:noreply,
       %{
         state
         | rtp_sequence: seq,
           rtp_timestamp: ts,
           updated_at: System.system_time(:second)
       }}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info({:ex_webrtc, _from, {:ice_gathering_state_change, :complete}}, state) do
    maybe_reply_offer(state)
  end

  def handle_info(:ice_gather_timeout, state) do
    maybe_reply_offer(state)
  end

  def handle_info(_, state), do: {:noreply, state}

  # Rewrite the profile_idc/constraint_flags/level_idc bytes of an SPS NAL to
  # match the `42e01f` (Constrained Baseline level 3.1) advertised in our SDP
  # answer. libcamera-vid on the Pi Zero 2 W cannot emit level <4.0 so its SPS
  # claims level_idc=40 even though 640x480@15fps is well within level 3.1's
  # capacity. Browsers strictly check that the SPS profile-level-id matches the
  # SDP; rewriting the three header bytes makes Chrome accept the stream.
  # NAL header: F(1) | NRI(2) | type(5). SPS is type=7, profile_idc=66 is baseline.
  defp rewrite_sps_profile_level(<<f::1, nri::2, 7::5, 66, _constraints, _level_idc, rest::binary>>) do
    <<f::1, nri::2, 7::5, 0x42, 0xE0, 0x1F, rest::binary>>
  end

  defp rewrite_sps_profile_level(nal), do: nal

  # H.264 RTP packetization (RFC 6184) — access-unit aware.
  #
  # Given a list of NALs that form one access unit, produce a list of ExRTP
  # packets sharing one timestamp. Marker bit is set ONLY on the final packet
  # of the AU (§5.1: "set to 1 in the last RTP packet of an access unit").
  #
  #   - Leading non-VCL NALs (SPS/PPS/SEI/AUD) that fit aggregated are bundled
  #     into one STAP-A packet (§5.7.1).
  #   - The VCL NAL (slice) is emitted as a single-NAL packet if it fits in
  #     the MTU, otherwise FU-A fragmented (§5.8).
  defp build_au_packets(nals, seq, timestamp) do
    {non_vcl, vcl} = Enum.split_with(nals, &non_vcl?/1)

    {seq, packets_rev} =
      {seq, []}
      |> emit_non_vcl(non_vcl, timestamp)
      |> emit_vcl(vcl, timestamp)

    packets = packets_rev |> Enum.reverse() |> set_marker_on_last()
    {seq, packets}
  end

  defp emit_non_vcl({seq, acc}, [], _ts), do: {seq, acc}

  defp emit_non_vcl({seq, acc}, [single], ts) do
    {next_seq, [pkt]} = single_nal_packet(single, seq, ts)
    {next_seq, [pkt | acc]}
  end

  defp emit_non_vcl({seq, acc}, nals, ts) do
    case build_stapa(nals) do
      {:ok, stapa_payload} when byte_size(stapa_payload) <= @max_rtp_payload ->
        next_seq = rem(seq + 1, 65_536)
        pkt = Packet.new(stapa_payload, sequence_number: seq, timestamp: ts, marker: false)
        {next_seq, [pkt | acc]}

      _ ->
        Enum.reduce(nals, {seq, acc}, fn nal, {cur_seq, acc_in} ->
          {next, [pkt]} = single_nal_packet(nal, cur_seq, ts)
          {next, [pkt | acc_in]}
        end)
    end
  end

  defp emit_vcl({seq, acc}, [], _ts), do: {seq, acc}

  defp emit_vcl({seq, acc}, nals, ts) do
    Enum.reduce(nals, {seq, acc}, fn nal, {cur_seq, acc_in} ->
      {next_seq, pkts} =
        if byte_size(nal) <= @max_rtp_payload do
          single_nal_packet(nal, cur_seq, ts)
        else
          fu_a_packets(nal, cur_seq, ts)
        end

      {next_seq, Enum.reduce(pkts, acc_in, &[&1 | &2])}
    end)
  end

  defp single_nal_packet(nal, seq, ts) do
    next_seq = rem(seq + 1, 65_536)
    pkt = Packet.new(nal, sequence_number: seq, timestamp: ts, marker: false)
    {next_seq, [pkt]}
  end

  defp fu_a_packets(nal, seq, ts) do
    <<_f::1, nri::2, nal_type::5, nal_body::binary>> = nal
    fu_indicator = <<0::1, nri::2, 28::5>>
    max_frag = @max_rtp_payload - 2
    fragments = chunk_binary(nal_body, max_frag)
    last_idx = length(fragments) - 1

    {final_seq, rev_pkts} =
      fragments
      |> Enum.with_index()
      |> Enum.reduce({seq, []}, fn {frag, idx}, {cur_seq, acc} ->
        s = if idx == 0, do: 1, else: 0
        e = if idx == last_idx, do: 1, else: 0
        fu_header = <<s::1, e::1, 0::1, nal_type::5>>
        payload = fu_indicator <> fu_header <> frag
        pkt = Packet.new(payload, sequence_number: cur_seq, timestamp: ts, marker: false)
        {rem(cur_seq + 1, 65_536), [pkt | acc]}
      end)

    {final_seq, Enum.reverse(rev_pkts)}
  end

  # STAP-A (RFC 6184 §5.7.1): payload type 24. Body is a concatenation of
  # <<size::16, nal::binary>> entries. The single-byte header uses NRI = max
  # NRI of the aggregated NALs and F = OR of forbidden_zero_bits.
  defp build_stapa(nals) do
    {max_nri, max_f} =
      Enum.reduce(nals, {0, 0}, fn <<f::1, nri::2, _::5, _::binary>>, {acc_nri, acc_f} ->
        {max(acc_nri, nri), max(acc_f, f)}
      end)

    header = <<max_f::1, max_nri::2, 24::5>>
    body = Enum.map_join(nals, fn nal -> <<byte_size(nal)::16, nal::binary>> end)
    {:ok, header <> body}
  end

  defp set_marker_on_last([]), do: []

  defp set_marker_on_last(packets) do
    {init, [last]} = Enum.split(packets, length(packets) - 1)
    init ++ [%{last | marker: true}]
  end

  defp non_vcl?(<<_f::1, _nri::2, nal_type::5, _::binary>>),
    do: nal_type in 6..9

  defp non_vcl?(_), do: false

  defp chunk_binary(bin, chunk_size) do
    chunk_binary(bin, chunk_size, [])
  end

  defp chunk_binary(<<>>, _chunk_size, acc), do: Enum.reverse(acc)

  defp chunk_binary(bin, chunk_size, acc) when byte_size(bin) <= chunk_size do
    Enum.reverse([bin | acc])
  end

  defp chunk_binary(bin, chunk_size, acc) do
    <<chunk::binary-size(chunk_size), rest::binary>> = bin
    chunk_binary(rest, chunk_size, [chunk | acc])
  end

  defp resolve_mdns_in_sdp(sdp, nil), do: sdp

  defp resolve_mdns_in_sdp(sdp, remote_ip) when is_binary(remote_ip) do
    Regex.replace(~r/[0-9a-f]{8,}-[0-9a-f-]+\.local/, sdp, remote_ip)
  end

  # Strip the browser's SDP to only keep the H.264 codec that matches
  # ExWebRTC's supported profile (42e01f, packetization-mode=1).
  # This dramatically reduces SDP size and parsing time on the Pi Zero 2 W.
  defp strip_unsupported_codecs(sdp) do
    lines = String.split(sdp, "\r\n")

    # Find the payload type for our preferred profile
    preferred_pt =
      Enum.find_value(lines, fn line ->
        if String.starts_with?(line, "a=fmtp:") and
             String.contains?(line, "profile-level-id=42e01f") and
             String.contains?(line, "packetization-mode=1") do
          line |> String.split(":") |> Enum.at(1) |> String.split(" ") |> hd()
        end
      end)

    if preferred_pt do
      lines
      |> Enum.map(fn line ->
        if String.starts_with?(line, "m=video") do
          # Rewrite m-line to only include the preferred payload type
          parts = String.split(line, " ")
          # m=video <port> <proto> <pt>
          Enum.take(parts, 3) |> Enum.join(" ") |> Kernel.<>(" #{preferred_pt}")
        else
          line
        end
      end)
      |> Enum.filter(fn line ->
        cond do
          # Keep all non-codec lines
          not Enum.any?(["a=rtpmap:", "a=rtcp-fb:", "a=fmtp:"], &String.starts_with?(line, &1)) ->
            true

          # Keep lines for the preferred payload type
          String.starts_with?(line, "a=rtpmap:#{preferred_pt} ") -> true
          String.starts_with?(line, "a=rtcp-fb:#{preferred_pt} ") -> true
          String.starts_with?(line, "a=fmtp:#{preferred_pt} ") -> true

          # Drop everything else
          true -> false
        end
      end)
      |> Enum.join("\r\n")
    else
      sdp
    end
  end

  defp maybe_reply_offer(%{pending_offer_from: nil} = state), do: {:noreply, state}

  defp maybe_reply_offer(%{pending_offer_from: from} = state) do
    # Get the local description which now includes gathered ICE candidates.
    # For the browser-offers-server-answers flow, this is the answer SDP.
    # For the server-offers flow, this is the offer SDP.
    sdp =
      case WebRTCPeer.get_local_description(state.pc) do
        %SessionDescription{sdp: sdp} -> sdp
        nil -> state.answer_sdp || state.offer_sdp
      end

    Logger.info("WebRTC SDP ready with ICE candidates for #{state.camera_id}")
    GenServer.reply(from, {:ok, sdp})
    {:noreply, %{state | pending_offer_from: nil}}
  end

  defp ensure_sender_track(%{sender_track_id: track_id} = state) when is_integer(track_id),
    do: {:ok, state}

  defp ensure_sender_track(state) do
    stream_id = MediaStreamTrack.generate_stream_id()
    track = MediaStreamTrack.new(:video, [stream_id])

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

    result = WebRTCPeer.add_ice_candidate(pc, c)
    Logger.info("WebRTC add_ice_candidate result: #{inspect(result)} candidate: #{c.candidate}")
    result
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
