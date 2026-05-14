defmodule NervesView.CameraParams do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:id, :string)
    field(:name, :string)
    field(:device_path, :string, default: "/dev/video0")
    field(:source_type, :string, default: "libcamera")
  end

  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:id, :name, :device_path, :source_type])
    |> validate_required([:id, :name, :device_path])
    |> validate_format(:id, ~r/^[a-z0-9\-]+$/,
      message: "lowercase letters, numbers, hyphens only"
    )
    |> validate_length(:id, min: 2)
    |> validate_length(:name, min: 2)
    |> validate_inclusion(:source_type, ["libcamera", "rtsp"])
    |> validate_source_path()
  end

  defp validate_source_path(changeset) do
    source_type = get_field(changeset, :source_type)

    validate_change(changeset, :device_path, fn :device_path, path ->
      cond do
        source_type == "libcamera" and not String.starts_with?(path, "/dev/") ->
          [device_path: "must start with /dev/"]

        source_type == "rtsp" and not String.starts_with?(path, "rtsp://") ->
          [device_path: "must start with rtsp://"]

        true ->
          []
      end
    end)
  end
end
