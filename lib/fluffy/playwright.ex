defmodule Fluffy.Playwright do
  @moduledoc """
  Playwright-only helpers for the active page.

  These functions intentionally live under `Fluffy.Playwright` because they
  depend on a real browser. Use them when behavior requires one; they are not
  implemented by the Static or LiveView drivers. The page clock lives in
  `Fluffy.Playwright.Clock`, page-wide input in `Fluffy.Playwright.Keyboard` and
  `Fluffy.Playwright.Mouse`.
  """
  @moduledoc groups: [
               "Lifecycle and navigation",
               "Actions",
               "Page inspection",
               "JavaScript",
               "Network",
               "Browser context",
               "Diagnostics and native access"
             ]

  alias Fluffy.Backend
  alias Fluffy.Backend.Playwright, as: PlaywrightBackend
  alias Fluffy.CapabilityError
  alias Fluffy.Driver.Playwright.Document
  alias Fluffy.Options
  alias Fluffy.Session
  alias Playwright.BrowserContext
  alias Playwright.WebStorage

  @route_schema NimbleOptions.new!(
                  times: [
                    type: :pos_integer,
                    doc: "How many requests the route handles before it expires. By default it never expires."
                  ]
                )

  @type route_option :: unquote(NimbleOptions.option_typespec(@route_schema))
  @typedoc "A `route/4` handler: as for `Playwright.BrowserContext.route/4`."
  @type route_handler ::
          (Playwright.Route.t() -> term()) | (Playwright.Route.t(), Playwright.Request.t() -> term())

  @type go_back_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:go_back)))
  @type go_forward_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:go_forward)))
  @type hover_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:hover)))
  @type drag_to_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:drag_to)))
  @type press_sequentially_option ::
          unquote(NimbleOptions.option_typespec(Options.action_schema(:press_sequentially)))
  @type dblclick_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:dblclick)))
  @type tap_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:tap)))
  @type select_text_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:select_text)))
  @type locator_screenshot_option ::
          unquote(NimbleOptions.option_typespec(Options.action_schema(:locator_screenshot)))
  @type page_screenshot_option ::
          unquote(NimbleOptions.option_typespec(Options.action_schema(:page_screenshot)))
  @type emulate_media_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:emulate_media)))
  @type wait_for_function_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:wait_for_function)))
  @type wait_for_load_state_option ::
          unquote(NimbleOptions.option_typespec(Options.action_schema(:wait_for_load_state)))
  @type bounding_box_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:bounding_box)))
  @type inner_text_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:inner_text)))
  @type aria_snapshot_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:aria_snapshot)))
  @type add_script_tag_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:add_script_tag)))
  @type add_style_tag_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:add_style_tag)))
  @type unroute_all_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:unroute_all)))
  @type locator_evaluate_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:locator_evaluate)))
  @type locator_wait_for_function_option ::
          unquote(NimbleOptions.option_typespec(Options.action_schema(:locator_wait_for_function)))
  @type drop_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:drop)))
  @type pdf_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:pdf)))
  @type content_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:content)))

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Returns a live handle to the selected page."
  @spec current_page(Session.t()) :: Fluffy.Page.t()
  def current_page(%Session{} = session) do
    CapabilityError.require_playwright!(session, :pages, :current_page)
    Session.current_driver(session)
    Session.handle(session)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Selects a page handle for this pipeline, without changing other session handles."
  @spec switch_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def switch_page(%Session{} = session, %Fluffy.Page{} = page) do
    CapabilityError.require_playwright!(session, :pages, :switch_page)
    Session.activate_page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Closes a page. Handles selecting it must explicitly switch to another page before continuing."
  @spec close_page(Session.t()) :: Session.t()
  def close_page(%Session{} = session) do
    CapabilityError.require_playwright!(session, :pages, :close_page)
    close_page(session, Session.handle(session))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Closes the given page handle, preserving the session's current-page selection."
  @spec close_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def close_page(%Session{} = session, %Fluffy.Page{} = page) do
    CapabilityError.require_playwright!(session, :pages, :close_page)
    Backend.close_page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Returns live handles for all open pages, including browser pages discovered without an event wait."
  @spec pages(Session.t()) :: [Fluffy.Page.t()]
  def pages(%Session{} = session) do
    CapabilityError.require_playwright!(session, :pages, :pages)
    Enum.map(Session.pages(session), fn {id, _page} -> Fluffy.Page.new(session.runtime, id) end)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Returns the handle of a `Playwright.Page` of the session's browser context, for
  `switch_page/2`. Events other than page events deliver Playwright's values, so this
  turns the page of a dialog or console message into one Fluffy can act on:

      dialog = await(pending)
      Playwright.Dialog.dismiss!(dialog)
      switch_page(session, page(session, Playwright.Dialog.page(dialog)))

  A page that has closed returns its closed handle. A page of another browser context
  raises `ArgumentError`. A dialog or console message may have no page, as in Playwright,
  and `nil` returns `nil`.
  """
  @spec page(Session.t(), Playwright.Page.t() | nil) :: Fluffy.Page.t() | nil
  def page(%Session{} = session, page) when is_struct(page, Playwright.Page) or is_nil(page) do
    CapabilityError.require_playwright!(session, :pages, :page)
    if page, do: PlaywrightBackend.Events.page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Creates a blank page in the session's browser context and returns its handle.

  The session keeps its current page selection. Use `switch_page/2` to select
  the new page. Pages share the context's cookies and storage.

      import Fluffy
      import Fluffy.Playwright

      main = current_page(session)
      other = Fluffy.Playwright.new_page(session)

      session
      |> switch_page(other)
      |> visit("/common-room")
      |> switch_page(main)
  """
  @spec new_page(Session.t()) :: Fluffy.Page.t()
  def new_page(%Session{} = session) do
    CapabilityError.require_playwright!(session, :pages, :new_page)
    Backend.new_page(session)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Navigates backward in browser history. Does nothing if there is no entry.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:go_back)}.

  #{NimbleOptions.docs(Options.action_schema(:go_back))}
  """
  @spec go_back(Session.t(), [go_back_option()]) :: Session.t()
  def go_back(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :browser_history, :go_back)
    Backend.history(session, :go_back, Options.validate_action!(:go_back, options))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Navigates forward in browser history. Does nothing if there is no entry.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:go_forward)}.

  #{NimbleOptions.docs(Options.action_schema(:go_forward))}
  """
  @spec go_forward(Session.t(), [go_forward_option()]) :: Session.t()
  def go_forward(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :browser_history, :go_forward)
    Backend.history(session, :go_forward, Options.validate_action!(:go_forward, options))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Waits for the active page to reach a load state and returns the session.

  `state` is `:load` (the default), `:domcontentloaded` or `:networkidle`, and the
  options may take its place. As in Playwright, `timeout:` defaults to the navigation
  timeout ([Timeouts](installation.md#timeouts)). Phoenix sessions raise `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:wait_for_load_state))}
  """
  @spec wait_for_load_state(Session.t()) :: Session.t()
  @spec wait_for_load_state(Session.t(), :load | :domcontentloaded | :networkidle | nil | [wait_for_load_state_option()]) ::
          Session.t()
  @spec wait_for_load_state(Session.t(), :load | :domcontentloaded | :networkidle | nil, [wait_for_load_state_option()]) ::
          Session.t()
  def wait_for_load_state(session, state \\ nil, options \\ [])

  def wait_for_load_state(%Session{} = session, options, []) when is_list(options),
    do: wait_for_load_state(session, nil, options)

  def wait_for_load_state(%Session{} = session, state, options),
    do: __call__(session, :wait, :pages, :wait_for_load_state, :page, [state], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Focuses the target in the active browser page. Accepts `timeout:`."
  @spec focus(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def focus(%Session{} = session, locator, options \\ []),
    do: __call__(session, :action, :focus, :focus, locator, [], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Blurs the target in the active browser page. Accepts `timeout:`."
  @spec blur(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def blur(%Session{} = session, locator, options \\ []),
    do: __call__(session, :action, :focus, :blur, locator, [], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Hovers over a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:hover)}.

  #{NimbleOptions.docs(Options.action_schema(:hover))}
  """
  @spec hover(Session.t(), Fluffy.Locator.t(), [hover_option()]) :: Session.t()
  def hover(%Session{} = session, locator, options \\ []),
    do: __call__(session, :action, :browser_pointer_typing, :hover, locator, [], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Drags the source locator onto the target locator in the same frame.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:drag_to)}.

  #{NimbleOptions.docs(Options.action_schema(:drag_to))}
  """
  @spec drag_to(Session.t(), Fluffy.Locator.t(), Fluffy.Locator.t(), [drag_to_option()]) :: Session.t()
  def drag_to(%Session{} = session, source, target, options \\ []),
    do: __call__(session, :action, :browser_pointer_typing, :drag_to, source, [target], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Types text character by character, emitting keyboard events.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:press_sequentially)}.

  #{NimbleOptions.docs(Options.action_schema(:press_sequentially))}
  """
  @spec press_sequentially(Session.t(), Fluffy.Locator.t(), String.t(), [press_sequentially_option()]) :: Session.t()
  def press_sequentially(%Session{} = session, locator, text, options \\ []) when is_binary(text),
    do: __call__(session, :action, :browser_pointer_typing, :press_sequentially, locator, [text], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Double-clicks a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:dblclick)}.

  #{NimbleOptions.docs(Options.action_schema(:dblclick))}
  """
  @spec dblclick(Session.t(), Fluffy.Locator.t(), [dblclick_option()]) :: Session.t()
  def dblclick(%Session{} = session, locator, options \\ []),
    do: __call__(session, :action, :browser_pointer_typing, :dblclick, locator, [], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Taps a locator. The session's browser context needs `has_touch: true`.

  `options` is required: a `tap/2` would make `Kernel.tap/2` ambiguous wherever this
  module is imported.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:tap)}.

  #{NimbleOptions.docs(Options.action_schema(:tap))}
  """
  @spec tap(Session.t(), Fluffy.Locator.t(), [tap_option()]) :: Session.t()
  def tap(%Session{} = session, locator, options),
    do: __call__(session, :action, :browser_pointer_typing, :tap, locator, [], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Dispatches a DOM event of `type` on a locator, skipping actionability checks.

  `event_init` is an optional map of event properties, such as `%{bubbles: false}`.

  As in Playwright, this does not wait for a navigation the event starts and can
  return before it commits, so the next action can race it. If the event navigates,
  `expect` something on the new page before the next action.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:dispatch_event))}
  """
  @spec dispatch_event(Session.t(), Fluffy.Locator.t(), String.t(), map() | nil, [Fluffy.action_option()]) :: Session.t()
  def dispatch_event(%Session{} = session, locator, type, event_init \\ nil, options \\ [])
      when is_binary(type) and (is_map(event_init) or is_nil(event_init)),
      do: __call__(session, :action, :browser_pointer_typing, :dispatch_event, locator, [type, event_init], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Selects the text of a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:select_text)}.

  #{NimbleOptions.docs(Options.action_schema(:select_text))}
  """
  @spec select_text(Session.t(), Fluffy.Locator.t(), [select_text_option()]) :: Session.t()
  def select_text(%Session{} = session, locator, options \\ []),
    do: __call__(session, :action, :browser_pointer_typing, :select_text, locator, [], options)

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Scrolls a locator into view unless it is already visible. Accepts `timeout:`."
  @spec scroll_into_view_if_needed(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def scroll_into_view_if_needed(%Session{} = session, locator, options \\ []),
    do: __call__(session, :action, :browser_pointer_typing, :scroll_into_view_if_needed, locator, [], options)

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the bounding box of a locator as `%{x: x, y: y, width: width, height: height}`,
  or `nil` if the element is not visible.

  Coordinates are in CSS pixels relative to the main frame's viewport. As in
  Playwright, `timeout:` (by default the action timeout) limits finding the element;
  reading its box has no timeout. Phoenix sessions raise
  `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:bounding_box))}
  """
  @spec bounding_box(Session.t(), Fluffy.Locator.t(), [bounding_box_option()]) ::
          %{x: number(), y: number(), width: number(), height: number()} | nil
  def bounding_box(%Session{} = session, %Fluffy.Locator{} = locator, options \\ []),
    do: __call__(session, :read, :computed_browser_semantics, :bounding_box, locator, [], options)

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the rendered text of one strict target, as Playwright's `locator.innerText()`.

  It is the browser's `innerText`, which depends on CSS: hidden text is left out, and
  blocks, `<br>` and table cells add line breaks and tabs. It waits and reads once as
  `Fluffy.text_content/3` does, which works on every driver. Phoenix sessions raise
  `Fluffy.CapabilityError`, as they render no CSS.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:inner_text))}
  """
  @spec inner_text(Session.t(), Fluffy.Locator.t(), [inner_text_option()]) :: String.t()
  def inner_text(%Session{} = session, %Fluffy.Locator{} = locator, options \\ []),
    do: __call__(session, :read, :computed_browser_semantics, :inner_text, locator, [], options)

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the rendered text of every element the locator matches, as Playwright's
  `locator.allInnerTexts()`.

  Like `Fluffy.all_text_contents/2`, it doesn't wait and returns `[]` if nothing matches.
  Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec all_inner_texts(Session.t(), Fluffy.Locator.t()) :: [String.t()]
  def all_inner_texts(%Session{} = session, %Fluffy.Locator{} = locator) do
    CapabilityError.require_playwright!(session, :computed_browser_semantics, :all_inner_texts)
    Backend.driver(session, :all_inner_texts, [locator])
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the ARIA snapshot of the active page, or of a locator, as YAML text.

  `timeout:` defaults to the action timeout ([Timeouts](installation.md#timeouts)). Phoenix
  sessions raise `Fluffy.CapabilityError`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:aria_snapshot)}.

  #{NimbleOptions.docs(Options.action_schema(:aria_snapshot))}
  """
  @spec aria_snapshot(Session.t(), Fluffy.Locator.t() | [aria_snapshot_option()], [aria_snapshot_option()]) :: String.t()
  def aria_snapshot(session, locator_or_options \\ [], options \\ [])

  def aria_snapshot(%Session{} = session, options, []) when is_list(options),
    do: __call__(session, :read, :computed_browser_semantics, {:aria_snapshot, :page_aria_snapshot}, :page, [], options)

  def aria_snapshot(%Session{} = session, %Fluffy.Locator{} = locator, options),
    do: __call__(session, :read, :computed_browser_semantics, :aria_snapshot, locator, [], options)

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns one `Fluffy.Locator` per element the locator matches right now, built with `Fluffy.Locator.nth/2`.

  As in Playwright, this does not wait for elements to match and returns `[]` if none
  do, and it is flaky on a list that is still changing: the elements can change
  between this call and the use of a locator. Wait first, such as with
  `Fluffy.Expect.to_have_count/3`. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec all(Session.t(), Fluffy.Locator.t()) :: [Fluffy.Locator.t()]
  def all(%Session{} = session, %Fluffy.Locator{} = locator) do
    CapabilityError.require_playwright!(session, :playwright_only_api, :all)
    count = unwrap_and_return(session, locator, &Playwright.Locator.count!/1)
    for index <- 0..(count - 1)//1, do: Fluffy.Locator.nth(locator, index)
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Drops files or data onto a locator and returns the session.

  `payload` has `files:`, as paths or `%{name: name, mimeType: type, buffer: content}`
  maps, `data:`, a map of MIME type to string, or both. As in Playwright, the call
  fails if the target's `dragover` listener does not call `preventDefault()`. Phoenix
  sessions raise `Fluffy.CapabilityError`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:drop)}.

  #{NimbleOptions.docs(Options.action_schema(:drop))}
  """
  @spec drop(Session.t(), Fluffy.Locator.t(), map(), [drop_option()]) :: Session.t()
  def drop(%Session{} = session, %Fluffy.Locator{} = locator, payload, options \\ []) when is_map(payload),
    do: __call__(session, :action, :browser_pointer_typing, :drop, locator, [payload], options)

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Returns the active page as a PDF binary, as Playwright's `page.pdf()`. With `path:`,
  it also writes the file.

      pdf = Fluffy.Playwright.pdf(session, path: "tmp/half-blood-prince.pdf")

  Browsers other than Chromium cannot generate one and raise. Phoenix sessions raise
  `Fluffy.CapabilityError`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:pdf)}.

  #{NimbleOptions.docs(Options.action_schema(:pdf))}
  """
  @spec pdf(Session.t(), [pdf_option()]) :: binary()
  def pdf(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :computed_browser_semantics, :pdf)
    native = Options.validate_action!(:pdf, options)
    page_read(session, :pdf, &Playwright.Page.pdf(&1, native))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Brings the active page to the front and returns the session."
  @spec bring_to_front(Session.t(), []) :: Session.t()
  def bring_to_front(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :pages, :bring_to_front)
    Options.validate_untimed!(options)
    page_action(session, :bring_to_front, &Playwright.Page.bring_to_front/1)
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the full HTML of the active page, including the doctype.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:content)}.

  #{NimbleOptions.docs(Options.action_schema(:content))}
  """
  @spec content(Session.t(), [content_option()]) :: String.t()
  def content(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :playwright_only_api, :content)
    native = Options.validate_action!(:content, options)
    page_read(session, :content, &Playwright.Page.content(&1, native))
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc "Returns the active page's title. To assert it, use `Fluffy.Expect.page_to_have_title/2`."
  @spec title(Session.t(), []) :: String.t()
  def title(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :playwright_only_api, :title)
    Options.validate_untimed!(options)
    page_read(session, :title, &Playwright.Page.title/1)
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the active page's `localStorage` for its current origin, as
  `[%{name: name, value: value}]`, like `storage_state/2` a read of the state as a
  value. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec local_storage(Session.t(), []) :: [%{name: String.t(), value: String.t()}]
  def local_storage(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :browser_context_state, :local_storage)
    Options.validate_untimed!(options)
    page_read(session, :local_storage, fn page -> WebStorage.items(Playwright.Page.local_storage(page)) end)
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the active page's `sessionStorage` for its current origin, as
  `local_storage/2` does. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec session_storage(Session.t(), []) :: [%{name: String.t(), value: String.t()}]
  def session_storage(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :browser_context_state, :session_storage)
    Options.validate_untimed!(options)
    page_read(session, :session_storage, fn page -> WebStorage.items(Playwright.Page.session_storage(page)) end)
  end

  defp page_read(session, operation, fun), do: Backend.driver(session, :page_read, [operation, fun])

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the active page's viewport as `%{width: width, height: height}`, or `nil`
  without a fixed viewport. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec viewport_size(Session.t()) :: %{width: integer(), height: integer()} | nil
  def viewport_size(%Session{} = session) do
    CapabilityError.require_playwright!(session, :browser_pointer_typing, :viewport_size)
    Playwright.Page.viewport_size(Session.page_state(session).page)
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Resizes the active page's viewport to `%{width: width, height: height}`.
  """
  @spec set_viewport_size(Session.t(), %{width: integer(), height: integer()}, []) :: Session.t()
  def set_viewport_size(%Session{} = session, %{width: _, height: _} = size, options \\ []) do
    CapabilityError.require_playwright!(session, :browser_pointer_typing, :set_viewport_size)
    Options.validate_untimed!(options)
    page_action(session, :set_viewport_size, &Playwright.Page.set_viewport_size(&1, size))
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Emulates media features on the active page, such as `color_scheme: :dark`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:emulate_media)}.

  #{NimbleOptions.docs(Options.action_schema(:emulate_media))}
  """
  @spec emulate_media(Session.t(), [emulate_media_option()]) :: Session.t()
  def emulate_media(%Session{} = session, options \\ []) do
    CapabilityError.require_playwright!(session, :browser_pointer_typing, :emulate_media)
    native = Options.validate_action!(:emulate_media, options)
    page_action(session, :emulate_media, &Playwright.Page.emulate_media(&1, native))
  end

  defp page_action(session, operation, fun), do: Backend.driver(session, :page_action, [operation, fun])

  @doc false
  # The path of a Playwright-only call that is one PlaywrightEx call on the active page
  # (`target` `:page`) or a locator: the capability gate, the options of its entry in
  # `Fluffy.Options.playwright_actions/0`, then the Playwright driver, which makes the call
  # with `arguments`. An `:action` returns the session, a `:read` the call's value, and a
  # `:wait` releases the handle it returns. `operation` is the public name, or
  # `{name, entry}` when its entry has another.
  def __call__(session, kind, capability, operation, target, arguments, options) when kind in [:action, :read, :wait] do
    {operation, native} = if is_atom(operation), do: {operation, operation}, else: operation
    CapabilityError.require_playwright!(session, capability, operation)
    options = Options.validate_action!(native, options)
    Backend.driver(session, :native_call, [kind, {operation, native}, target, arguments, options])
  end

  @doc false
  def __page_input__(session, device, operation, fun) do
    CapabilityError.require_playwright!(session, :browser_pointer_typing, operation)
    page_action(session, operation, &fun.(device.(&1)))
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Intercepts matching browser requests in the session's context, so popups and
  new pages are covered too, and returns the session. It is
  `Playwright.BrowserContext.route/4` on the session's context.

  `url` is what Playwright's `route` takes: a glob string, resolved against the
  session's `base_url:` (such as `"**/api/*"` or `"/api/potions"`), a regular
  expression, or a predicate over the URL as a `%URI{}`.

  `handler` receives the `Playwright.Route` (and its `Playwright.Request`, if it
  takes two arguments) and answers it with `Playwright.Route.fulfill!/2`,
  `continue!/2`, `abort!/2` or `fallback!/2`:

      import Fluffy.Playwright
      alias Playwright.Route

      session
      |> route("/api/potions", fn route -> Route.fulfill!(route, json: [%{name: "Felix Felicis"}]) end)
      |> visit("/potions")

  As in Playwright, the handler runs in a process of its own, with this call's
  process and its `$callers` in `$callers`. Call it from the test, or from a process
  with the test in `$callers`. Don't block in a route handler (`receive`,
  `Process.sleep`, `GenServer` calls, database or Phoenix work); hand off to a `Task`
  and fulfil from it. The `Task` inherits `$callers`, so the Ecto sandbox works there:

      route(session, "**/owl-post/**", fn route ->
        Task.start(fn -> Route.fulfill!(route, json: Owlery.letters_for("Harry")) end)
      end)

  When several routes match, the last registered wins; `fallback!/2` hands the
  request to the one registered before it.

  As in Playwright, a handler that raises fails the test and leaves its request
  pending, and a request never answered hangs until the action waiting for it times
  out. A handler may leave the route to another process, such as the test. The
  route lasts until `unroute/3`, `unroute_all/2` or the session's end. Like
  Playwright, routing disables the browser's HTTP cache. See
  [Routing requests](advanced-events.md#routing-requests).

  Phoenix sessions raise `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(@route_schema)}
  """
  @spec route(Session.t(), Fluffy.Page.url_expectation(), route_handler(), [route_option()]) :: Session.t()
  def route(%Session{} = session, url, handler, options \\ []) when is_function(handler) and is_list(options) do
    options = NimbleOptions.validate!(options, @route_schema)
    _disposable = session |> browser_context!(:routing, :route) |> BrowserContext.route!(url, handler, options)
    session
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Removes the routes registered for `url` by `route/4`, or only those of `handler`,
  and returns the session. It is `Playwright.BrowserContext.unroute/3`.

  `url` must equal the matcher given to `route/4`. As in Playwright, this does not
  wait for handlers already running; `unroute_all/2` with `behavior:` does.
  Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec unroute(Session.t(), Fluffy.Page.url_expectation(), route_handler() | nil) :: Session.t()
  def unroute(%Session{} = session, url, handler \\ nil) when is_nil(handler) or is_function(handler) do
    :ok = session |> browser_context!(:routing, :unroute) |> BrowserContext.unroute!(url, handler)
    session
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Removes every route on the browser context and returns the session. It is
  `Playwright.BrowserContext.unroute_all/2`.

  As in Playwright, this includes routes set up natively and HAR routers, and there
  is no timeout. `behavior: :ignore_errors` lets handlers still running fail
  nothing, such as at the end of a test. Phoenix sessions raise
  `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:unroute_all))}
  """
  @spec unroute_all(Session.t(), [unroute_all_option()]) :: Session.t()
  def unroute_all(%Session{} = session, options \\ []) do
    options = Options.validate_action!(:unroute_all, options)
    :ok = session |> browser_context!(:routing, :unroute_all) |> BrowserContext.unroute_all!(options)
    session
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Runs `fun` with the `Playwright.Locator` for `locator` and returns the reconciled session.

  Like `Fluffy.unwrap/2`, for native locator operations that have no Fluffy
  API. The locator resolves in the active page, through any frame locators, and
  is not checked for strictness until the callback uses it. The callback's
  return value is ignored, and a document it navigates is adopted.

      session
      |> Fluffy.Playwright.unwrap(by_role(:button, name: "Edit"), &Playwright.Locator.dblclick!/1)
      |> expect(to_be_visible(by_label("Title")))

  Prefer Playwright bang functions inside the callback when failure should
  stop the test. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec unwrap(Session.t(), Fluffy.Locator.t(), (Playwright.Locator.t() -> term())) :: Session.t()
  def unwrap(%Session{} = session, %Fluffy.Locator{} = locator, fun) when is_function(fun, 1) do
    CapabilityError.require_playwright!(session, :playwright_only_api, :unwrap)
    Backend.driver(session, :unwrap_locator, [locator, fun])
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Runs `fun` with the `Playwright.Locator` for `locator` and returns the callback's result.

  Like `unwrap/3`, including the reconcile after the callback, but for reads:

      text = Fluffy.Playwright.unwrap_and_return(session, by_css("#status"), &Playwright.Locator.text_content!/1)

  Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec unwrap_and_return(Session.t(), Fluffy.Locator.t(), (Playwright.Locator.t() -> result)) :: result
        when result: term()
  def unwrap_and_return(%Session{} = session, %Fluffy.Locator{} = locator, fun) when is_function(fun, 1) do
    CapabilityError.require_playwright!(session, :playwright_only_api, :unwrap_and_return)
    Backend.driver(session, :unwrap_and_return_locator, [locator, fun])
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Returns a screenshot of the active page as a binary, as Playwright's
  `page.screenshot()`. With `path:`, it also writes the file.

      png = Fluffy.Playwright.screenshot(session, path: "tmp/marauders-map.png", full_page: true)

  Pass a locator to capture one element, see `screenshot/3`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:page_screenshot)}.

  #{NimbleOptions.docs(Options.action_schema(:page_screenshot))}
  """
  @spec screenshot(Session.t(), [page_screenshot_option()]) :: binary()
  @spec screenshot(Session.t(), Fluffy.Locator.t()) :: binary()
  def screenshot(session, locator_or_options \\ [])

  def screenshot(%Session{} = session, options) when is_list(options),
    do: __call__(session, :read, :computed_browser_semantics, {:screenshot, :page_screenshot}, :page, [], options)

  def screenshot(session, %Fluffy.Locator{} = locator), do: screenshot(session, locator, [])

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Returns a screenshot of one element as a binary, as Playwright's
  `locator.screenshot()`. With `path:`, it also writes the file.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:locator_screenshot)}.

  #{NimbleOptions.docs(Options.action_schema(:locator_screenshot))}
  """
  @spec screenshot(Session.t(), Fluffy.Locator.t(), [locator_screenshot_option()]) :: binary()
  def screenshot(%Session{} = session, %Fluffy.Locator{} = locator, options) when is_list(options),
    do: __call__(session, :read, :computed_browser_semantics, {:screenshot, :locator_screenshot}, locator, [], options)

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Evaluates JavaScript in the active Playwright page and returns the value.

  This is `Playwright.Page.evaluate/3`: the expression is JavaScript source,
  either an expression or a function that receives `arg`. Promises are awaited,
  serializable values return as Elixir terms (objects as maps with string
  keys, JavaScript `null` as `:null`), and JavaScript failures raise. As in
  Playwright, it has no timeout and takes no options: an expression that never
  settles waits until the test times out.

  A non-empty keyword list in the place of `arg` is taken as options, and rejected,
  since no JavaScript value serializes to one; any other list, including `[]`, is an
  array.

  `evaluate` is a Playwright-only value query, so it returns the evaluated value
  rather than the Fluffy session. The session is unchanged, so keep using it:

      alias Fluffy.Playwright

      house = Playwright.evaluate(session, "localStorage.getItem('house')")
      assert house == "Ravenclaw"

      Playwright.evaluate(session, "selector => document.querySelector(selector).textContent", "#status")

  To assert on page state, prefer `Fluffy.Expect`, which retries; a value read
  here is checked once.

  Do not use this for JavaScript that owns a navigation, opens a page, starts a
  download, or installs a durable listener. Use the corresponding
  listener-before-action `Fluffy.wait_for/3` event API so lifecycle and
  cleanup remain owned by Fluffy. Reserve `Fluffy.unwrap/2` for uncommon
  page-local operations that have no first-class API.
  """
  @spec evaluate(Session.t(), String.t()) :: term()
  def evaluate(session, expression) when is_binary(expression), do: run_evaluate(session, nil, expression, nil, [])

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  With a string, like `evaluate/2` with `arg`. With a `Fluffy.Locator`,
  evaluates `expression` on its one element and returns the value: a function
  expression receives the element and then `arg`. As in Playwright, `timeout:`
  limits finding the element, not the evaluation.

      Playwright.evaluate(session, by_css("#status"), "element => element.textContent")

  ## Locator options

  Playwright-only options pass through to #{Options.native_reference(:locator_evaluate)}.

  #{NimbleOptions.docs(Options.action_schema(:locator_evaluate))}
  """
  @spec evaluate(Session.t(), String.t(), term()) :: term()
  @spec evaluate(Session.t(), Fluffy.Locator.t(), String.t()) :: term()
  def evaluate(session, %Fluffy.Locator{} = locator, expression) when is_binary(expression),
    do: run_evaluate(session, locator, expression, nil, [])

  def evaluate(session, expression, arg) when is_binary(expression), do: run_evaluate(session, nil, expression, arg, [])

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc "Like `evaluate/3`, with `arg` and no options on the page, or `arg` or options on a locator."
  @spec evaluate(Session.t(), String.t(), term(), []) :: term()
  @spec evaluate(Session.t(), Fluffy.Locator.t(), String.t(), term() | [locator_evaluate_option()]) :: term()
  def evaluate(session, %Fluffy.Locator{} = locator, expression, arg) when is_binary(expression),
    do: run_evaluate(session, locator, expression, arg, [])

  def evaluate(session, expression, arg, options) when is_binary(expression),
    do: run_evaluate(session, nil, expression, arg, options)

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc "Like `evaluate/4` on a locator, with both `arg` and options."
  @spec evaluate(Session.t(), Fluffy.Locator.t(), String.t(), term(), [locator_evaluate_option()]) :: term()
  def evaluate(session, %Fluffy.Locator{} = locator, expression, arg, options) when is_binary(expression),
    do: run_evaluate(session, locator, expression, arg, options)

  defp run_evaluate(session, target, expression, arg, options) do
    {arg, options} = arg_and_options(arg, options)
    evaluate_target(session, target, expression, arg, options)
  end

  # A non-empty keyword list in the place of `arg` is options; `[]` stays a JavaScript array.
  defp arg_and_options([_ | _] = arg, []), do: if(Keyword.keyword?(arg), do: {nil, arg}, else: {arg, []})
  defp arg_and_options(arg, options), do: {arg, options}

  defp evaluate_target(session, nil, expression, arg, options) do
    CapabilityError.require_playwright!(session, :javascript_evaluation, :evaluate)
    Options.validate_untimed!(options)

    case Playwright.Frame.evaluate(Session.page_state(session).frame, expression, arg) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  defp evaluate_target(session, %Fluffy.Locator{} = locator, expression, arg, options),
    do:
      __call__(
        session,
        :read,
        :javascript_evaluation,
        {:evaluate, :locator_evaluate},
        locator,
        [expression, arg],
        options
      )

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Evaluates `expression` on all elements of a locator and returns the value: a function
  expression receives the array of elements and then `arg`.

      count = Playwright.evaluate_all(session, by_css("li"), "items => items.length")

  Unlike `evaluate/3` on a locator, any number of elements may match, including none.
  As in Playwright, it has no timeout and takes no options; a non-empty keyword list
  in the place of `arg` is rejected as options. Phoenix sessions raise
  `Fluffy.CapabilityError`.
  """
  @spec evaluate_all(Session.t(), Fluffy.Locator.t(), String.t(), term()) :: term()
  @spec evaluate_all(Session.t(), Fluffy.Locator.t(), String.t(), term(), []) :: term()
  def evaluate_all(%Session{} = session, %Fluffy.Locator{} = locator, expression, arg \\ nil, options \\ [])
      when is_binary(expression) do
    CapabilityError.require_playwright!(session, :javascript_evaluation, :evaluate_all)
    {arg, options} = arg_and_options(arg, options)
    Options.validate_untimed!(options)
    Backend.driver(session, :evaluate_all, [locator, expression, arg])
  end

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Waits until a JavaScript expression returns a truthy value in the active page and returns the session.

  The expression is JavaScript source, either an expression or a function that
  receives `arg`, as in `evaluate/3`. It is re-evaluated until it is truthy, across
  navigations of the page; a navigation meanwhile is adopted. `timeout:` defaults to
  the action timeout ([Timeouts](installation.md#timeouts)):

      session
      |> Fluffy.Playwright.wait_for_function("window.editor?.ready === true")
      |> Fluffy.Playwright.wait_for_function("min => window.innerWidth > min", 800, timeout: 2_000)
      |> Fluffy.Playwright.wait_for_function("window.editor?.saved", timeout: 2_000)

  A non-empty keyword list in the place of `arg` is options, as in `evaluate/4`.
  Phoenix sessions raise `Fluffy.CapabilityError`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:wait_for_function)}.

  #{NimbleOptions.docs(Options.action_schema(:wait_for_function))}
  """
  @spec wait_for_function(Session.t(), String.t()) :: Session.t()
  def wait_for_function(%Session{} = session, expression) when is_binary(expression),
    do: run_wait_for_function(session, nil, expression, nil, [])

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  With a string, like `wait_for_function/2` with `arg` or options. With a
  `Fluffy.Locator`, waits until a function of the locator's element returns a truthy
  value and returns the session; the function receives the element and then `arg`.

      Playwright.wait_for_function(session, by_css("#status"), "element => element.dataset.ready === 'true'")

  ## Locator options

  Playwright-only options pass through to #{Options.native_reference(:locator_wait_for_function)}.

  #{NimbleOptions.docs(Options.action_schema(:locator_wait_for_function))}
  """
  @spec wait_for_function(Session.t(), String.t(), term() | [wait_for_function_option()]) :: Session.t()
  @spec wait_for_function(Session.t(), Fluffy.Locator.t(), String.t()) :: Session.t()
  def wait_for_function(%Session{} = session, %Fluffy.Locator{} = locator, expression) when is_binary(expression),
    do: run_wait_for_function(session, locator, expression, nil, [])

  def wait_for_function(%Session{} = session, expression, arg) when is_binary(expression),
    do: run_wait_for_function(session, nil, expression, arg, [])

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc "Like `wait_for_function/3`, with `arg` and options on the page, or `arg` or options on a locator."
  @spec wait_for_function(Session.t(), String.t(), term(), [wait_for_function_option()]) :: Session.t()
  @spec wait_for_function(Session.t(), Fluffy.Locator.t(), String.t(), term() | [locator_wait_for_function_option()]) ::
          Session.t()
  def wait_for_function(%Session{} = session, %Fluffy.Locator{} = locator, expression, arg) when is_binary(expression),
    do: run_wait_for_function(session, locator, expression, arg, [])

  def wait_for_function(%Session{} = session, expression, arg, options) when is_binary(expression),
    do: run_wait_for_function(session, nil, expression, arg, options)

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc "Like `wait_for_function/4` on a locator, with both `arg` and options."
  @spec wait_for_function(Session.t(), Fluffy.Locator.t(), String.t(), term(), [locator_wait_for_function_option()]) ::
          Session.t()
  def wait_for_function(%Session{} = session, %Fluffy.Locator{} = locator, expression, arg, options)
      when is_binary(expression), do: run_wait_for_function(session, locator, expression, arg, options)

  defp run_wait_for_function(session, target, expression, arg, options) do
    {arg, options} = arg_and_options(arg, options)
    wait_for_target(session, target, expression, arg, options)
  end

  defp wait_for_target(session, nil, expression, arg, options),
    do: __call__(session, :wait, :javascript_evaluation, :wait_for_function, :page, [expression, arg], options)

  defp wait_for_target(session, %Fluffy.Locator{} = locator, expression, arg, options) do
    operation = {:wait_for_function, :locator_wait_for_function}
    __call__(session, :action, :javascript_evaluation, operation, locator, [expression, arg], options)
  end

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Adds a script that runs in every document of the session's browser context before
  the document's own scripts, and returns the session.

  Each session owns one context, so popups and new pages are covered too. The script
  only affects documents loaded afterwards: add it before `visit/2`, or reload.

  `script` is JavaScript source, or `%{path: path}` or `%{content: source}`, which
  take no `arg`. With `arg`, source must be a function, which receives `arg`:

      session
      |> Fluffy.Playwright.add_init_script("name => { window.greeting = name }", "Harry")
      |> visit("/potions")

  Without `arg`, a string is evaluated as it stands, as in Playwright: a function
  expression such as `"() => { window.seeded = true }"` is evaluated but not called.
  Write statements instead, or call the function in the source.

  As in Playwright, it has no timeout. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec add_init_script(Session.t(), String.t() | map(), term()) :: Session.t()
  def add_init_script(session, script, arg \\ nil)

  def add_init_script(_session, script, arg) when is_map(script) and not is_nil(arg) do
    raise ArgumentError, "Fluffy.Playwright.add_init_script/3: a script map takes no arg, got: #{inspect(arg)}"
  end

  def add_init_script(session, script, arg),
    do: set_context!(session, :javascript_evaluation, :add_init_script, &BrowserContext.add_init_script(&1, script, arg))

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Adds a `<script>` tag to the active page's current document and returns the session.

  Give one of `url:`, `path:` or `content:`. The tag does not outlive the document; for
  every document, use `add_init_script/3`. Phoenix sessions raise `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:add_script_tag))}
  """
  @spec add_script_tag(Session.t(), [add_script_tag_option()]) :: Session.t()
  def add_script_tag(%Session{} = session, options) do
    CapabilityError.require_playwright!(session, :javascript_evaluation, :add_script_tag)
    add_tag(session, :add_script_tag, &Playwright.Page.add_script_tag/2, options)
  end

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Adds a `<style>` or `<link rel="stylesheet">` tag to the active page's current
  document and returns the session.

  Give one of `url:`, `path:` or `content:`. The tag does not outlive the document.
  Phoenix sessions raise `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:add_style_tag))}
  """
  @spec add_style_tag(Session.t(), [add_style_tag_option()]) :: Session.t()
  def add_style_tag(%Session{} = session, options) do
    CapabilityError.require_playwright!(session, :javascript_evaluation, :add_style_tag)
    add_tag(session, :add_style_tag, &Playwright.Page.add_style_tag/2, options)
  end

  defp add_tag(session, operation, add, options) do
    native = Options.validate_action!(operation, options)
    page_action(session, operation, &with({:ok, tag} <- add.(&1, native), do: Document.release(tag)))
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Returns the context's storage state for reuse as `browser_context: [storage_state: state]`.

  Accepts the options of `Playwright.BrowserContext.storage_state/2`, such as `path:` and `indexed_db:`.
  """
  @spec storage_state(Session.t(), BrowserContext.storage_state_options()) :: map()
  def storage_state(session, options \\ []) do
    session |> browser_context!(:browser_context_state, :storage_state) |> BrowserContext.storage_state!(options)
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Replaces the context's storage with `state`, a saved state from `storage_state/2`
  as a map or file path, and returns the session.

  As in Playwright, it clears the existing cookies, local storage, IndexedDB and other
  entries first. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec set_storage_state(Session.t(), String.t() | map()) :: Session.t()
  def set_storage_state(session, state) when is_binary(state) or is_map(state) do
    set_context!(session, :browser_context_state, :set_storage_state, &BrowserContext.set_storage_state(&1, state))
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Grants browser permissions, such as `"geolocation"`, and returns the session.

  Accepts `origin:` to limit them to one origin. See `Playwright.BrowserContext.grant_permissions/3`.
  """
  @spec grant_permissions(Session.t(), [String.t()], BrowserContext.grant_permissions_options()) :: Session.t()
  def grant_permissions(session, permissions, options \\ []) when is_list(permissions) do
    set_context!(
      session,
      :browser_context_setters,
      :grant_permissions,
      &BrowserContext.grant_permissions(&1, permissions, options)
    )
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc "Clears all granted browser permissions and returns the session."
  @spec clear_permissions(Session.t()) :: Session.t()
  def clear_permissions(session) do
    set_context!(session, :browser_context_setters, :clear_permissions, &BrowserContext.clear_permissions/1)
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Sets the geolocation and returns the session; `:null` clears it.

  Takes `%{latitude: latitude, longitude: longitude}` and optionally `:accuracy`.
  Pages also need the `"geolocation"` permission from `grant_permissions/3`.
  """
  @spec set_geolocation(Session.t(), :null | map()) :: Session.t()
  def set_geolocation(session, geolocation) do
    set_context!(session, :browser_context_setters, :set_geolocation, &BrowserContext.set_geolocation(&1, geolocation))
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc "Emulates the network being offline, or back online, and returns the session."
  @spec set_offline(Session.t(), boolean()) :: Session.t()
  def set_offline(session, offline) when is_boolean(offline) do
    set_context!(session, :browser_context_setters, :set_offline, &BrowserContext.set_offline(&1, offline))
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Sets HTTP authentication credentials and returns the session; `:null` clears them.

  Takes `%{username: username, password: password}` and optionally `:origin`, or
  a list of those for different origins. Browsers may cache credentials for an
  origin that has already authenticated.
  """
  @spec set_http_credentials(Session.t(), :null | map() | [map()]) :: Session.t()
  def set_http_credentials(session, credentials) do
    set_context!(
      session,
      :browser_context_setters,
      :set_http_credentials,
      &BrowserContext.set_http_credentials(&1, credentials)
    )
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Sets extra HTTP headers for every request of the session's browser context and
  returns the session.

  Each call replaces the headers of an earlier one, as in Playwright, but keeps those
  the session started with: its `extra_http_headers:`, else the test's (config, module or
  tag), and the Ecto sandbox header. A header of the same name overrides them. Phoenix sessions raise
  `Fluffy.CapabilityError`.
  """
  @spec set_extra_http_headers(Session.t(), %{optional(String.t()) => String.t()}) :: Session.t()
  def set_extra_http_headers(session, headers) when is_map(headers) do
    headers = Map.new(headers, fn {name, value} -> {String.downcase(to_string(name)), value} end)

    # Playwright replaces all of the context's headers, the sandbox's among them.
    set_context!(session, :browser_context_setters, :set_extra_http_headers, fn browser_context ->
      merged = Map.merge(Session.context(session).extra_http_headers, headers)
      BrowserContext.set_extra_http_headers(browser_context, merged)
    end)
  end

  # As in Playwright, these have no timeout, and a blocked page can hold them up.
  defp set_context!(session, capability, operation, fun) do
    browser_context = browser_context!(session, capability, operation)

    case fun.(browser_context) do
      {:error, error} -> raise error
      _ok -> session
    end
  end

  defp browser_context!(session, capability, operation) do
    CapabilityError.require_playwright!(session, capability, operation)
    Session.context(session).browser_context
  end
end
