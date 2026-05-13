defmodule NervesViewWeb.RecordingController do
  use NervesViewWeb, :controller

  alias NervesView.DVR.{PlaylistBuilder, SegmentIndex}

  @doc """
  Build a playlist for a recorded clip on the fly. A clip id is
  `clip-<camera_id>-<unix_started_at>`; the segments come from
  `SegmentIndex.get_clip/1`. Segment URLs point at `/api/dvr/...` (served by
  `DVRController.segment/2`), so we don't need a second per-recording route.
  """
  def playlist(conn, %{"id" => clip_id}) do
    case SegmentIndex.get_clip(clip_id) do
      {:ok, %{camera_id: camera_id, segments: segments}} ->
        body = PlaylistBuilder.build_vod(camera_id, segments)

        conn
        |> put_resp_content_type("application/x-mpegURL")
        |> put_resp_header("cache-control", "no-cache, no-store")
        |> send_resp(200, body)

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> text("not found")
    end
  end

  @doc "Backwards-compat: redirect old segment URLs to the DVR endpoint."
  def segment(conn, %{"id" => clip_id, "segment" => segment}) do
    case SegmentIndex.get_clip(clip_id) do
      {:ok, %{camera_id: camera_id}} ->
        redirect(conn, to: "/api/dvr/#{camera_id}/segments/#{segment}")

      {:error, _} ->
        conn |> put_status(:not_found) |> text("not found")
    end
  end

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
