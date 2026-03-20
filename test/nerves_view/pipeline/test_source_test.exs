defmodule NervesView.Pipeline.TestSourceTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.TestSource

  test "emits synthetic frames" do
    {:ok, pid} = TestSource.start_link(frame_count: 5, interval_ms: 1)
    Process.sleep(15)

    frames = TestSource.fetch_frames(pid)
    assert length(frames) == 5
    assert Enum.at(frames, 0).index == 0
    assert Enum.at(frames, 4).index == 4
  end
end
