defmodule NervesViewWeb.RecordingController do
  use NervesViewWeb, :controller

  def playlist(conn, %{"id" => id}) do
    case Enum.find(NervesView.list_recordings(), &(&1.id == id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      rec ->
        lines =
          [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:6",
            "#EXT-X-MEDIA-SEQUENCE:0"
          ] ++
            Enum.flat_map(Map.get(rec, :segment_paths, []), fn segment ->
              ["#EXTINF:6.0,", segment]
            end) ++ ["#EXT-X-ENDLIST"]

        conn
        |> put_resp_content_type("application/x-mpegURL")
        |> send_resp(200, Enum.join(lines, "\n"))
    end
  end
end
