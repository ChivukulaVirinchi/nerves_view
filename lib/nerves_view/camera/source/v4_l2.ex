defmodule NervesView.Camera.Source.V4L2 do
  @moduledoc false

  @behaviour NervesView.Camera.Source

  @impl true
  def source_type, do: :v4l2

  @impl true
  def normalize(attrs) do
    case Map.get(attrs, :device_path) do
      path when is_binary(path) ->
        if String.starts_with?(path, "/dev/video") do
          {:ok,
           attrs
           |> Map.put(:source_type, :v4l2)
           |> Map.put_new(:capture_backend, :v4l2)}
        else
          {:error, :invalid_device_path}
        end

      _ ->
        {:error, :invalid_device_path}
    end
  end
end
