defmodule NervesView.Storage.ManagerTest do
  use ExUnit.Case, async: false

  alias NervesView.Recording.Store
  alias NervesView.Storage.Manager

  setup do
    :ok = Store.clear()
    :ok
  end

  test "reports usage and enforces retention" do
    now = System.system_time(:second)

    for i <- 1..3 do
      {:ok, _} =
        Store.put(%{
          id: "rec-#{i}",
          camera_id: "cam-a",
          started_at: now + i * 10,
          ended_at: now + i * 10 + 9,
          mode: :continuous,
          path: "/fake/path/#{i}.m3u8",
          size_bytes: 1000 * i
        })
    end

    usage = Manager.usage()
    assert usage.recording_count == 3
    assert usage.total_bytes > 0

    result = Manager.enforce_retention(max_count: 2)
    assert result.trimmed == 1

    remaining = Store.list()
    assert length(remaining) == 2
  end
end
