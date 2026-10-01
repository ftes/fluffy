defmodule Fluffy.PhoenixTest.Form do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.Locator
  alias Fluffy.Session

  def owner(session, locator) do
    case Session.current_driver(session) do
      :playwright -> browser_owner(session, locator)
      driver when driver in [:static, :live] -> structural_owner(session, locator)
    end
  end

  defp structural_owner(session, locator) do
    client_dom = Session.page_state(session).client_dom

    with [target] <- ClientDOM.targets(client_dom, locator),
         %{} = form <- DocumentIndex.form_owner(client_dom.index, target) do
      case List.keyfind(form.attributes, "id", 0) do
        {"id", id} when id != "" -> Locator.by_css("form[id=#{JSON.encode!(id)}]")
        _ -> Locator.by_css(DocumentIndex.target_by_id(client_dom.index, form.id).selector)
      end
    else
      _ -> nil
    end
  end

  defp browser_owner(session, locator) do
    context = Session.context(session)

    case PlaywrightEx.Locator.evaluate(Session.page_state(session).frame_id,
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
end
