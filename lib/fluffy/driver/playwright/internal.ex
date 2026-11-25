defmodule Fluffy.Driver.Playwright.Internal do
  @moduledoc false

  # Fluffy's own Playwright calls (document probes, LiveView waits, presence checks) are
  # internal calls, as upstream's helpers make theirs (`_wrapApiCall(..., { internal: true })`):
  # the trace records no action for them and takes no snapshots, and Playwright Test no step.
  # They fail as they would otherwise, with the same error and call log.

  alias Playwright.Client.ChannelOwner

  @doc """
  Calls `module.function(target, ...)`, a facade call that returns `{:ok, value}` or
  `{:error, error}`, as an internal call.

  The outer zone is the call's, so the facade call's error lacks the API name
  `_wrapApiCall` puts in front of its message; it gets it here.
  """
  def call(module, function, [target | _] = arguments) do
    call = fn _api_zone -> apply(module, function, arguments) end

    case ChannelOwner._wrap_api_call(owner(target), call, %{internal: true}) do
      {:error, error} -> {:error, with_api_name(error, api_name(module, function))}
      result -> result
    end
  end

  # A locator's calls are its frame's, as in the client.
  defp owner(%Playwright.Locator{_frame: frame}), do: frame
  defp owner(channel_owner), do: channel_owner

  defp with_api_name(%{message: message} = error, api_name) when is_binary(message) do
    prefix = api_name <> ": "
    if String.starts_with?(message, prefix), do: error, else: %{error | message: prefix <> message}
  end

  defp with_api_name(error, _api_name), do: error

  # `Playwright.Frame.wait_for_function` -> "frame.waitForFunction", as the facade names it.
  defp api_name(module, function) do
    class = module |> Module.split() |> List.last()
    lower_first(class) <> "." <> lower_first(Macro.camelize("#{function}"))
  end

  defp lower_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
end
