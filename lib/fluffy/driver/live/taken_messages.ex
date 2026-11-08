defmodule Fluffy.Driver.Live.TakenMessages do
  @moduledoc false

  # The view messages, such as a redirect, that the running Live action took
  # from the mailbox. The driver's `act` tracks them around the action. An
  # action that fails leaves its session on the page it started on, so it puts
  # them back for that session's next call to find. Outside an action, nothing
  # tracks them, so recording does nothing.

  @taken {__MODULE__, :taken}

  def track(action) when is_function(action, 0) do
    Process.put(@taken, [])

    try do
      action.()
    catch
      kind, reason ->
        @taken |> Process.get() |> Enum.reverse() |> Enum.each(&send(self(), &1))
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      Process.delete(@taken)
    end
  end

  def record(message) do
    case Process.get(@taken) do
      nil -> :ok
      taken -> Process.put(@taken, [message | taken])
    end

    :ok
  end
end
