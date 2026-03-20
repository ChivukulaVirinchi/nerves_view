defmodule NervesView.Motion do
  @moduledoc "Simple frame-diff motion detection helpers for phase-3."

  @spec detect([number()], [number()], keyword()) :: {:ok, map()} | {:error, atom()}
  def detect(previous_frame, current_frame, opts \\ [])

  def detect(previous_frame, current_frame, opts)
      when is_list(previous_frame) and is_list(current_frame) do
    threshold = Keyword.get(opts, :threshold, 0.08)

    with :ok <- validate_frames(previous_frame, current_frame),
         :ok <- validate_threshold(threshold) do
      deltas = Enum.zip_with(previous_frame, current_frame, fn prev, curr -> abs(curr - prev) end)
      changed = Enum.count(deltas, &(&1 > 0))
      ratio = changed / max(length(deltas), 1)

      {:ok,
       %{
         motion?: ratio >= threshold,
         change_ratio: ratio,
         changed_pixels: changed,
         total_pixels: length(deltas)
       }}
    end
  end

  def detect(_previous_frame, _current_frame, _opts), do: {:error, :invalid_frame_data}

  defp validate_frames(previous_frame, current_frame)
       when length(previous_frame) == length(current_frame) and previous_frame != [],
       do: :ok

  defp validate_frames(_previous_frame, _current_frame), do: {:error, :invalid_frame_data}

  defp validate_threshold(threshold)
       when is_number(threshold) and threshold > 0 and threshold <= 1,
       do: :ok

  defp validate_threshold(_threshold), do: {:error, :invalid_threshold}
end
