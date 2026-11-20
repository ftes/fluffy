defmodule Fluffy.Driver.Static do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  import Fluffy.Driver.Phoenix.HTML.Semantics, only: [attribute: 2]

  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Expect
  alias Fluffy.Expectation
  alias Fluffy.Internal.Navigation
  alias Fluffy.Locator
  alias Fluffy.Session

  @impl true
  def open_browser(%Session{} = session, open_fun) do
    endpoint = if Session.context(session).http, do: Session.context(session).http.endpoint
    document = Session.page_state(session).client_dom.document
    Fluffy.OpenBrowser.write(document, Fluffy.OpenBrowser.static_asset_resolver(endpoint), open_fun)
    session
  end

  @impl true
  def validate_operation!(session, operation, arguments),
    do: Fluffy.Driver.Phoenix.Validation.validate_operation!(session, operation, arguments)

  @impl true
  def set_html(%Session{} = session, html) when is_binary(html) do
    state = Map.put(Session.page_state(session), :client_dom, ClientDOM.from_fragment(html))
    Session.put_page_state(session, state)
  end

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    case expectation do
      %Expect{target: {:locator, locator}, kind: :count, expected: expected} ->
        candidates =
          session |> client_dom() |> ClientDOM.resolve(locator)

        assert_count_expectation!(expectation, locator, expected, candidates)

      %Expect{target: {:locator, _locator}} ->
        {passed?, actual} = ClientDOM.Expectation.evaluate(client_dom(session), expectation)
        Expect.Internal.assert!(expectation, passed?, actual)

      %Expect{target: :page, kind: :url, expected: expected} ->
        actual = Session.current_page(session).url
        # A session for HTML has no server, so no base URL.
        base_url = with %{base_url: base_url} <- Session.context(session).http, do: base_url
        Expect.Internal.assert!(expectation, Expect.Internal.url_matches?(expected, base_url, actual), actual)

      %Expect{target: :page, kind: :title, expected: expected} ->
        actual = session |> Session.page_state() |> document() |> page_title()
        Expect.Internal.assert!(expectation, Expect.Internal.title_matches?(expected, actual), actual)
    end

    session
  end

  # Static actions check once, since nothing changes, so they read no option: the options
  # are validated, and on Phoenix hold at most `timeout:` (`Fluffy.Options.validate_action!/3`).
  @impl true
  def click(%Session{} = session, %Locator{} = locator, _options \\ []) do
    click = session |> Session.page_state() |> Map.fetch!(:client_dom) |> ClientDOM.click(locator)
    commit_click(session, click)
  end

  # Keeps the page the click's last dispatch left and takes its default action.
  defp commit_click(session, {clicks, default}) do
    {_target, _page, client_dom} = List.last(clicks)
    state = Session.page_state(session)
    session = Session.put_page_state(session, %{state | client_dom: client_dom})

    case default do
      nil ->
        session

      {:link, %{attributes: attributes}} ->
        {:navigate, session, Navigation.link(attribute(attributes, "href"), download: attribute(attributes, "download"))}

      {:phoenix_html, submission} ->
        {:navigate, session, Navigation.submission(submission)}

      {:submit, _submitter, submission} ->
        {:navigate, session, Navigation.submission(submission)}
    end
  end

  @impl true
  def submit(%Session{} = session, %Locator{} = locator, _options \\ []) do
    state = Session.page_state(session)
    client_dom = Map.fetch!(state, :client_dom)
    target = ClientDOM.target!(client_dom, locator)

    case ClientDOM.submit_form(client_dom, target) do
      nil ->
        raise ArgumentError, "submit/2 requires a form locator, got #{inspect(target.tag)}"

      submission ->
        {:navigate, session, Navigation.submission(submission)}
    end
  end

  @impl true
  def fill(%Session{} = session, %Locator{} = locator, value, _options \\ []) do
    fill_value(session, :fill, locator, value)
  end

  @impl true
  def clear(%Session{} = session, %Locator{} = locator, _options \\ []) do
    fill_value(session, :clear, locator, "")
  end

  defp fill_value(session, action, locator, value) do
    state = Session.page_state(session)
    client_dom = Map.fetch!(state, :client_dom)
    {client_dom, _target} = ClientDOM.fill(client_dom, locator, value, :static, action)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, _source_paths, selected_files, _options \\ []) do
    state = Session.page_state(session)
    client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, _options \\ []) do
    case session |> Session.page_state() |> Map.fetch!(:client_dom) |> ClientDOM.set_checked(locator, desired) do
      nil ->
        session

      # Like Playwright, check the control's state on the page the click left.
      {{clicks, _default} = click, control} ->
        {_target, _page, clicked_dom} = List.last(clicks)
        ClientDOM.ensure_checked!(clicked_dom, control, desired, locator)
        commit_click(session, click)
    end
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, _options \\ []) do
    state = Session.page_state(session)
    {client_dom, _target} = state |> Map.fetch!(:client_dom) |> ClientDOM.select_option(locator, requested)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  @spec press(Session.t(), Locator.t(), String.t()) :: no_return()
  @spec press(Session.t(), Locator.t(), String.t(), keyword()) :: no_return()
  def press(%Session{} = _session, %Locator{} = _locator, _key, _options \\ []) do
    raise Fluffy.CapabilityError,
      capability: :liveview_keyboard_events,
      operation: :press,
      driver: :static,
      detail: "Static pages do not support keyboard events"
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    case fun.(current_conn!(session)) do
      %Plug.Conn{} = returned_conn ->
        {:navigate, session, Navigation.static_conn(returned_conn)}

      other ->
        raise ArgumentError,
              "Static unwrap callback must return an updated Plug.Conn, got: #{inspect(other)}"
    end
  end

  # A read: the result is not a replacement conn, so the page stays as it is.
  @impl true
  def unwrap_and_return(%Session{} = session, fun) when is_function(fun, 1),
    do: {:return, fun.(current_conn!(session)), session}

  defp current_conn!(session) do
    case Session.page_state(session) do
      %{conn: %Plug.Conn{} = conn} ->
        conn

      _state ->
        raise ArgumentError,
              "cannot unwrap a Static page without a current Plug.Conn; visit a Phoenix page first"
    end
  end

  defp client_dom(session), do: session |> Session.page_state() |> Map.fetch!(:client_dom)
  defp document(state), do: state |> Map.fetch!(:client_dom) |> Map.fetch!(:document)

  defp page_title(document) do
    document
    |> LazyHTML.query("title")
    |> Enum.at(0)
    |> case do
      nil -> nil
      title -> LazyHTML.text(title)
    end
  end

  defp assert_count_expectation!(%Expect{negated?: false}, locator, expected, candidates) do
    Expectation.assert_count!(locator, expected, candidates)
  end

  defp assert_count_expectation!(%Expect{} = expectation, _locator, expected, candidates) do
    actual = length(candidates)
    Expect.Internal.assert!(expectation, actual == expected, actual)
  end
end
