defmodule NervesView.Pipeline.MotionDetector do
  @moduledoc """
  Frame-diff based motion detector used until Evision integration lands.
  """

  @spec detect([number()], [number()], keyword()) :: {:ok, map()} | {:error, atom()}
  def detect(previous_frame, current_frame, opts \\ [])

  def detect(previous_frame, current_frame, opts)
      when is_list(previous_frame) and is_list(current_frame) do
    if length(previous_frame) != length(current_frame) or previous_frame == [] do
      {:error, :invalid_frames}
    else
      threshold = Keyword.get(opts, :threshold, 0.18)
      cooldown = Keyword.get(opts, :cooldown_seconds, 5)
      min_delta = Keyword.get(opts, :min_delta, 1)

      changed =
        Enum.zip(previous_frame, current_frame)
        |> Enum.count(fn {a, b} -> abs(a - b) >= min_delta end)

      score = changed / length(previous_frame)

      {:ok,
       %{
         motion?: score >= threshold,
         score: score,
         changed_pixels: changed,
         threshold: threshold,
         cooldown_seconds: cooldown
       }}
    end
  end

  def detect(_, _, _), do: {:error, :invalid_frames}
end
