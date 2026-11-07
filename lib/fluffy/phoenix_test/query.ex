defmodule Fluffy.PhoenixTest.Query do
  @moduledoc false

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.ClientDOM
  alias Fluffy.Driver
  alias Fluffy.Session
  alias PlaywrightEx.TimeoutError

  def matches?(session, locator) do
    matches?(Session.page_state(session), Session.context(session), locator)
  end

  defp matches?(%Driver.Static.State{client_dom: dom}, _context, locator), do: ClientDOM.resolve(dom, locator) != []

  defp matches?(%Driver.Live.State{client_dom: dom}, _context, locator), do: ClientDOM.resolve(dom, locator) != []

  # `count` has no timeout of its own and waits while a script blocks the page.
  defp matches?(%Driver.Playwright.State{frame: frame}, context, locator) do
    # Probe presence only. The selected click retains native waiting and strictness.
    native = Fluffy.Locator.Playwright.locator(frame, locator)
    timeout = max(context.timeout, 1)

    case Bounded.within(timeout, fn -> PlaywrightEx.Locator.count(native) end) do
      {:ok, {:ok, count}} ->
        count > 0

      {:ok, {:error, cause}} ->
        raise_click_link!(locator, cause)

      :timeout ->
        raise_click_link!(locator, %TimeoutError{message: "Timeout #{timeout}ms exceeded while counting matches"})
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
