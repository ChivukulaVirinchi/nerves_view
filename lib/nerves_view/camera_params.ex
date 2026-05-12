defmodule NervesView.CameraParams do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, :string
    field :name, :string
    field :device_path, :string, default: "/dev/video0"
    field :source_type, :string, default: "libcamera"
  end

  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:id, :name, :device_path, :source_type])
    |> validate_required([:id, :name, :device_path])
    |> validate_format(:id, ~r/^[a-z0-9\-]+$/, message: "lowercase letters, numbers, hyphens only")
    |> validate_length(:id, min: 2)
    |> validate_length(:name, min: 2)
    |> validate_format(:device_path, ~r/^\/dev\//, message: "must start with /dev/")
  end
end
