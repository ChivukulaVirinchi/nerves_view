defmodule NervesView.Camera.ProducerTest do
  use ExUnit.Case, async: true

  alias NervesView.Camera.Producer

  test "resolves producer modules by source type" do
    assert Producer.module_for(:libcamera) == NervesView.Camera.Producer.Libcamera
    assert Producer.module_for(:rtsp) == NervesView.Camera.Producer.RTSP
    assert Producer.module_for(:synthetic) == NervesView.Camera.Producer.Synthetic
  end

  test "raises on unsupported source type" do
    assert_raise RuntimeError, ~r/Unsupported/, fn ->
      Producer.module_for(:v4l2)
    end
  end
end
