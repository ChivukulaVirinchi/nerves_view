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
    Process.sleep(20)
    frames = TestSource.fetch_frames(status.source_pid)
    assert length(frames) == 6

    assert :ok = Manager.stop_pipeline("cam-1")
    assert {:error, :not_found} = Manager.status("cam-1")
  end
end
