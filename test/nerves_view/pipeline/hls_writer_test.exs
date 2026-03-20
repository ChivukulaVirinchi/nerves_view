defmodule NervesView.Pipeline.HLSWriterTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.HLSWriter
  alias NervesView.Recording.Store

  setup do
    :ok = Store.clear()
    :ok
  end

  test "writes recording metadata with hls segments" do
    assert {:ok, rec} = HLSWriter.write("cam-1", now: 1_700_700_000, segments: 3)
    assert rec.playlist_path =~ ".m3u8"
    assert length(rec.segment_paths) == 3
    assert rec.size_bytes > 0
  end
end
