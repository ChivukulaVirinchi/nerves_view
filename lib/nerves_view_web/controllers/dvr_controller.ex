defmodule NervesViewWeb.DVRController do
  @moduledoc """
  API endpoints for DVR timeline playback — serves on-the-fly HLS playlists
  and segment files for any point in the retention window.
  """

  use NervesViewWeb, :controller

  alias NervesView.DVR.{PlaylistBuilder, SegmentIndex}
  alias NervesView.Security.RateLimiter

  @doc "GET /api/dvr/:camera_id/playlist.m3u8?from=<unix_ts>"
  def playlist(conn, %{"camera_id" => camera_id} = params) do
    with :ok <- rate_limit(conn, "playlist", max_attempts: 60, window_seconds: 60) do
      from_ts = parse_int(params["from"], System.system_time(:second) - 300)
      to_ts = parse_int(params["to"], System.system_time(:second) + 60)

      segments = SegmentIndex.segments_for(camera_id, from_ts, to_ts)

      if segments == [] do
        conn
        |> put_status(:not_found)
        |> json(%{error: "no_segments_in_range"})
      else
        body = PlaylistBuilder.build_vod(camera_id, segments)

        conn
        |> put_resp_content_type("application/x-mpegURL")
        |> put_resp_header("cache-control", "no-cache, no-store")
        |> send_resp(200, body)
      end
    else
      {:error, :rate_limited} -> rate_limited(conn)
    end
  end

  @doc "GET /api/dvr/:camera_id/segments/:filename"
  def segment(conn, %{"camera_id" => camera_id, "filename" => filename}) do
    with :ok <- rate_limit(conn, "segment", max_attempts: 300, window_seconds: 60) do
      unless Regex.match?(~r/^seg-\d+\.ts$/, filename) do
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_segment_name"})
      else
        recordings_path = Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")
        path = Path.join([recordings_path, camera_id, filename])

        if File.exists?(path) do
          conn
          |> put_resp_content_type("video/mp2t")
          |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
          |> send_file(200, path)
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "segment_not_found"})
        end
      end
    else
      {:error, :rate_limited} -> rate_limited(conn)
    end
  end

  @doc "GET /api/dvr/:camera_id/timeline"
  def timeline(conn, %{"camera_id" => camera_id}) do
    with :ok <- rate_limit(conn, "timeline", max_attempts: 60, window_seconds: 60) do
      case SegmentIndex.retention_window(camera_id) do
        nil ->
          json(conn, %{
            camera_id: camera_id,
            oldest_ts: nil,
            newest_ts: nil,
            segment_count: 0
          })

        {oldest, newest} ->
          segs = SegmentIndex.all_segments(camera_id)

          json(conn, %{
            camera_id: camera_id,
            oldest_ts: oldest,
            newest_ts: newest,
            segment_count: length(segs)
          })
      end
    else
      {:error, :rate_limited} -> rate_limited(conn)
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp rate_limit(conn, bucket, opts) do
    key = "dvr:#{bucket}:#{conn.remote_ip |> :inet.ntoa() |> to_string()}"
    RateLimiter.check(key, opts)
  end

  defp rate_limited(conn) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{error: "rate_limited"})
  end
end
