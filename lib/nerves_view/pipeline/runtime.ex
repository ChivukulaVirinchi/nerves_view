defmodule NervesView.Pipeline.Runtime do
  @moduledoc "Behaviour for running camera pipeline backends."

  @callback start_pipeline(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stop_pipeline(map()) :: :ok
  @callback health(map()) :: map()
end
