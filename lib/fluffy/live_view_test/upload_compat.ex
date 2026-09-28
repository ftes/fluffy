defmodule Fluffy.LiveViewTest.UploadCompat do
  @moduledoc false

  # Phoenix.LiveViewTest.file_input/4 is a macro because Phoenix.ChannelTest
  # needs the caller's compile-time @endpoint. Fluffy chooses an endpoint
  # from the runtime session instead, so this is the one contained compatibility
  # use of the entrypoints behind that public helper. Supported dependency
  # versions are declared in mix.exs.

  def file_input!(view, form_selector, name, entries, endpoint) do
    Phoenix.LiveViewTest.__file_input__(
      view,
      form_selector,
      name,
      entries,
      fn -> Phoenix.ChannelTest.__connect__(endpoint, Phoenix.LiveView.Socket, %{}, []) end
    )
  end

  def stop(upload) do
    if Process.alive?(upload.pid) do
      GenServer.stop(upload.pid, :normal)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end
end
