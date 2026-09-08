defmodule Fluffy.Driver.Static do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.ClientDOM
  alias Fluffy.Expect
  alias Fluffy.Expectation
  alias Fluffy.Locator
  alias Fluffy.Locator.Static, as: StaticLocator
  alias Fluffy.Navigation
  alias Fluffy.Session
  alias Fluffy.URLMatcher

  @impl true
  def set_html(%Session{} = session, html) when is_binary(html) do
    state = Map.put(Session.page_state(session), :client_dom, ClientDOM.from_fragment(html))
    Session.put_page_state(session, state)
  end

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    Keyword.validate!(expectation.options, [:timeout])

    case expectation do
      %Expect{target: {:locator, locator}, kind: :count, expected: expected} ->
        candidates =
          session |> Session.page_state() |> document() |> StaticLocator.resolve(locator)

        assert_count_expectation!(expectation, locator, expected, candidates)

      %Expect{target: {:locator, locator}, kind: :visible} ->
        candidates =
          session |> Session.page_state() |> document() |> StaticLocator.resolve(locator)

        visible_count = Enum.count(candidates, &structurally_visible?/1)
        assert_truth!(expectation, visible_count > 0, visible_count)

      %Expect{target: {:locator, locator}, kind: :disabled} ->
        actual = session |> client_dom() |> ClientDOM.disabled?(locator)
        assert_truth!(expectation, actual, actual)

      %Expect{target: {:locator, locator}, kind: :editable} ->
        actual = session |> client_dom() |> ClientDOM.editable?(locator)
        assert_truth!(expectation, actual, actual)

      %Expect{target: {:locator, locator}, kind: :enabled} ->
        actual = not (session |> client_dom() |> ClientDOM.disabled?(locator))
        assert_truth!(expectation, actual, actual)

      %Expect{target: {:locator, locator}, kind: :focused} ->
        actual = session |> client_dom() |> ClientDOM.focused?(locator)
        assert_truth!(expectation, actual, actual)

      %Expect{target: {:locator, _locator}, kind: :checked, expected: :indeterminate} ->
        raise Fluffy.CapabilityError,
          capability: :indeterminate_checked_state,
          driver: :static,
          detail: "indeterminate is a browser-owned DOM property"

      %Expect{target: {:locator, locator}, kind: :checked, expected: expected} ->
        actual = session |> client_dom() |> ClientDOM.checked?(locator)
        assert_truth!(expectation, actual == (expected == :checked), actual)

      %Expect{target: {:locator, locator}, kind: :value, expected: expected} ->
        actual = session |> client_dom() |> ClientDOM.value(locator)
        assert_truth!(expectation, actual == expected, actual)

      %Expect{target: {:locator, locator}, kind: :values, expected: expected} ->
        actual = session |> client_dom() |> ClientDOM.selected_values(locator)
        assert_truth!(expectation, actual == expected, actual)

      %Expect{target: :page, kind: :url, expected: expected} ->
        actual = Session.current_page(session).url
        assert_truth!(expectation, URLMatcher.matches?(expected, actual), actual)

      %Expect{target: :page, kind: :title, expected: expected} ->
        actual = session |> Session.page_state() |> document() |> page_title()
        assert_truth!(expectation, Expect.title_matches?(expected, actual), actual)
    end

    session
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    client_dom = Map.fetch!(state, :client_dom)
    {client_dom, target} = ClientDOM.click(client_dom, locator)
    session = Session.put_page_state(session, %{state | client_dom: client_dom})

    case ClientDOM.phoenix_html_submission(client_dom, target) do
      submission when is_map(submission) ->
        {:navigate, session, Navigation.submission(submission)}

      nil ->
        case target do
          %{tag: tag, attributes: attributes} when tag in ["a", "area"] ->
            case attribute(attributes, "href") do
              href when is_binary(href) ->
                {:navigate, session,
                 Navigation.link(href,
                   download: attribute(attributes, "download")
                 )}

              nil ->
                session
            end

          submitter ->
            case ClientDOM.form_submission(client_dom, submitter) do
              nil -> session
              submission -> {:navigate, session, Navigation.submission(submission)}
            end
        end
    end
  end

  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
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
  def fill(%Session{} = session, %Locator{} = locator, value, options \\ []) do
    Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    client_dom = Map.fetch!(state, :client_dom)
    {client_dom, _target} = ClientDOM.fill(client_dom, locator, value)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, _source_paths, selected_files, options \\ []) do
    Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, options \\ []) do
    Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    client_dom = Map.fetch!(state, :client_dom)
    {client_dom, _target} = ClientDOM.set_checked(client_dom, locator, desired)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    {client_dom, _target} = state |> Map.fetch!(:client_dom) |> ClientDOM.select_option(locator, requested)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  @impl true
  def focus(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
    update_client_dom(session, &ClientDOM.focus(&1, locator))
  end

  @impl true
  def blur(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
    update_client_dom(session, &ClientDOM.blur(&1, locator))
  end

  @impl true
  def press(%Session{} = session, %Locator{} = locator, key, options \\ []) do
    Keyword.validate!(options, [:delay, :timeout])

    case key do
      key when key in ["Space", "Tab"] ->
        update_client_dom(session, &ClientDOM.press(&1, locator, key))

      "Enter" ->
        state = Session.page_state(session)
        client_dom = ClientDOM.focus(state.client_dom, locator)
        session = Session.put_page_state(session, %{state | client_dom: client_dom})

        case ClientDOM.implicit_submission(client_dom, locator) do
          nil ->
            session

          submission ->
            {:navigate, session, Navigation.submission(submission)}
        end
    end
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    case Session.page_state(session) do
      %{conn: %Plug.Conn{} = conn} ->
        case fun.(conn) do
          %Plug.Conn{} = returned_conn ->
            {:navigate, session, Navigation.static_conn(returned_conn)}

          other ->
            raise ArgumentError,
                  "Static unwrap callback must return an updated Plug.Conn, got: #{inspect(other)}"
        end

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

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp update_client_dom(session, fun) do
    state = Session.page_state(session)
    Session.put_page_state(session, %{state | client_dom: fun.(state.client_dom)})
  end

  defp assert_truth!(%Expect{} = expectation, passed?, actual) do
    if passed? == expectation.negated? do
      raise ExUnit.AssertionError,
        message: "Expected #{Expect.describe(expectation)}, got #{inspect(actual)}"
    end

    :ok
  end

  defp assert_count_expectation!(%Expect{negated?: false}, locator, expected, candidates) do
    Expectation.assert_count!(locator, expected, candidates)
  end

  defp assert_count_expectation!(%Expect{} = expectation, _locator, expected, candidates) do
    actual = length(candidates)
    assert_truth!(expectation, actual != expected, actual)
  end

  defp structurally_visible?(element) do
    attributes =
      case LazyHTML.attributes(element) do
        [attributes] -> attributes
        _other -> []
      end

    not List.keymember?(attributes, "hidden", 0) and
      String.downcase(attribute(attributes, "aria-hidden") || "false") != "true"
  end
end
