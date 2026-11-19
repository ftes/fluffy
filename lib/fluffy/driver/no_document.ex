defmodule Fluffy.Driver.NoDocument do
  @moduledoc false

  # A Phoenix page without a document: the session's page before its first visit
  # (`:unvisited`), or the page the app sent off-origin by a link, form or redirect
  # (`:external`). Like `Phoenix.ConnTest.redirected_to/1`, an external page has a URL
  # but no document, so URL expectations work there. Everything else raises instead of
  # passing or failing vacuously. Playwright starts at `about:blank`, where an action
  # waits for an element that never comes; Phoenix has no page to wait on.

  alias Fluffy.Driver.Static
  alias Fluffy.Expect
  alias Fluffy.Session

  def validate_operation!(session, operation, arguments) do
    if Session.current_driver(session) == :external and url_expectation?(operation, arguments),
      do: :ok,
      else: unsupported!(session, operation)
  end

  defp url_expectation?(:expect, [%Expect{target: :page, kind: :url}]), do: true
  defp url_expectation?(_operation, _arguments), do: false

  @spec unsupported!(Session.t(), atom()) :: no_return()
  def unsupported!(session, operation) do
    case Session.current_page(session) do
      %{driver: :external, url: url} ->
        raise Fluffy.CapabilityError,
          capability: :external_navigation,
          driver: :external,
          detail:
            "the app navigated away to #{url}, which has nothing to #{inspect(operation)}; only URL expectations work there"

      %{driver: :unvisited} ->
        raise ArgumentError, "there is no page for #{inspect(operation)} before the first visit/2; visit a page first"
    end
  end

  def expect(session, %Expect{} = expectation), do: Static.expect(session, expectation)
end
