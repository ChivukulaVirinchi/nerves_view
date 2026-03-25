defmodule NervesViewWeb.RecordingController do
  use NervesViewWeb, :controller

  def playlist(conn, %{"id" => id}) do
    case Enum.find(NervesView.list_recordings(), &(&1.id == id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      rec ->
        with {:ok, body} <- File.read(rec.playlist_path) do
          body =
            Enum.reduce(Map.get(rec, :segment_paths, []), body, fn segment_path, acc ->
              String.replace(
                acc,
                Path.basename(segment_path),
                segment_url(id, Path.basename(segment_path))
              )
            end)

          conn
          |> put_resp_content_type("application/x-mpegURL")
          |> send_resp(200, body)
        else
          _ ->
            conn
            |> put_status(:not_found)
            |> text("playlist not found")
        end
    end
  end

  def segment(conn, %{"id" => id, "segment" => segment}) do
    case Enum.find(NervesView.list_recordings(), &(&1.id == id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      rec ->
        case Enum.find(Map.get(rec, :segment_paths, []), &(Path.basename(&1) == segment)) do
          nil ->
            conn
            |> put_status(:not_found)
            |> text("segment not found")

          segment_path ->
            conn
            |> put_resp_content_type("video/mp2t")
            |> send_file(200, segment_path)
        end
    end
  end

  defp segment_url(recording_id, segment_file),
    do: "/recordings/#{recording_id}/segments/#{segment_file}"
end
