defmodule Fluffy.Backend.Contract do
  @moduledoc false

  alias Fluffy.Internal.Navigation
  alias Fluffy.Page
  alias Fluffy.Session

  @callback start_session(keyword()) :: Session.t()
  @callback new_page(Session.t()) :: Page.t()
  @callback history(Session.t(), :go_back | :go_forward, keyword()) :: Session.t()
  @callback visit(Session.t(), String.t()) :: Session.t()
  @callback reload(Session.t(), keyword()) :: Session.t()
  @callback navigate(Session.t(), Navigation.t()) :: Session.t()
  @callback close_page(Session.t(), Page.t()) :: Session.t()
  @callback event_source(Session.t(), atom(), :page | :context) :: :context | reference()
  @callback subscribe_event(Session.t(), atom(), :context | reference(), pid()) ::
              {(term() -> {:ok, term()} | {:error, String.t()} | :ignore), (-> :ok)}
  @callback absolute_url(Session.t(), String.t()) :: String.t()
  @callback base_url(Session.t()) :: String.t()

  # The session's cookies, as Playwright's `browserContext` cookie methods.
  @callback add_cookies(Session.t(), [map()]) :: Session.t()
  @callback cookies(Session.t(), [String.t()]) :: [map()]
  @callback clear_cookies(Session.t(), keyword() | map()) :: Session.t()

  # Browser pages and history, which `Fluffy.Playwright` gates to a Playwright session.
  @optional_callbacks new_page: 1, history: 3, close_page: 2

  # A navigation a driver reports; the Playwright driver adopts what the browser did itself.
  @optional_callbacks navigate: 2

  # Metadata and document identity belong to the backend that owns the page.
  @callback page_snapshot(term(), Page.State.t()) :: Page.State.t()
  @callback commit_page(Page.State.t(), atom(), term(), String.t() | nil, keyword()) :: Page.State.t()

  # Normalize backend page identities and events before they enter the runtime.
  @type page_registration :: {Page.State.t(), term() | nil, term() | nil}
  @callback prepare_page(term(), Page.State.t()) :: {:ok, page_registration()} | {:error, String.t()}
  # Called only for the first registration of an open page.
  @callback subscribe_page(term(), Page.State.t(), pid()) :: :ok | {:error, String.t()}
  @callback runtime_event(term(), term()) ::
              {:page_opened, page_registration()}
              | {:page_closed, term()}
              | :closed
              | :ignore
end
