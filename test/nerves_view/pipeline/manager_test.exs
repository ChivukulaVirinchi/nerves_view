defmodule NervesView.Pipeline.ManagerTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.Manager
  alias NervesView.Pipeline.TestSource

  setup do
    :ok = Manager.clear()
    :ok
  end

  test "starts and stops pipeline per camera" do
    assert {:ok, pipeline} = Manager.start_pipeline("cam-1", frame_count: 6, interval_ms: 1)
    assert pipeline.camera_id == "cam-1"
    assert pipeline.status == :running

    assert {:ok, status} = Manager.status("cam-1")
    frames = wait_for_frames(status.source_pid, 6)
    assert length(frames) == 6

    assert :ok = Manager.stop_pipeline("cam-1")
    assert {:error, :not_found} = Manager.status("cam-1")
  end

  defp wait_for_frames(pid, expected, attempts_left \\ 40)

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
