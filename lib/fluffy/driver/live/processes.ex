defmodule Fluffy.Driver.Live.Processes do
  @moduledoc false

  # The processes of a LiveView page that the session runtime stops with the session: the
  # view, its LiveViewTest client proxy and upload clients.

  # How long one may take to stop before it is killed: OTP's default shutdown of a worker.
  @stop_timeout 5_000

  def register(runtime, kind, pid) do
    Fluffy.SessionRuntime.register(runtime, {kind, pid}, fn -> stop(pid, :shutdown) end)
  end

  def release(runtime, kind, pid), do: Fluffy.SessionRuntime.release(runtime, {kind, pid})

  def stop(pid, reason) do
    if Process.alive?(pid) do
      reference = Process.monitor(pid)

      try do
        request_stop(pid, @stop_timeout, reason)
      catch
        :exit, _reason -> Process.exit(pid, :kill)
      end

      receive do
        {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
      after
        @stop_timeout ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
          end
      end
    end

    :ok
  end

  # Replacing a document stops its linked processes normally in the caller;
  # runtime teardown sends shutdown from the resource owner.
  defp request_stop(pid, timeout, :normal) do
    Process.unlink(pid)
    GenServer.stop(pid, :normal, timeout)
  end

  defp request_stop(pid, _timeout, :shutdown), do: Process.exit(pid, :shutdown)
end
