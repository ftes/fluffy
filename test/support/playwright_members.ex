defmodule Fluffy.Support.PlaywrightMembers do
  # How Fluffy covers each member of the PlaywrightEx facade it builds on, checked
  # against the installed PlaywrightEx by `Fluffy.Support.PlaywrightMembersTest`. Review it on a
  # PlaywrightEx upgrade: new members are unclassified, removed ones stale.
  #
  #   * `:wrapped` - a Fluffy function or value field of the same name in `counterparts/1`.
  #   * `{:renamed, {module, fun, arity}}` - the Fluffy function that covers it.
  #   * `{:unwrap, reason}` - not wrapped, but safe natively: on the page through
  #     `Fluffy.unwrap/2`, on a locator through `Fluffy.Playwright.unwrap/3`, or on a
  #     value through `Fluffy.unwrap_and_return/2`. "gap:" marks candidates for a Fluffy API.
  #   * `{:denied, reason}` - breaks Fluffy's tracking or ownership when called natively.
  #   * `{:na, reason}` - not applicable: legacy, deprecated, or tooling.
  @moduledoc false

  alias Fluffy.Playwright.Keyboard
  alias Fluffy.Playwright.Mouse

  @legacy {:na, "selector-string duplicate of a Locator member"}
  @discouraged {:na, "deprecated or discouraged upstream"}
  @tooling {:na, "debugging or authoring tool"}
  @native_locator {:unwrap, "gap: on the native locator of Fluffy.Playwright.unwrap/3"}
  @native_read {:unwrap, "non-retrying read through Fluffy.Playwright.unwrap_and_return/3; prefer an expectation"}
  @native_page {:unwrap, "on the page of Fluffy.unwrap/2"}
  @page_gap {:unwrap, "gap: on the page of Fluffy.unwrap/2"}
  @native_value {:unwrap, "gap: on the PlaywrightEx value of Fluffy.unwrap_and_return/2"}
  @native_event {:unwrap, "gap: listen natively inside Fluffy.unwrap/2"}
  @event_value {:unwrap, "on the PlaywrightEx value an event delivers, as in Playwright"}
  @native_retry {:unwrap, "gap: retries any callback natively, Fluffy calls in it too"}
  @own_timeouts {:denied,
                 "the defaults are config, as in Playwright Test: `action_timeout` and `navigation_timeout` of " <>
                   "`config :playwright_ex, :test`; Fluffy's own calls read them there"}
  @own_listeners {:denied, "removes the listeners Fluffy relies on for pages and events"}
  @own_document {:denied, "replaces the tracked document outside navigation tracking"}

  @selector_legacy ~w(check click dblclick dispatch_event drag_and_drop eval_on_selector eval_on_selector_all
                      fill focus get_attribute hover inner_html inner_text input_value is_checked is_disabled
                      is_editable is_enabled is_hidden is_visible press query_selector query_selector_all
                      select_option set_checked set_input_files tap text_content type uncheck wait_for_selector)a

  @by %{
    get_by_alt_text: :by_alt_text,
    get_by_label: :by_label,
    get_by_placeholder: :by_placeholder,
    get_by_role: :by_role,
    get_by_test_id: :by_test_id,
    get_by_text: :by_text,
    get_by_title: :by_title
  }

  # Scoped locator builders (scope, value, options).
  # `by_test_id` takes no options, as `getByTestId`.
  defp by(arity) do
    for {upstream, fluffy} <- @by,
        do: {[upstream], {:renamed, {Fluffy.Locator, fluffy, if(fluffy == :by_test_id, do: 2, else: arity)}}}
  end

  @doc "Fluffy modules searched for a `:wrapped` member."
  def counterparts(PlaywrightEx.Locator), do: [Fluffy.Locator, Fluffy, Fluffy.Playwright]
  def counterparts(PlaywrightEx.Expect), do: [Fluffy.Expect]
  def counterparts(PlaywrightEx.Page), do: [Fluffy, Fluffy.Playwright, Fluffy.Page]
  def counterparts(PlaywrightEx.FrameLocator), do: [Fluffy.FrameLocator]
  def counterparts(PlaywrightEx.BrowserContext), do: [Fluffy.Playwright]
  def counterparts(PlaywrightEx.Clock), do: [Fluffy.Playwright.Clock]
  def counterparts(PlaywrightEx.Keyboard), do: [Keyboard]
  def counterparts(PlaywrightEx.Mouse), do: [Mouse]
  def counterparts(PlaywrightEx.Download), do: [Fluffy.Download]
  def counterparts(PlaywrightEx.FileChooser), do: [Fluffy.FileChooser]
  def counterparts(:event), do: [Fluffy.Event]
  def counterparts(_module), do: []

  @doc "Facade modules and their members, `[{[fun], classification}]`."
  def members do
    %{
      PlaywrightEx.Locator =>
        [
          {~w(and_ or_ filter first last nth content_frame frame_locator)a, :wrapped},
          {~w(click fill check uncheck select_option press set_input_files)a, :wrapped},
          {~w(hover drag_to press_sequentially focus blur wait_for bounding_box aria_snapshot)a, :wrapped},
          {~w(evaluate evaluate_all wait_for_function drop all within)a, :wrapped},
          {~w(clear set_checked dblclick tap dispatch_event select_text scroll_into_view_if_needed screenshot)a,
           :wrapped},
          {[:locator], {:renamed, {Fluffy.Locator, :by_css, 2}}},
          {[:visible], {:renamed, {Fluffy.Locator, :filter, 2}}},
          {~w(evaluate_handle aria_snapshot_json)a, @native_locator},
          {~w(count text_content inner_text inner_html all_text_contents all_inner_texts get_attribute input_value
              is_checked is_disabled is_editable is_enabled is_hidden is_visible)a, @native_read},
          {~w(describe description to_string normalize)a, {:na, "names a native locator; Fluffy locators inspect"}},
          {[:page], {:renamed, {Fluffy.Playwright, :current_page, 1}}},
          {~w(highlight hide_highlight)a, @tooling},
          {~w(element_handle element_handles)a, {:na, "ElementHandle is discouraged upstream"}},
          {[:type], @discouraged}
        ] ++ by(3),
      PlaywrightEx.Expect =>
        expect([
          {~w(to_have_count to_be_visible to_be_disabled to_be_editable to_be_enabled to_be_focused to_be_checked
              to_have_value to_have_values to_have_text to_contain_text to_have_attribute to_have_class
              to_contain_class to_have_id to_be_attached to_be_hidden to_be_empty to_be_in_viewport to_have_css
              to_have_js_property to_have_screenshot to_have_role to_have_accessible_name
              to_have_accessible_description to_have_accessible_error_message to_match_aria_snapshot)a, :wrapped},
          {[:to_have_title], {:renamed, {Fluffy.Expect, :page_to_have_title, 2}}},
          {[:to_have_url], {:renamed, {Fluffy.Expect, :page_to_have_url, 2}}},
          {[:to_be_ok], {:na, "APIResponse assertion"}},
          {[:soft], {:unwrap, "gap: soft matchers on the native locator of Fluffy.Playwright.unwrap/3"}},
          {[:message], {:unwrap, "gap: custom expect messages on the native locator of Fluffy.Playwright.unwrap/3"}},
          {[:to_pass], @native_retry},
          {[:poll], @native_retry}
        ]),
      PlaywrightEx.Page =>
        [
          {~w(reload go_back go_forward url opener evaluate screenshot on once off)a, :wrapped},
          {~w(set_viewport_size viewport_size emulate_media wait_for_function wait_for_load_state add_script_tag
              add_style_tag aria_snapshot pdf bring_to_front content title local_storage session_storage)a, :wrapped},
          {[:keyboard], {:renamed, {Keyboard, :press, 3}}},
          {[:mouse], {:renamed, {Mouse, :click, 4}}},
          {[:goto], {:renamed, {Fluffy, :visit, 2}}},
          {[:close], {:renamed, {Fluffy.Playwright, :close_page, 2}}},
          {[:add_listener], {:renamed, {Fluffy, :on, 4}}},
          {[:remove_listener], {:renamed, {Fluffy, :off, 4}}},
          {[:wait_for_event], {:renamed, {Fluffy, :wait_for, 3}}},
          {[:expect_event], {:renamed, {Fluffy.Expect, :expect_event, 3}}},
          {[:expect_download], {:renamed, {Fluffy.Event, :download, 1}}},
          {[:expect_popup], {:renamed, {Fluffy.Event, :popup, 1}}},
          {[:expect_file_chooser], {:renamed, {Fluffy.Event, :file_chooser, 1}}},
          {~w(expect_request wait_for_request)a, {:renamed, {Fluffy.Event, :request, 1}}},
          {~w(expect_response wait_for_response)a, {:renamed, {Fluffy.Event, :response, 1}}},
          {[:locator], {:renamed, {Fluffy.Locator, :by_css, 1}}},
          {[:frame_locator], {:renamed, {Fluffy.Locator, :frame_locator, 1}}},
          {[:expect_console_message], {:renamed, {Fluffy.Event, :console, 1}}},
          {[:expect_request_finished], {:renamed, {Fluffy.Event, :request_finished, 1}}},
          {[:expect_websocket], {:renamed, {Fluffy.Event, :web_socket, 1}}},
          {[:expect_worker], {:renamed, {Fluffy.Event, :worker, 1}}},
          {~w(route unroute unroute_all)a, :wrapped},
          {~w(route_from_har route_web_socket touchscreen aria_snapshot_json add_locator_handler remove_locator_handler)a,
           @page_gap},
          {~w(wait_for_url add_init_script expose_binding expose_function set_extra_http_headers console_messages
              clear_console_messages page_errors clear_page_errors requests workers context main_frame frame
              frames request coverage video screencast
              is_closed evaluate_handle prepend_listener clock pause)a, @native_page},
          {[:remove_all_listeners], @own_listeners},
          {~w(set_default_timeout set_default_navigation_timeout)a, @own_timeouts},
          {[:set_content], @own_document},
          {~w(pick_locator cancel_pick_locator hide_highlight get_by_ref webmcp request_gc)a, @tooling},
          {~w(expect_navigation wait_for_navigation wait_for_timeout)a, @discouraged},
          {@selector_legacy, @legacy}
        ] ++ for({upstream, fluffy} <- @by, do: {[upstream], {:renamed, {Fluffy.Locator, fluffy, 2}}}),
      PlaywrightEx.Frame => [
        {~w(url page parent_frame)a, @event_value},
        {~w(name child_frames is_detached title frame_element goto evaluate evaluate_handle wait_for_load_state
              wait_for_url wait_for_function content add_script_tag add_style_tag locator frame_locator)a,
         {:unwrap, "on the frame of Fluffy.unwrap/2; Fluffy locators resolve from the page"}},
        {Map.keys(@by), {:unwrap, "on the frame of Fluffy.unwrap/2; Fluffy locators resolve from the page"}},
        {[:set_content], @own_document},
        {~w(expect_navigation wait_for_navigation wait_for_timeout)a, @discouraged},
        {[:webmcp], @tooling},
        {@selector_legacy, @legacy}
      ],
      PlaywrightEx.FrameLocator =>
        [
          {[:owner], :wrapped},
          {[:locator], {:renamed, {Fluffy.Locator, :by_css, 2}}},
          {[:frame_locator], {:renamed, {Fluffy.Locator, :frame_locator, 2}}},
          {~w(first last nth)a, {:na, "select the iframe on the owner: owner |> first() |> content_frame()"}}
        ] ++ by(3),
      PlaywrightEx.BrowserContext => [
        {~w(add_cookies cookies clear_cookies storage_state new_page pages add_init_script)a, :wrapped},
        {[:tracing], {:denied, "PlaywrightEx.Test records the trace: config or `@tag trace: true`"}},
        {[:on], {:renamed, {Fluffy, :on, 4}}},
        {[:once], {:renamed, {Fluffy, :once, 4}}},
        {[:off], {:renamed, {Fluffy, :off, 4}}},
        {[:add_listener], {:renamed, {Fluffy, :on, 4}}},
        {[:remove_listener], {:renamed, {Fluffy, :off, 4}}},
        {[:wait_for_event], {:renamed, {Fluffy, :wait_for, 3}}},
        {[:expect_event], {:renamed, {Fluffy.Expect, :expect_event, 3}}},
        {[:expect_page], {:renamed, {Fluffy.Event, :page, 1}}},
        {[:expect_console_message], @native_event},
        {~w(grant_permissions clear_permissions set_geolocation set_offline set_http_credentials)a, :wrapped},
        {[:set_extra_http_headers], :wrapped},
        {~w(route unroute unroute_all)a, :wrapped},
        {~w(route_from_har route_web_socket)a, {:unwrap, "gap: on PlaywrightEx.Page.context/1 inside Fluffy.unwrap/2"}},
        {[:set_storage_state], :wrapped},
        {~w(expose_binding expose_function clock browser
            background_pages service_workers new_cdp_session credentials debugger request is_closed
            prepend_listener)a, {:unwrap, "on PlaywrightEx.Page.context/1 inside Fluffy.unwrap/2"}},
        {[:close], {:denied, "the session owns its context; use Fluffy.close_session/1"}},
        {[:remove_all_listeners], @own_listeners},
        {~w(set_default_timeout set_default_navigation_timeout)a, @own_timeouts}
      ],
      PlaywrightEx.Keyboard => [{~w(down insert_text press type up)a, :wrapped}],
      PlaywrightEx.Mouse => [{~w(click dblclick down move up wheel)a, :wrapped}],
      PlaywrightEx.Touchscreen => [{[:tap], {:unwrap, "page-global input on PlaywrightEx.Page.touchscreen/1"}}],
      PlaywrightEx.Dialog => [{~w(accept dismiss page type message default_value)a, @event_value}],
      PlaywrightEx.Download => [
        {~w(suggested_filename url page)a, :wrapped},
        {[:save_as], {:renamed, {Fluffy.Download, :save_as, 2}}},
        {[:create_read_stream], {:renamed, {Fluffy.Download, :read, 2}}},
        {[:path], :wrapped},
        {~w(failure delete cancel)a, {:unwrap, "on PlaywrightEx.Download inside Fluffy.unwrap_and_return/2"}}
      ],
      PlaywrightEx.FileChooser => [
        {[:page], :wrapped},
        {[:is_multiple], {:renamed, {Fluffy.FileChooser, :multiple?, 1}}},
        {[:set_files], {:renamed, {Fluffy, :set_input_files, 4}}},
        {[:element], @native_value}
      ],
      PlaywrightEx.Request => [
        {~w(url method headers resource_type post_data failure redirected_from redirected_to all_headers header_value
            post_data_json frame timing sizes response headers_array post_data_buffer is_navigation_request
            existing_response service_worker)a, @event_value}
      ],
      PlaywrightEx.Response => [
        {~w(url status status_text headers request ok body text json all_headers header_value header_values
            security_details server_addr finished frame headers_array http_version from_service_worker)a, @event_value}
      ],
      PlaywrightEx.Route => [
        {~w(abort continue fallback fulfill request fetch)a,
         {:unwrap, "on the PlaywrightEx route a route/4 handler receives"}}
      ],
      PlaywrightEx.ConsoleMessage => [{~w(location page text timestamp type args worker)a, @event_value}],
      PlaywrightEx.WebError => [
        {~w(error location page)a, {:unwrap, "gap: from a native web_error listener"}}
      ],
      PlaywrightEx.Clock => [
        {~w(install pause_at run_for fast_forward resume set_fixed_time set_system_time)a, :wrapped}
      ],
      PlaywrightEx.Tracing => [
        {~w(start stop stop_chunk)a, {:denied, "PlaywrightEx.Test records the trace: config or `@tag trace: true`"}},
        {~w(group group_end)a, {:renamed, {Fluffy.Playwright, :step, 4}}},
        {~w(start_chunk start_har stop_har)a, {:unwrap, "on PlaywrightEx.BrowserContext.tracing/1"}}
      ]
    }
  end

  @doc "Facade modules with events (`@type event`) and their events, `[{[event], classification}]`."
  def events do
    %{
      PlaywrightEx.Page => [
        {~w(close console crash dialog dom_content_loaded download file_chooser frame_attached frame_detached
            frame_navigated load page_error popup request request_failed request_finished response web_socket
            worker)a, :wrapped},
        {[:dialog_closed], @native_event}
      ],
      PlaywrightEx.BrowserContext => [
        {~w(page request response request_failed request_finished)a, :wrapped},
        {~w(console dialog dialog_closed download frame_attached frame_detached frame_navigated page_close page_load
            web_error background_page service_worker)a, @native_event},
        {[:close], {:na, "the session owns its context"}}
      ]
    }
  end

  @doc """
  Wrapped members whose upstream call takes `timeout:` but whose options Fluffy does not
  classify in `Fluffy.Options`, with how they are handled instead.
  """
  def unclassified_options do
    %{
      {PlaywrightEx.Page, :goto} => "Fluffy.visit/2 navigates by path and takes no options",
      {PlaywrightEx.Page, :wait_for_event} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_event} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_download} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_popup} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_file_chooser} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_request} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_response} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_console_message} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_request_finished} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_websocket} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :expect_worker} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :wait_for_request} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.Page, :wait_for_response} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.BrowserContext, :wait_for_event} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.BrowserContext, :expect_event} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.BrowserContext, :expect_page} => "Fluffy.Event waits take timeout: and scope:",
      {PlaywrightEx.FileChooser, :set_files} => "Fluffy.set_input_files/4 takes timeout: and max_bytes:"
    }
  end

  # A negated matcher is covered by `Fluffy.Expect.not_/1` when its positive one is wrapped.
  defp expect(groups) do
    negated =
      for {funs, classification} <- groups,
          fun = Atom.to_string(hd(funs)),
          String.starts_with?(fun, "to_") do
        negated = classification in [:wrapped] or match?({:renamed, _}, classification)
        {Enum.map(funs, &:"not_#{&1}"), if(negated, do: {:renamed, {Fluffy.Expect, :not_, 1}}, else: classification)}
      end

    [{[:not_], :wrapped} | groups] ++ negated
  end
end
