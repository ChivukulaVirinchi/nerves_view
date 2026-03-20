defmodule NervesView.Storage.ManagerTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.HLSWriter
  alias NervesView.Recording.Store
  alias NervesView.Storage.Manager

  setup do
    :ok = Store.clear()
    :ok
  end

  test "reports usage and enforces retention" do
    assert {:ok, _} = HLSWriter.write("cam-a", now: 1_700_701_000)
    assert {:ok, _} = HLSWriter.write("cam-a", now: 1_700_701_010)
    assert {:ok, _} = HLSWriter.write("cam-a", now: 1_700_701_020)

    usage = Manager.usage()
    assert usage.recording_count == 3
    assert usage.total_bytes > 0

    result = Manager.enforce_retention(max_count: 2)
    assert result.trimmed == 1
  end
end
