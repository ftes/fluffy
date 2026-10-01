defmodule Fluffy.PhoenixTest.Form do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Driver
  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.Locator
  alias Fluffy.Session

  def owner(session, locator) do
    owner(Session.page_state(session), Session.context(session), locator)
  end

  defp owner(%Driver.Static.State{client_dom: client_dom}, _context, locator), do: structural_owner(client_dom, locator)
  defp owner(%Driver.Live.State{client_dom: client_dom}, _context, locator), do: structural_owner(client_dom, locator)

  defp owner(%Driver.Playwright.State{frame_id: frame_id}, context, locator) do
    case PlaywrightEx.Locator.evaluate(frame_id,
           selector: Fluffy.Locator.Playwright.selector(locator),
           connection: context.connection,
           timeout: context.timeout,
           is_function: true,
           expression: """
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
           """
         ) do
      {:ok, nil} -> nil
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
