defmodule NervesView.Camera.Config do
  @moduledoc """
  Per-camera color/encoding settings persisted alongside the camera registry.

  Defaults are tuned for IMX219 sensors with libcamera-vid:
    - AWB `auto` adapts to indoor / outdoor lighting
    - Saturation/contrast/sharpness at 1.0 (neutral)
    - Exposure `normal` (balanced)
  """

  defstruct awb_mode: :auto,
            saturation: 1.0,
            contrast: 1.0,
            sharpness: 1.0,
            exposure_mode: :normal

  @valid_awb_modes ~w(auto incandescent tungsten fluorescent indoor daylight cloudy)a
  @valid_exposure_modes ~w(normal short long)a

  @type t :: %__MODULE__{
          awb_mode: atom(),
          saturation: float(),
          contrast: float(),
          sharpness: float(),
          exposure_mode: atom()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) do
    {:ok,
     %__MODULE__{
       awb_mode: cast_awb(Map.get(attrs, "awb_mode") || Map.get(attrs, :awb_mode)),
       saturation: cast_float(Map.get(attrs, "saturation") || Map.get(attrs, :saturation), 1.0),
       contrast: cast_float(Map.get(attrs, "contrast") || Map.get(attrs, :contrast), 1.0),
       sharpness: cast_float(Map.get(attrs, "sharpness") || Map.get(attrs, :sharpness), 1.0),
       exposure_mode:
         cast_exposure(Map.get(attrs, "exposure_mode") || Map.get(attrs, :exposure_mode))
     }}
  end

  @spec from_opts(keyword()) :: t()
  def from_opts(opts) do
    awb = Keyword.get(opts, :awb, :auto)
    %__MODULE__{
      awb_mode: cast_awb(awb),
      saturation: Keyword.get(opts, :saturation, 1.0),
      contrast: Keyword.get(opts, :contrast, 1.0),
      sharpness: Keyword.get(opts, :sharpness, 1.0),
      exposure_mode: cast_exposure(Keyword.get(opts, :exposure, :normal))
    }
  end

  defp cast_awb(nil), do: :auto
  defp cast_awb(mode) when is_atom(mode), do: if(mode in @valid_awb_modes, do: mode, else: :auto)
  defp cast_awb(mode) when is_binary(mode), do: cast_awb(String.to_existing_atom(mode))

  defp cast_exposure(nil), do: :normal

  defp cast_exposure(mode) when is_atom(mode),
    do: if(mode in @valid_exposure_modes, do: mode, else: :normal)

  defp cast_exposure(mode) when is_binary(mode),
    do: cast_exposure(String.to_existing_atom(mode))

  defp cast_float(nil, default), do: default
  defp cast_float(v, _default) when is_float(v), do: v

  defp cast_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> Float.round(f, 1)
      :error -> default
    end
  end
end
