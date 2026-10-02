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

  defp matches?(%Driver.Playwright.State{frame_id: frame_id}, context, locator) do
    # Probe presence only. The selected click retains native waiting and strictness.
    case PlaywrightEx.Frame.expect(frame_id,
           connection: context.connection,
           selector: Fluffy.Locator.Playwright.selector(locator),
           expression: "to.have.count",
           expected_number: 0,
           timeout: 1
         ) do
      {:ok, empty?} ->
        not empty?

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
