defmodule Fluffy.Conformance.HTMLIsolationTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "isolates parallel injected documents with #{driver}", %{driver: driver} do
      [{"Alpha", "Beta"}, {"Beta", "Alpha"}]
      |> Enum.map(fn {present, absent} ->
        Task.async(fn ->
          session =
            session_for_html(driver, "<button>#{present}</button>", base_url: Fluffy.TestServer.base_url())

          try do
            session
            |> expect(count(by_role(:button, name: present), 1))
            |> expect(count(by_role(:button, name: absent), 0))
          after
            Fluffy.Backend.close_session(session)
          end
        end)
      end)
      |> Task.await_many(30_000)
    end
  end
end
