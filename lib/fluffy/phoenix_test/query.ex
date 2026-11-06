defmodule Fluffy.PhoenixTest.Query do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Driver
  alias Fluffy.Session

  def matches?(session, locator) do
    matches?(Session.page_state(session), Session.context(session), locator)
  end

  defp matches?(%Driver.Static.State{client_dom: dom}, _context, locator), do: ClientDOM.resolve(dom, locator) != []

  defp matches?(%Driver.Live.State{client_dom: dom}, _context, locator), do: ClientDOM.resolve(dom, locator) != []

  defp matches?(%Driver.Playwright.State{frame: frame}, _context, locator) do
    # Probe presence only. The selected click retains native waiting and strictness.
    case frame |> Fluffy.Locator.Playwright.locator(locator) |> PlaywrightEx.Locator.count() do
      {:ok, count} ->
        count > 0

      {:error, cause} ->
        raise Fluffy.OperationError,
          backend: :playwright,
          driver: :playwright,
          operation: :click_link,
          locator: locator,
          cause: cause
    end
  end
end
