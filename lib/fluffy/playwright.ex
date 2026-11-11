defmodule Fluffy.Playwright do
  @moduledoc """
  Browser-only helpers for the active Playwright page.

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
  alias Fluffy.Backend.Playwright.Document
  alias Fluffy.CapabilityError
  alias Fluffy.Options
  alias Fluffy.Playwright.Trace
  alias Fluffy.Route
  alias Fluffy.Session
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.WebStorage

  @trace_schema NimbleOptions.new!(
                  directory: [
                    type: :string,
                    doc: "Directory in which to save the trace archive."
                  ],
                  name: [
                    type: :string,
                    doc: "Human-readable trace name and artifact filename prefix."
                  ],
                  open: [
                    type: :boolean,
                    default: true,
                    doc: "Open Playwright Trace Viewer after saving the trace."
                  ]
                )

  @trace_capture [screenshots: true, snapshots: true, sources: true]

  @route_schema NimbleOptions.new!(
                  times: [
                    type: :pos_integer,
                    doc: "How many requests the route handles before it expires. By default it never expires."
                  ]
                )

  @typedoc "Fluffy's trace options, and the capture options of `PlaywrightEx.Tracing.start/2`."
  @type trace_option ::
          unquote(NimbleOptions.option_typespec(@trace_schema))
          | {:screenshots, boolean()}
          | {:snapshots, boolean() | map()}
          | {:sources, boolean()}
          | {:live, boolean()}

  @type route_option :: unquote(NimbleOptions.option_typespec(@route_schema))

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
    ensure_playwright_backend!(session, :pages)
    Session.current_driver(session)
    Session.handle(session)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Selects a page handle for this pipeline, without changing other session handles."
  @spec switch_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def switch_page(%Session{} = session, %Fluffy.Page{} = page) do
    ensure_playwright_backend!(session, :pages)
    Session.activate_page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Closes a page. Handles selecting it must explicitly switch to another page before continuing."
  @spec close_page(Session.t()) :: Session.t()
  def close_page(%Session{} = session) do
    ensure_playwright_backend!(session, :pages)
    close_page(session, Session.handle(session))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Closes the given page handle, preserving the session's current-page selection."
  @spec close_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def close_page(%Session{} = session, %Fluffy.Page{} = page) do
    ensure_playwright_backend!(session, :pages)
    Backend.close_page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Returns live handles for all open pages, including browser pages discovered without an event wait."
  @spec pages(Session.t()) :: [Fluffy.Page.t()]
  def pages(%Session{} = session) do
    ensure_playwright_backend!(session, :pages)
    Enum.map(Session.pages(session), fn {id, _page} -> Fluffy.Page.new(session.runtime, id) end)
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
  def new_page(%Session{} = session), do: Backend.new_page(session)

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
    ensure_playwright_backend!(session, :browser_history)
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
    ensure_playwright_backend!(session, :browser_history)
    Backend.history(session, :go_forward, Options.validate_action!(:go_forward, options))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Waits for the active page to reach a load state and returns the session.

  `state` is `:load` (the default), `:domcontentloaded` or `:networkidle`, and the
  options may take its place. The call raises after the session's `timeout:` unless
  `timeout:` is given. Phoenix sessions raise `Fluffy.CapabilityError`.

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

  def wait_for_load_state(%Session{} = session, state, options) do
    ensure_playwright_backend!(session, :wait_for_load_state)
    options = Options.validate_action!(:wait_for_load_state, options)
    wait = &PlaywrightEx.Page.wait_for_load_state(&1, state, &2)
    Fluffy.__dispatch_driver__(session, :page_wait, [:wait_for_load_state, wait, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Focuses the target in the active browser page. Accepts `timeout:`."
  @spec focus(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def focus(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :focus)
    options = Options.validate_action!(:focus, options)
    Fluffy.__dispatch_driver__(session, :focus, [locator, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Blurs the target in the active browser page. Accepts `timeout:`."
  @spec blur(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def blur(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :blur)
    options = Options.validate_action!(:blur, options)
    Fluffy.__dispatch_driver__(session, :blur, [locator, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Hovers over a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:hover)}.

  #{NimbleOptions.docs(Options.action_schema(:hover))}
  """
  @spec hover(Session.t(), Fluffy.Locator.t(), [hover_option()]) :: Session.t()
  def hover(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :hover)
    Fluffy.__dispatch_driver__(session, :hover, [locator, Options.validate_action!(:hover, options)])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Drags the source locator onto the target locator in the same frame.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:drag_to)}.

  #{NimbleOptions.docs(Options.action_schema(:drag_to))}
  """
  @spec drag_to(Session.t(), Fluffy.Locator.t(), Fluffy.Locator.t(), [drag_to_option()]) :: Session.t()
  def drag_to(%Session{} = session, source, target, options \\ []) do
    ensure_playwright_backend!(session, :drag_to)
    Fluffy.__dispatch_driver__(session, :drag_to, [source, target, Options.validate_action!(:drag_to, options)])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Types text character by character, emitting keyboard events.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:press_sequentially)}.

  #{NimbleOptions.docs(Options.action_schema(:press_sequentially))}
  """
  @spec press_sequentially(Session.t(), Fluffy.Locator.t(), String.t(), [press_sequentially_option()]) :: Session.t()
  def press_sequentially(%Session{} = session, locator, text, options \\ []) do
    ensure_playwright_backend!(session, :press_sequentially)
    options = Options.validate_action!(:press_sequentially, options)
    Fluffy.__dispatch_driver__(session, :press_sequentially, [locator, text, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Double-clicks a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:dblclick)}.

  #{NimbleOptions.docs(Options.action_schema(:dblclick))}
  """
  @spec dblclick(Session.t(), Fluffy.Locator.t(), [dblclick_option()]) :: Session.t()
  def dblclick(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :dblclick)
    Fluffy.__dispatch_driver__(session, :dblclick, [locator, Options.validate_action!(:dblclick, options)])
  end

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
  def tap(%Session{} = session, locator, options) do
    ensure_playwright_backend!(session, :tap)
    Fluffy.__dispatch_driver__(session, :tap, [locator, Options.validate_action!(:tap, options)])
  end

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
      when is_binary(type) and (is_map(event_init) or is_nil(event_init)) do
    ensure_playwright_backend!(session, :dispatch_event)
    options = Options.validate_action!(:dispatch_event, options)
    Fluffy.__dispatch_driver__(session, :dispatch_event, [locator, type, event_init, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Selects the text of a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:select_text)}.

  #{NimbleOptions.docs(Options.action_schema(:select_text))}
  """
  @spec select_text(Session.t(), Fluffy.Locator.t(), [select_text_option()]) :: Session.t()
  def select_text(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :select_text)
    Fluffy.__dispatch_driver__(session, :select_text, [locator, Options.validate_action!(:select_text, options)])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Scrolls a locator into view unless it is already visible. Accepts `timeout:`."
  @spec scroll_into_view_if_needed(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def scroll_into_view_if_needed(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :scroll_into_view_if_needed)
    options = Options.validate_action!(:scroll_into_view_if_needed, options)
    Fluffy.__dispatch_driver__(session, :scroll_into_view_if_needed, [locator, options])
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the bounding box of a locator as `%{x: x, y: y, width: width, height: height}`,
  or `nil` if the element is not visible.

  Coordinates are in CSS pixels relative to the main frame's viewport. As in
  Playwright, finding the element raises after the session's `timeout:` unless
  `timeout:` is given; reading its box has no timeout. Phoenix sessions raise
  `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:bounding_box))}
  """
  @spec bounding_box(Session.t(), Fluffy.Locator.t(), [bounding_box_option()]) ::
          %{x: number(), y: number(), width: number(), height: number()} | nil
  def bounding_box(%Session{} = session, %Fluffy.Locator{} = locator, options \\ []) do
    ensure_playwright_backend!(session, :bounding_box)
    Fluffy.__dispatch_driver__(session, :bounding_box, [locator, Options.validate_action!(:bounding_box, options)])
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the ARIA snapshot of the active page, or of a locator, as YAML text.

  The call raises after the session's `timeout:` unless `timeout:` is given. Phoenix
  sessions raise `Fluffy.CapabilityError`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:aria_snapshot)}.

  #{NimbleOptions.docs(Options.action_schema(:aria_snapshot))}
  """
  @spec aria_snapshot(Session.t(), Fluffy.Locator.t() | [aria_snapshot_option()], [aria_snapshot_option()]) :: String.t()
  def aria_snapshot(session, locator_or_options \\ [], options \\ [])

  def aria_snapshot(%Session{} = session, options, []) when is_list(options) do
    ensure_playwright_backend!(session, :aria_snapshot)
    Fluffy.__dispatch_driver__(session, :page_aria_snapshot, [Options.validate_action!(:page_aria_snapshot, options)])
  end

  def aria_snapshot(%Session{} = session, %Fluffy.Locator{} = locator, options) do
    ensure_playwright_backend!(session, :aria_snapshot)
    Fluffy.__dispatch_driver__(session, :aria_snapshot, [locator, Options.validate_action!(:aria_snapshot, options)])
  end

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
    ensure_playwright_backend!(session, :all)
    count = unwrap_and_return(session, locator, &PlaywrightEx.Locator.count!/1)
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
  def drop(%Session{} = session, %Fluffy.Locator{} = locator, payload, options \\ []) when is_map(payload) do
    ensure_playwright_backend!(session, :drop)
    Fluffy.__dispatch_driver__(session, :drop, [locator, payload, Options.validate_action!(:drop, options)])
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Saves the active page as a PDF and returns the session.

  Browsers other than Chromium cannot generate one and raise. Phoenix sessions raise
  `Fluffy.CapabilityError`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:pdf)}.

  #{NimbleOptions.docs(Options.action_schema(:pdf))}
  """
  @spec pdf(Session.t(), Path.t(), [pdf_option()]) :: Session.t()
  def pdf(%Session{} = session, path, options \\ []) when is_binary(path) do
    ensure_playwright_backend!(session, :pdf)
    native = Options.validate_action!(:pdf, options)
    native = Keyword.put(native, :path, path)
    page_action(session, :pdf, &PlaywrightEx.Page.pdf(&1, native))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Brings the active page to the front and returns the session."
  @spec bring_to_front(Session.t(), []) :: Session.t()
  def bring_to_front(%Session{} = session, options \\ []) do
    ensure_playwright_backend!(session, :bring_to_front)
    Options.validate_untimed!(options)
    page_action(session, :bring_to_front, &PlaywrightEx.Page.bring_to_front/1)
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
    ensure_playwright_backend!(session, :content)
    native = Options.validate_action!(:content, options)
    page_read(session, :content, &PlaywrightEx.Page.content(&1, native))
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc "Returns the active page's title. To assert it, use `Fluffy.Expect.page_to_have_title/2`."
  @spec title(Session.t(), []) :: String.t()
  def title(%Session{} = session, options \\ []) do
    ensure_playwright_backend!(session, :title)
    Options.validate_untimed!(options)
    page_read(session, :title, &PlaywrightEx.Page.title/1)
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
    ensure_playwright_backend!(session, :local_storage)
    Options.validate_untimed!(options)
    page_read(session, :local_storage, fn page -> WebStorage.items(PlaywrightEx.Page.local_storage(page)) end)
  end

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the active page's `sessionStorage` for its current origin, as
  `local_storage/2` does. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec session_storage(Session.t(), []) :: [%{name: String.t(), value: String.t()}]
  def session_storage(%Session{} = session, options \\ []) do
    ensure_playwright_backend!(session, :session_storage)
    Options.validate_untimed!(options)
    page_read(session, :session_storage, fn page -> WebStorage.items(PlaywrightEx.Page.session_storage(page)) end)
  end

  defp page_read(session, operation, fun), do: Fluffy.__dispatch_driver__(session, :page_read, [operation, fun])

  @doc group: "Page inspection"
  @doc playwright_only: true
  @doc """
  Returns the active page's viewport as `%{width: width, height: height}`, or `nil`
  without a fixed viewport. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec viewport_size(Session.t()) :: %{width: integer(), height: integer()} | nil
  def viewport_size(%Session{} = session) do
    ensure_playwright_backend!(session, :viewport_size)
    PlaywrightEx.Page.viewport_size(Session.page_state(session).page)
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Resizes the active page's viewport to `%{width: width, height: height}`.
  """
  @spec set_viewport_size(Session.t(), %{width: integer(), height: integer()}, []) :: Session.t()
  def set_viewport_size(%Session{} = session, %{width: _, height: _} = size, options \\ []) do
    ensure_playwright_backend!(session, :set_viewport_size)
    Options.validate_untimed!(options)
    page_action(session, :set_viewport_size, &PlaywrightEx.Page.set_viewport_size(&1, size))
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
    ensure_playwright_backend!(session, :emulate_media)
    native = Options.validate_action!(:emulate_media, options)
    page_action(session, :emulate_media, &PlaywrightEx.Page.emulate_media(&1, native))
  end

  defp page_action(session, operation, fun), do: Fluffy.__dispatch_driver__(session, :page_action, [operation, fun])

  @doc false
  def __page_input__(session, device, operation, fun) do
    ensure_playwright_backend!(session, :browser_pointer_typing)
    page_action(session, operation, &fun.(device.(&1)))
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Intercepts matching browser requests in the session's context, so popups and
  new pages are covered too, and returns the session.

  `url` is what `Fluffy.Expect.page_to_have_url/2` accepts: a string, a regular
  expression, a unary predicate over the `URI`, or path, query and fragment
  components. A string is a Playwright glob, resolved against the session's
  `base_url:`, such as `"**/api/*"` or `"/api/potions"`.

  `handler` receives a `Fluffy.Route` and must answer it with
  `Fluffy.Route.fulfill/2`, `continue/2`, `abort/2` or `fallback/2`:

      import Fluffy.Playwright
      alias Fluffy.Route

      session
      |> route("/api/potions", fn route -> Route.fulfill(route, json: [%{name: "Felix Felicis"}]) end)
      |> visit("/potions")

  The handler runs in its own process, since the test process is blocked in the
  action that caused the request. That process is a `$callers` descendant of
  this call's process, so the Ecto sandbox allows its queries. Requests run
  concurrently.

  When several routes match, the last registered wins; `Fluffy.Route.fallback/2`
  hands the request to the one registered before it.

  A handler that raises aborts its request and fails this call's process, like a
  `Fluffy.on/4` handler. A handler may return without answering and leave the
  route to another process, such as the test; a request never answered hangs until
  the action waiting for it times out, as in Playwright. The route lasts until
  `unroute/3` or the session's end, even if this call's process exits first, unlike
  an `on/4` listener. Like Playwright, routing disables the browser's HTTP cache. See
  [Routing requests](advanced-events.md#routing-requests).

  Phoenix sessions raise `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(@route_schema)}
  """
  @spec route(Session.t(), Fluffy.Page.url_expectation(), (Route.t() -> term()), [route_option()]) :: Session.t()
  def route(%Session{} = session, url, handler, options \\ []) when is_function(handler, 1) and is_list(options) do
    ensure_playwright_backend!(session, :routing)
    options = NimbleOptions.validate!(options, @route_schema)
    Route.Registration.start(session, url, handler, options)
    session
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Removes the routes registered for `url` by `route/4`, or only those of `handler`,
  and returns the session.

  `url` must be the matcher given to `route/4`. As in Playwright, this does not
  wait for handlers already running. Removing the last route lets their requests go
  on to the server, so a late answer raises in its handler and fails this call's
  process; `unroute_all/2` with `behavior:` avoids that. Phoenix sessions raise
  `Fluffy.CapabilityError`.
  """
  @spec unroute(Session.t(), Fluffy.Page.url_expectation(), (Route.t() -> term()) | nil) :: Session.t()
  def unroute(%Session{} = session, url, handler \\ nil) when is_nil(handler) or is_function(handler, 1) do
    ensure_playwright_backend!(session, :routing)
    Route.Registration.remove(session, url, handler)
    session
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Removes every route on the browser context and returns the session.

  As in Playwright, this includes routes set up natively and HAR routers, not only
  those registered by `route/4`. `behavior:` decides what happens to handlers
  already running, and there is no timeout, as in Playwright. Phoenix sessions
  raise `Fluffy.CapabilityError`.

  ## Options

  #{NimbleOptions.docs(Options.action_schema(:unroute_all))}
  """
  @spec unroute_all(Session.t(), [unroute_all_option()]) :: Session.t()
  def unroute_all(%Session{} = session, options \\ []) do
    ensure_playwright_backend!(session, :routing)
    Route.Registration.remove_all(session, Options.validate_action!(:unroute_all, options))
    session
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Runs `fun` with the `PlaywrightEx.Locator` for `locator` and returns the reconciled session.

  Like `Fluffy.unwrap/2`, for native locator operations that have no Fluffy
  API. The locator resolves in the active page, through any frame locators, and
  is not checked for strictness until the callback uses it. The callback's
  return value is ignored, and a document it navigates is adopted.

      session
      |> Fluffy.Playwright.unwrap(by_role(:button, name: "Edit"), &PlaywrightEx.Locator.dblclick!/1)
      |> expect(to_be_visible(by_label("Title")))

  Prefer PlaywrightEx bang functions inside the callback when failure should
  stop the test. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec unwrap(Session.t(), Fluffy.Locator.t(), (PlaywrightEx.Locator.t() -> term())) :: Session.t()
  def unwrap(%Session{} = session, %Fluffy.Locator{} = locator, fun) when is_function(fun, 1) do
    ensure_playwright_backend!(session, :native_locator)
    Fluffy.__dispatch_driver__(session, :unwrap_locator, [locator, fun])
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Runs `fun` with the `PlaywrightEx.Locator` for `locator` and returns the callback's result.

  Like `unwrap/3`, including the reconcile after the callback, but for reads:

      text = Fluffy.Playwright.unwrap_and_return(session, by_css("#status"), &PlaywrightEx.Locator.text_content!/1)

  Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec unwrap_and_return(Session.t(), Fluffy.Locator.t(), (PlaywrightEx.Locator.t() -> result)) :: result
        when result: term()
  def unwrap_and_return(%Session{} = session, %Fluffy.Locator{} = locator, fun) when is_function(fun, 1) do
    ensure_playwright_backend!(session, :native_locator)
    Fluffy.__dispatch_driver__(session, :unwrap_and_return_locator, [locator, fun])
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Starts a Playwright trace for this session's BrowserContext.

  The trace includes every page in the session and is saved when the test's
  lifecycle scope shuts down. Because an explicit trace is primarily a local
  debugging request, its viewer opens by default; pass `open: false` in CI. A
  session may start one trace.

  ## Options

  #{NimbleOptions.docs(@trace_schema)}

  Other options go to `PlaywrightEx.Tracing.start/2`. Fluffy defaults
  `screenshots:`, `snapshots:` and `sources:` to `true`.
  """
  @spec trace(Session.t(), [trace_option()]) :: Session.t()
  def trace(session, options \\ []) when is_list(options) do
    ensure_playwright_backend!(session, :tracing)
    {fluffy_options, capture_options} = Keyword.split(options, Keyword.keys(@trace_schema.schema))
    fluffy_options = NimbleOptions.validate!(fluffy_options, @trace_schema)
    context = Session.context(session)

    if context.trace do
      raise ArgumentError, "this Playwright session is already tracing"
    end

    trace = Trace.start(context, fluffy_options, Keyword.merge(@trace_capture, capture_options))

    :ok = Fluffy.SessionRuntime.register(session.runtime, {:trace, trace}, fn -> Trace.stop(trace) end)

    Session.put_context(session, Map.put(context, :trace, Trace.public_state(trace)))
  end

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Saves a screenshot of the active page and returns the session.

  Pass a locator and a path to capture one element, see `screenshot/4`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:page_screenshot)}.

  #{NimbleOptions.docs(Options.action_schema(:page_screenshot))}
  """
  @spec screenshot(Session.t(), Path.t(), [page_screenshot_option()]) :: Session.t()
  @spec screenshot(Session.t(), Fluffy.Locator.t(), Path.t()) :: Session.t()
  def screenshot(session, target, path_or_options \\ [])

  def screenshot(session, path, options) when is_binary(path) and is_list(options) do
    ensure_playwright_backend!(session, :screenshot)
    options = Options.validate_action!(:page_screenshot, options)
    Fluffy.__dispatch_driver__(session, :page_screenshot, [path, options])
  end

  def screenshot(session, %Fluffy.Locator{} = locator, path) when is_binary(path),
    do: screenshot(session, locator, path, [])

  @doc group: "Diagnostics and native access"
  @doc playwright_only: true
  @doc """
  Saves a screenshot of one element and returns the session.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:locator_screenshot)}.

  #{NimbleOptions.docs(Options.action_schema(:locator_screenshot))}
  """
  @spec screenshot(Session.t(), Fluffy.Locator.t(), Path.t(), [locator_screenshot_option()]) :: Session.t()
  def screenshot(%Session{} = session, %Fluffy.Locator{} = locator, path, options) when is_binary(path) do
    ensure_playwright_backend!(session, :screenshot)
    options = Options.validate_action!(:locator_screenshot, options)
    Fluffy.__dispatch_driver__(session, :screenshot, [locator, path, options])
  end

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Evaluates JavaScript in the active Playwright page and returns the value.

  This is `PlaywrightEx.Page.evaluate/3`: the expression is JavaScript source,
  either an expression or a function that receives `arg`. Promises are awaited,
  serializable values return as Elixir terms (objects as maps with string
  keys, JavaScript `null` as `:null`), and JavaScript failures raise. As in
  Playwright, it has no timeout and takes no options: an expression that never
  settles waits until the test times out.

  A non-empty keyword list in the place of `arg` is taken as options, and rejected,
  since no JavaScript value serializes to one; any other list, including `[]`, is an
  array.

  `evaluate/4` is a browser-only value query, so it returns the evaluated value
  rather than the Fluffy session. Use Elixir's `then/2` when a pipeline needs
  the value and then should continue with the session:

      import Fluffy
      import Fluffy.Playwright
      import Fluffy.Locator
      alias Fluffy.Playwright

      session
      |> then(fn session ->
        title = Playwright.evaluate(session, "document.title")
        assert title == "Potions classroom"
        session
      end)
      |> click(by_role(:button, name: "Continue"))

      Playwright.evaluate(session, "selector => document.querySelector(selector).textContent", "#status")

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
    ensure_playwright!(session)
    Options.validate_untimed!(options)

    case PlaywrightEx.Frame.evaluate(Session.page_state(session).frame, expression, arg) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  defp evaluate_target(session, %Fluffy.Locator{} = locator, expression, arg, options) do
    ensure_playwright!(session)
    options = Options.validate_action!(:locator_evaluate, options)
    Fluffy.__dispatch_driver__(session, :locator_evaluate, [locator, expression, arg, options])
  end

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
    ensure_playwright!(session)
    {arg, options} = arg_and_options(arg, options)
    Options.validate_untimed!(options)
    Fluffy.__dispatch_driver__(session, :evaluate_all, [locator, expression, arg])
  end

  @doc group: "JavaScript"
  @doc playwright_only: true
  @doc """
  Waits until a JavaScript expression returns a truthy value in the active page and returns the session.

  The expression is JavaScript source, either an expression or a function that
  receives `arg`, as in `evaluate/3`. It is re-evaluated until it is truthy, across
  navigations of the page; a navigation meanwhile is adopted. The call raises
  after the session's `timeout:` unless `timeout:` is given:

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

  defp wait_for_target(session, nil, expression, arg, options) do
    ensure_playwright!(session)
    options = Options.validate_action!(:wait_for_function, options)
    wait = &PlaywrightEx.Page.wait_for_function(&1, expression, arg, &2)
    Fluffy.__dispatch_driver__(session, :page_wait, [:wait_for_function, wait, options])
  end

  defp wait_for_target(session, %Fluffy.Locator{} = locator, expression, arg, options) do
    ensure_playwright!(session)
    options = Options.validate_action!(:locator_wait_for_function, options)
    Fluffy.__dispatch_driver__(session, :locator_wait_for_function, [locator, expression, arg, options])
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Adds cookies to the browser context and returns the session.

  Cookie maps use the keys of `PlaywrightEx.BrowserContext.add_cookies/2`, such as
  `%{name: "token", value: "abc", url: url, httpOnly: true, sameSite: "Lax"}`.
  """
  @spec add_cookies(Session.t(), [map()]) :: Session.t()
  def add_cookies(session, cookies) when is_list(cookies) do
    Enum.each(cookies, &reject_snake_case_cookie_keys!/1)
    session |> browser_context!(:add_cookies) |> BrowserContext.add_cookies!(cookies)
    session
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
    raise ArgumentError, "add_init_script: a script map takes no arg, got: #{inspect(arg)}"
  end

  def add_init_script(session, script, arg), do: set_context!(session, &BrowserContext.add_init_script(&1, script, arg))

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
    ensure_playwright_backend!(session, :add_script_tag)
    add_tag(session, :add_script_tag, &PlaywrightEx.Page.add_script_tag/2, options)
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
    ensure_playwright_backend!(session, :add_style_tag)
    add_tag(session, :add_style_tag, &PlaywrightEx.Page.add_style_tag/2, options)
  end

  defp add_tag(session, operation, add, options) do
    native = Options.validate_action!(operation, options)
    page_action(session, operation, &with({:ok, tag} <- add.(&1, native), do: Document.release(tag)))
  end

  # Playwright ignores unknown cookie keys, such as the snake_case ones Fluffy 0.8 took.
  @snake_case_cookie_keys %{http_only: :httpOnly, same_site: :sameSite, partition_key: :partitionKey}

  defp reject_snake_case_cookie_keys!(cookie) when is_map(cookie) do
    for {key, _value} <- cookie,
        {snake_case, camel_case} <- @snake_case_cookie_keys,
        key in [snake_case, Atom.to_string(snake_case)] do
      raise ArgumentError, "cookie key #{inspect(key)} is not a Playwright cookie field; use #{inspect(camel_case)}"
    end
  end

  defp reject_snake_case_cookie_keys!(_cookie), do: :ok

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc "Returns browser cookies, optionally only those for `urls`. See `PlaywrightEx.BrowserContext.cookies/2`."
  @spec cookies(Session.t(), String.t() | [String.t()] | nil) :: [map()]
  def cookies(session, urls \\ nil) do
    reject_cookies_options!(urls)
    session |> browser_context!(:cookies) |> BrowserContext.cookies!(urls)
  end

  # Fluffy 0.8 took `cookies(session, urls: [...], timeout: ...)`; such a list
  # would now reach Playwright as the URLs.
  defp reject_cookies_options!([{key, _value} | _] = options) when is_atom(key) do
    raise ArgumentError,
          "cookies/2 takes the URL list, not the options #{inspect(Keyword.keys(options))}; " <>
            "call cookies(session, urls): as in Playwright, it has no timeout"
  end

  defp reject_cookies_options!(_urls), do: :ok

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Clears cookies and returns the session.

  Accepts the filters of `PlaywrightEx.BrowserContext.clear_cookies/2`: `name:`, `domain:` and `path:`.
  """
  @spec clear_cookies(Session.t(), BrowserContext.clear_cookies_options()) :: Session.t()
  def clear_cookies(session, options \\ []) do
    session |> browser_context!(:clear_cookies) |> BrowserContext.clear_cookies!(options)
    session
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Returns the context's storage state for reuse as `browser_context: [storage_state: state]`.

  Accepts the options of `PlaywrightEx.BrowserContext.storage_state/2`, such as `path:` and `indexed_db:`.
  """
  @spec storage_state(Session.t(), BrowserContext.storage_state_options()) :: map()
  def storage_state(session, options \\ []) do
    session |> browser_context!(:storage_state) |> BrowserContext.storage_state!(options)
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
    set_context!(session, &BrowserContext.set_storage_state(&1, state))
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc """
  Grants browser permissions, such as `"geolocation"`, and returns the session.

  Accepts `origin:` to limit them to one origin. See `PlaywrightEx.BrowserContext.grant_permissions/3`.
  """
  @spec grant_permissions(Session.t(), [String.t()], BrowserContext.grant_permissions_options()) :: Session.t()
  def grant_permissions(session, permissions, options \\ []) when is_list(permissions) do
    set_context!(session, &BrowserContext.grant_permissions(&1, permissions, options))
  end

  @doc group: "Browser context"
  @doc playwright_only: true
  @doc "Clears all granted browser permissions and returns the session."
  @spec clear_permissions(Session.t()) :: Session.t()
  def clear_permissions(session) do
    set_context!(session, &BrowserContext.clear_permissions/1)
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
    set_context!(session, &BrowserContext.set_geolocation(&1, geolocation))
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc "Emulates the network being offline, or back online, and returns the session."
  @spec set_offline(Session.t(), boolean()) :: Session.t()
  def set_offline(session, offline) when is_boolean(offline) do
    set_context!(session, &BrowserContext.set_offline(&1, offline))
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
    set_context!(session, &BrowserContext.set_http_credentials(&1, credentials))
  end

  @doc group: "Network"
  @doc playwright_only: true
  @doc """
  Sets extra HTTP headers for every request of the session's browser context and
  returns the session.

  Each call replaces the headers of an earlier one, as in Playwright, but keeps those
  the session started with: `headers:`, `browser_context: [extra_http_headers: ...]`
  and the Ecto sandbox header. A header of the same name overrides them. Phoenix
  sessions raise `Fluffy.CapabilityError`.
  """
  @spec set_extra_http_headers(Session.t(), %{optional(String.t()) => String.t()}) :: Session.t()
  def set_extra_http_headers(session, headers) when is_map(headers) do
    headers = Map.new(headers, fn {name, value} -> {String.downcase(to_string(name)), value} end)

    # Playwright replaces all of the context's headers, the sandbox's among them.
    set_context!(session, fn browser_context ->
      merged = Map.merge(Session.context(session).extra_http_headers, headers)
      BrowserContext.set_extra_http_headers(browser_context, merged)
    end)
  end

  # As in Playwright, these have no timeout, and a blocked page can hold them up.
  defp set_context!(session, fun) do
    browser_context = browser_context!(session, :browser_context_setters)

    case fun.(browser_context) do
      {:error, error} -> raise error
      _ok -> session
    end
  end

  defp browser_context!(session, operation) do
    ensure_playwright_backend!(session, operation)
    Session.context(session).browser_context
  end

  defp ensure_playwright!(session) do
    case Session.current_driver(session) do
      :playwright ->
        :ok

      driver ->
        raise CapabilityError,
          capability: :javascript_evaluation,
          driver: driver,
          detail:
            "JavaScript evaluation requires an active Playwright page; the current page driver is #{inspect(driver)}"
    end
  end

  @doc false
  def __ensure_playwright_backend__!(session, capability), do: ensure_playwright_backend!(session, capability)

  defp ensure_playwright_backend!(session, capability) do
    if Session.backend(session) != PlaywrightBackend do
      raise CapabilityError,
        capability: capability,
        driver: Session.current_driver(session),
        detail: "#{inspect(capability)} requires a Playwright session"
    end
  end
end
