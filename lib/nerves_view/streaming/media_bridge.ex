defmodule NervesView.Streaming.MediaBridge do
  @moduledoc false

  @spec offer_sdp(String.t()) :: String.t()
  def offer_sdp(camera_id) when is_binary(camera_id) do
    "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=NervesView-#{camera_id}\r\nt=0 0\r\na=group:BUNDLE 0\r\na=msid-semantic: WMS\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\nc=IN IP4 0.0.0.0\r\na=rtpmap:96 H264/90000\r\na=recvonly\r\n"
  end
end
