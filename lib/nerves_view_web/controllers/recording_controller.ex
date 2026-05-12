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

  # ── Live continuous recording HLS ──

  def live_playlist(conn, %{"camera_id" => camera_id}) do
    recordings_path = Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")
    path = Path.join([recordings_path, camera_id, "live.m3u8"])

    case File.read(path) do
      {:ok, body} ->
        # Rewrite segment filenames to use the live segment route
        rewritten =
          Regex.replace(~r/(seg-\d+\.ts)/, body, fn _, filename ->
            "/cameras/#{camera_id}/segments/#{filename}"
          end)

        conn
        |> put_resp_content_type("application/x-mpegURL")
        |> put_resp_header("cache-control", "no-cache, no-store")
        |> send_resp(200, rewritten)

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> text("no live playlist for this camera")
    end
  end

  def live_segment(conn, %{"camera_id" => camera_id, "segment" => segment}) do
    # Validate filename to prevent path traversal
    unless Regex.match?(~r/^seg-\d+\.ts$/, segment) do
      conn
      |> put_status(:bad_request)
      |> text("invalid segment name")
    else
      recordings_path = Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")
      path = Path.join([recordings_path, camera_id, segment])

      if File.exists?(path) do
        conn
        |> put_resp_content_type("video/mp2t")
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_file(200, path)
      else
        conn
        |> put_status(:not_found)
        |> text("segment not found")
      end
    end
  end
end
