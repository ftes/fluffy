defmodule Fluffy.PageLifecycle do
  @moduledoc false

  alias Fluffy.Page
  alias Fluffy.Session

  @type release_reason :: :document_replaced | :page_closed
  @type releaser :: (Session.t(), Page.State.t(), release_reason() -> :ok)

  def replace_document(%Session{} = session, driver, state, url, metadata, releaser)
      when is_list(metadata) and is_function(releaser, 3) do
    page = Session.current_page(session)
    :ok = releaser.(session, page, :document_replaced)
    Session.commit_page(session, driver, state, url, metadata)
  end

  def close_page(%Session{} = session, page, releaser) when is_function(releaser, 3) do
    handle = Session.page_handle(session, page)
    record = Page.record(handle)
    :ok = releaser.(session, record, :page_closed)
    Fluffy.SessionRuntime.close_page(session.runtime, Page.id(handle))
    session
  end
end
