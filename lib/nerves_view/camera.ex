defmodule NervesView.Camera do
  @moduledoc "Camera metadata and validation helpers."

  @enforce_keys [:id, :name, :source_type, :status]
  defstruct [
    :id,
    :name,
    :source_type,
    :status,
    :device_path,
    :location
  ]

  @type source_type :: :libcamera | :v4l2 | :rtsp
  @type status :: :initializing | :streaming | :offline | :error

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          source_type: source_type(),
          status: status(),
          device_path: String.t() | nil,
          location: String.t() | nil
        }

  @valid_sources [:libcamera, :v4l2, :rtsp]
  @valid_statuses [:initializing, :streaming, :offline, :error]

  @spec new(map()) :: {:ok, t()} | {:error, :missing_required_fields | {:invalid_field, atom()}}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_source(Map.get(attrs, :source_type)),
         :ok <- validate_status(Map.get(attrs, :status)) do
      {:ok,
       struct(__MODULE__, %{
         id: Map.get(attrs, :id),
         name: Map.get(attrs, :name),
         source_type: Map.get(attrs, :source_type),
         status: Map.get(attrs, :status),
         device_path: Map.get(attrs, :device_path),
         location: Map.get(attrs, :location)
       })}
    end
  end

  defp validate_required(%{id: id, name: name, source_type: _src, status: _status})
       when is_binary(id) and is_binary(name),
       do: :ok

  defp validate_required(_attrs), do: {:error, :missing_required_fields}

  defp validate_source(source) when source in @valid_sources, do: :ok
  defp validate_source(_), do: {:error, {:invalid_field, :source_type}}

  defp validate_status(status) when status in @valid_statuses, do: :ok
  defp validate_status(_), do: {:error, {:invalid_field, :status}}
end
