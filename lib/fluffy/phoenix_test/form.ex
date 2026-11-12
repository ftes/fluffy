defmodule Fluffy.PhoenixTest.Form do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Driver
  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.Locator
  alias Fluffy.Session

  def owner(session, locator) do
    state_owner(Session.page_state(session), locator)
  end

  defp state_owner(%Driver.Static.State{client_dom: client_dom}, locator), do: structural_owner(client_dom, locator)
  defp state_owner(%Driver.Live.State{client_dom: client_dom}, locator), do: structural_owner(client_dom, locator)
  defp state_owner(%Driver.External.State{}, _locator), do: nil

  # As a locator read, the action timeout bounds it.
  defp state_owner(%Driver.Playwright.State{frame: frame}, locator) do
    case frame
         |> Fluffy.Locator.Playwright.locator(locator)
         |> PlaywrightEx.Locator.evaluate(
           """
           element => {
             const form = element.form;
             if (!form) return null;
             if (form.id) return 'form#' + CSS.escape(form.id);
             const parts = [];
             for (let node = form; node; node = node.parentElement) {
               const index = node.parentElement ? Array.from(node.parentElement.children).indexOf(node) + 1 : 1;
               parts.unshift(node.localName + ':nth-child(' + index + ')');
             }
             return parts.join(' > ');
           }
           """,
           nil,
           timeout: Fluffy.Timeouts.playwright_operation!(:evaluate, [])
         ) do
      {:ok, :null} -> nil
      {:ok, selector} -> Locator.by_css(selector)
      {:error, _error} -> nil
    end
  end

  defp structural_owner(client_dom, locator) do
    with [target] <- ClientDOM.targets(client_dom, locator),
         %{} = form <- DocumentIndex.form_owner(ClientDOM.index(client_dom), target) do
      case List.keyfind(form.attributes, "id", 0) do
        {"id", id} when id != "" -> Locator.by_css("form[id=#{JSON.encode!(id)}]")
        _ -> Locator.by_css(DocumentIndex.target_by_id(ClientDOM.index(client_dom), form.id).selector)
      end
    else
      _ -> nil
    end
  end
end
