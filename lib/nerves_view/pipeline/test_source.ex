defmodule NervesView.Pipeline.TestSource do
  @moduledoc """
  Host-side frame generator that emits synthetic frame metadata.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec fetch_frames(pid()) :: [map()]
  def fetch_frames(pid), do: GenServer.call(pid, :fetch_frames)

  @impl true
  def init(opts) do
    count = Keyword.get(opts, :frame_count, 30)
    interval_ms = Keyword.get(opts, :interval_ms, 33)

    state = %{
      frame_count: count,
      interval_ms: interval_ms,
      emitted: [],
      index: 0,
      done?: false
    }

    Process.send_after(self(), :emit, 0)
    {:ok, state}
  end

  @impl true
  def handle_info(:emit, %{done?: true} = state), do: {:noreply, state}

  def handle_info(:emit, state) do
    frame = %{
      index: state.index,
      pts_ms: state.index * state.interval_ms,
      pattern: rem(state.index, 8)
    }

    next = %{state | emitted: [frame | state.emitted], index: state.index + 1}

    if next.index >= next.frame_count do
      {:noreply, %{next | done?: true}}
    else
      Process.send_after(self(), :emit, next.interval_ms)
      {:noreply, next}
    end
  end

  @impl true
  def handle_call(:fetch_frames, _from, state) do
    {:reply, Enum.reverse(state.emitted), state}
  end
end
