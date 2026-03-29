defmodule NervesView.Camera.Producer.RTSP do
  @moduledoc "RTSP camera producer — not yet implemented."

  use GenServer

  @behaviour NervesView.Camera.Producer

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(_opts) do
    {:stop, :not_implemented}
  end
end
