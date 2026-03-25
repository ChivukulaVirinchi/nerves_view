defmodule NervesView.Pipeline.Runtime.Target do
  @moduledoc false

  @behaviour NervesView.Pipeline.Runtime

  @impl true
  def start_pipeline(descriptor, _opts) do
    start_ts = System.system_time(:second)

    case Map.get(descriptor, :source) do
      %{device_path: path} when is_binary(path) and path != "" ->
        {:ok,
         descriptor
         |> Map.put(:runtime, %{module: __MODULE__, source_path: path})
         |> Map.put(:status, :running)
         |> Map.put(:started_at, start_ts)
         |> Map.put(:last_frame_at, start_ts)}

      _ ->
        {:error, :invalid_source}
    end
  end

  @impl true
  def stop_pipeline(_descriptor), do: :ok

  @impl true
  def health(%{runtime: %{source_path: path}}) when is_binary(path) do
    %{healthy: true, source_path: path}
  end

  def health(_), do: %{healthy: false}
end
