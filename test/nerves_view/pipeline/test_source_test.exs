defmodule NervesView.Pipeline.TestSourceTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.TestSource

  test "emits synthetic frames" do
    {:ok, pid} = TestSource.start_link(frame_count: 5, interval_ms: 1)
    frames = wait_for_frames(pid, 5)
    assert length(frames) == 5
    assert Enum.at(frames, 0).index == 0
    assert Enum.at(frames, 4).index == 4
  end

  defp wait_for_frames(pid, expected, attempts_left \\ 60)

  defp wait_for_frames(pid, expected, attempts_left) when attempts_left > 0 do
    frames = TestSource.fetch_frames(pid)

    if length(frames) >= expected do
      frames
    else
      Process.sleep(5)
      wait_for_frames(pid, expected, attempts_left - 1)
    end
  end

  defp wait_for_frames(pid, _expected, 0), do: TestSource.fetch_frames(pid)
end
