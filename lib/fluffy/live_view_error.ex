defmodule Fluffy.LiveViewError do
  @moduledoc false

  defexception [:reason, :message]

  @impl true
  def exception(options) do
    reason = Keyword.fetch!(options, :reason)

    %__MODULE__{
      reason: reason,
      message: "LiveView became unavailable while waiting: #{inspect(reason)}"
    }
  end
end
