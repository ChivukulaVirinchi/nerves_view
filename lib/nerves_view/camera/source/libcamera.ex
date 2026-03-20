defmodule NervesView.Camera.Source.Libcamera do
  @moduledoc false

  @behaviour NervesView.Camera.Source

  @impl true
  def source_type, do: :libcamera

  @impl true
  def normalize(attrs) do
    {:ok,
     attrs
     |> Map.put(:source_type, :libcamera)
     |> Map.put_new(:capture_backend, :libcamera)
     |> Map.put_new(:device_path, "/dev/video0")}
  end
end
