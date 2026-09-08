defmodule Fluffy.PageLifecycle do
  @moduledoc false

  alias Fluffy.Page
  alias Fluffy.Session

  @type release_reason :: :document_replaced | :page_closed | :session_closed
  @type releaser :: (Session.t(), Page.t(), release_reason() -> :ok)

  def replace_document(%Session{} = session, driver, state, url, metadata, releaser)
      when is_list(metadata) and is_function(releaser, 3) do
    page = Session.current_page(session)
    :ok = releaser.(session, page, :document_replaced)
    Session.commit_page(session, driver, state, url, metadata)
  end

  def close_page(%Session{} = session, page_id, releaser) when is_function(releaser, 3) do
    page = Map.fetch!(session.pages, page_id)
    fallback = fallback_page!(session, page_id, page.opener)
    :ok = releaser.(session, page, :page_closed)
    Session.delete_page(session, page_id, fallback)
  end

  def release_all(%Session{} = session, releaser) when is_function(releaser, 3) do
    Enum.each(session.pages, fn {_page_id, page} ->
      :ok = releaser.(session, page, :session_closed)
    end)

    :ok
  end

  defp fallback_page!(session, closing_page, preferred) do
    available = Map.delete(session.pages, closing_page)

    cond do
      Map.has_key?(available, preferred) -> preferred
      map_size(available) > 0 -> available |> Map.keys() |> hd()
      true -> raise ArgumentError, "cannot close the only page in a session"
    end
  end
end
