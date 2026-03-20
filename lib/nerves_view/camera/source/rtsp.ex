defmodule NervesView.Camera.Source.RTSP do
  @moduledoc false

  @behaviour NervesView.Camera.Source

  @impl true
  def source_type, do: :rtsp

  @impl true
  def normalize(attrs) do
    case Map.get(attrs, :device_path) do
      path when is_binary(path) ->
        if String.starts_with?(path, "rtsp://") do
          {:ok,
           attrs
           |> Map.put(:source_type, :rtsp)
           |> Map.put_new(:capture_backend, :rtsp)}
        else
          {:error, :invalid_rtsp_url}
        end

      _ ->
        {:error, :invalid_rtsp_url}
    end
  end
end
