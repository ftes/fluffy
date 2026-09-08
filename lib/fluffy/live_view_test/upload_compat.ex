defmodule Fluffy.LiveViewTest.UploadCompat do
  @moduledoc false

  # Phoenix.LiveViewTest.file_input/4 is a macro because Phoenix.ChannelTest
  # needs the caller's compile-time @endpoint. Fluffy chooses an endpoint
  # from the runtime session instead, so this is the one contained compatibility
  # use of the entrypoints behind that public helper. It is pinned to the
  # phoenix_live_view version in mix.lock and must be reviewed on upgrade.
  @tested_live_view_version "1.2.11"

  def file_input!(view, form_selector, name, entries, endpoint) do
    ensure_compatible!()

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

  defp ensure_compatible! do
    actual_version = :phoenix_live_view |> Application.spec(:vsn) |> to_string()

    if !(actual_version == @tested_live_view_version and
           Code.ensure_loaded?(Phoenix.LiveViewTest) and
           Code.ensure_loaded?(Phoenix.ChannelTest) and
           function_exported?(Phoenix.LiveViewTest, :__file_input__, 5) and
           function_exported?(Phoenix.ChannelTest, :__connect__, 4)) do
      raise RuntimeError, """
      Fluffy managed LiveView uploads require Phoenix.LiveViewTest.__file_input__/5 and \
      Phoenix.ChannelTest.__connect__/4 from phoenix_live_view #{@tested_live_view_version}; \
      found phoenix_live_view #{actual_version}. Review Fluffy.LiveViewTest.UploadCompat before upgrading.
      """
    end
  end
end
