defmodule Fluffy.PhoenixTest.Query do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Driver
  alias Fluffy.Session

  def matches?(session, locator) do
    page_matches?(Session.page_state(session), locator)
  end

  defp page_matches?(%Driver.Static.State{client_dom: dom}, locator), do: ClientDOM.resolve(dom, locator) != []

  defp page_matches?(%Driver.Live.State{client_dom: dom}, locator), do: ClientDOM.resolve(dom, locator) != []

  # The click that follows raises for the missing document.
  defp page_matches?(%Driver.External.State{}, _locator), do: false

  # As in Playwright, `count` has no timeout and waits while a script blocks the page.
  defp page_matches?(%Driver.Playwright.State{frame: frame}, locator) do
    # Probe presence only. The selected click retains native waiting and strictness.
    native = Fluffy.Locator.Playwright.locator(frame, locator)

    case PlaywrightEx.Locator.count(native) do
      {:ok, count} -> count > 0
      {:error, cause} -> raise_click_link!(locator, cause)
    end
  end

  defp raise_click_link!(locator, cause) do
    raise Fluffy.OperationError,
      backend: :playwright,
      driver: :playwright,
      operation: :click_link,
      locator: locator,
      cause: cause
  end
end
