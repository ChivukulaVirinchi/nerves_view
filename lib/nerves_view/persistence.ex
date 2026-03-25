defmodule NervesView.Persistence do
  @moduledoc false

  @default_dir "tmp/persistence"

  @spec load(String.t(), term()) :: term()
  def load(name, default) when is_binary(name) do
    path = path_for(name)

    case File.read(path) do
      {:ok, bin} ->
        :erlang.binary_to_term(bin)

      {:error, _reason} ->
        default
    end
  rescue
    _ -> default
  end

  @spec save(String.t(), term()) :: :ok | {:error, term()}
  def save(name, value) when is_binary(name) do
    path = path_for(name)
    :ok = File.mkdir_p(Path.dirname(path))
    File.write(path, :erlang.term_to_binary(value))
  end

  @spec path_for(String.t()) :: String.t()
  def path_for(name) when is_binary(name) do
    dir = Application.get_env(:nerves_view, :persistence_dir, @default_dir)
    Path.join(dir, name)
  end
end
