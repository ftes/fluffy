defmodule Fluffy.Driver.External do
  @moduledoc false

  # The page a Phoenix session ends on when the app sends it off-origin, by a
  # redirect or a link. Like `Phoenix.ConnTest.redirected_to/1`, it has a URL
  # but no document: URL expectations and `unwrap` work, and everything that
  # reads the document raises instead of passing or failing vacuously.

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Driver.Static
  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Session

  @impl true
  def validate_operation!(_session, :expect, [%Expect{target: :page, kind: :url}]), do: :ok
  def validate_operation!(_session, operation, _arguments) when operation in [:unwrap, :unwrap_and_return], do: :ok
  def validate_operation!(session, operation, _arguments), do: unsupported!(session, operation)

  @impl true
  def expect(session, %Expect{} = expectation), do: Static.expect(session, expectation)

  @impl true
  def unwrap(session, fun), do: session |> require_conn!() |> Static.unwrap(fun)

  @impl true
  def unwrap_and_return(session, fun), do: session |> require_conn!() |> Static.unwrap_and_return(fun)

  # validate_operation!/3 rejects these first.
  @impl true
  @spec click(Session.t(), Locator.t(), keyword()) :: no_return()
  def click(session, _locator, _options), do: unsupported!(session, :click)

  @impl true
  @spec submit(Session.t(), Locator.t(), keyword()) :: no_return()
  def submit(session, _locator, _options), do: unsupported!(session, :submit)

  @impl true
  @spec fill(Session.t(), Locator.t(), String.t(), keyword()) :: no_return()
  def fill(session, _locator, _value, _options), do: unsupported!(session, :fill)

  @impl true
  @spec clear(Session.t(), Locator.t(), keyword()) :: no_return()
  def clear(session, _locator, _options), do: unsupported!(session, :clear)

  @impl true
  @spec set_input_files(Session.t(), term(), term(), list(), keyword()) :: no_return()
  def set_input_files(session, _target, _source, _files, _options), do: unsupported!(session, :set_input_files)

  @impl true
  @spec set_checked(Session.t(), Locator.t(), boolean(), keyword()) :: no_return()
  def set_checked(session, _locator, _desired, _options), do: unsupported!(session, :set_checked)

  @impl true
  @spec select_option(Session.t(), Locator.t(), term(), keyword()) :: no_return()
  def select_option(session, _locator, _requested, _options), do: unsupported!(session, :select_option)

  @impl true
  @spec press(Session.t(), Locator.t(), String.t(), keyword()) :: no_return()
  def press(session, _locator, _key, _options), do: unsupported!(session, :press)

  @impl true
  @spec open_browser(Session.t(), (String.t() -> term())) :: no_return()
  def open_browser(session, _open_fun), do: unsupported!(session, :open_browser)

  defp require_conn!(session) do
    if is_nil(Session.page_state(session).conn), do: unsupported!(session, :unwrap)
    session
  end

  @spec unsupported!(Session.t(), atom()) :: no_return()
  defp unsupported!(session, operation) do
    raise Fluffy.CapabilityError,
      capability: :external_navigation,
      driver: :external,
      detail:
        "the app navigated away to #{Session.current_page(session).url}, which has no document or " <>
          "Plug.Conn for #{inspect(operation)}; only URL expectations work there"
  end
end
