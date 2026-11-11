defmodule Fluffy.Driver.External do
  @moduledoc false

  # The page a Phoenix session ends on when the app sends it off-origin, by a
  # link, form or redirect. Like `Phoenix.ConnTest.redirected_to/1`, it has a
  # URL but no document: URL expectations work, and everything else raises
  # instead of passing or failing vacuously.

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Driver.Static
  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Session

  @impl true
  def validate_operation!(_session, :expect, [%Expect{target: :page, kind: :url}]), do: :ok
  def validate_operation!(session, operation, _arguments), do: unsupported!(session, operation)

  @impl true
  def expect(session, %Expect{} = expectation), do: Static.expect(session, expectation)

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

  @impl true
  @spec unwrap(Session.t(), (term() -> term())) :: no_return()
  def unwrap(session, _fun), do: unsupported!(session, :unwrap)

  @impl true
  @spec unwrap_and_return(Session.t(), (term() -> term())) :: no_return()
  def unwrap_and_return(session, _fun), do: unsupported!(session, :unwrap_and_return)

  @spec unsupported!(Session.t(), atom()) :: no_return()
  defp unsupported!(session, operation) do
    raise Fluffy.CapabilityError,
      capability: :external_navigation,
      driver: :external,
      detail:
        "the app navigated away to #{Session.current_page(session).url}, which has nothing to " <>
          "#{inspect(operation)}; only URL expectations work there"
  end
end
