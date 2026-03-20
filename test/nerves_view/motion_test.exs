defmodule NervesView.MotionTest do
  use ExUnit.Case, async: true

  alias NervesView.Motion

  test "detects motion when change ratio exceeds threshold" do
    prev = [0, 0, 0, 0, 0, 0, 0, 0]
    curr = [0, 1, 0, 1, 0, 1, 0, 1]

    assert {:ok, result} = Motion.detect(prev, curr, threshold: 0.4)
    assert result.motion?
    assert result.change_ratio == 0.5
  end

  test "does not detect motion when below threshold" do
    prev = [0, 0, 0, 0]
    curr = [0, 0, 1, 0]

    assert {:ok, result} = Motion.detect(prev, curr, threshold: 0.5)
    refute result.motion?
    assert result.changed_pixels == 1
  end

  test "returns error for invalid frame data" do
    assert {:error, :invalid_frame_data} = Motion.detect([], [1], threshold: 0.2)
  end
end
