defmodule NervesView.Recording.StoreTest do
  use ExUnit.Case, async: false

  alias NervesView.Recording.Store

  setup do
    :ok = Store.clear()
    :ok
  end

  test "stores and lists recordings sorted by started_at desc" do
    now = System.system_time(:second)

    assert {:ok, _} =
             Store.put(%{
               id: "rec-1",
               camera_id: "cam-1",
               started_at: now - 10,
               ended_at: now - 1,
               mode: :continuous,
               path: "/data/r1.m3u8"
             })

    assert {:ok, _} =
             Store.put(%{
               id: "rec-2",
               camera_id: "cam-1",
               started_at: now,
               ended_at: now + 9,
               mode: :motion,
               path: "/data/r2.mp4"
             })

    assert [%{id: "rec-2"}, %{id: "rec-1"}] = Store.list(camera_id: "cam-1")
  end

  test "trim_by_count keeps only most recent recordings" do
    now = System.system_time(:second)

    for n <- 1..4 do
      assert {:ok, _} =
               Store.put(%{
                 id: "rec-#{n}",
                 camera_id: "cam-1",
                 started_at: now + n,
                 ended_at: now + n + 1,
                 mode: :continuous,
                 path: "/data/rec-#{n}.m3u8"
               })
    end

    assert 2 = Store.trim_by_count(2)
    assert [%{id: "rec-4"}, %{id: "rec-3"}] = Store.list()
  end

  test "rejects invalid recording payload" do
    assert {:error, :invalid_recording} = Store.put(%{id: "bad"})
  end
end
