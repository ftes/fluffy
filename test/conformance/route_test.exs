defmodule Fluffy.Conformance.RouteTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Playwright
  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestWeb.Endpoint
  alias PlaywrightEx.Route
  alias PlaywrightEx.Test.TestInfo

  @fetch "url => fetch(url).then(response => response.text(), () => 'rejected')"
  @pending "Promise.race([window.result, new Promise(resolve => setTimeout(() => resolve('pending'), 200))])"

  describe "answers" do
    @tag driver: :playwright
    test "fulfill answers without reaching the server, and a 2-arity handler gets the request" do
      {session, fixture} = session()
      owner = self()

      route(session, "**/api", fn route, request ->
        send(owner, {:request, request})
        Route.fulfill!(route, status: 201, headers: %{"x-routed" => "yes"}, json: %{name: "routed"})
      end)

      assert Playwright.evaluate(
               session,
               "url => fetch(url, {method: 'POST', body: 'payload'}).then(async r => [r.status, r.headers.get('x-routed'), await r.json()])",
               url(fixture, "/api")
             ) == [201, "yes", %{"name" => "routed"}]

      assert_receive {:request, %PlaywrightEx.Request{} = request}
      assert {PlaywrightEx.Request.method(request), PlaywrightEx.Request.post_data(request)} == {"POST", "payload"}
      assert PlaywrightEx.Request.url(request) == url(fixture, "/api")
      assert fixture |> TestHTTPFixtures.requests() |> Enum.count(&(&1.path == "/api")) == 0
    end

    @tag driver: :playwright
    test "continue reaches the server with overrides" do
      {session, fixture} = session()

      route(session, "**/api", fn route ->
        Route.continue!(route,
          headers: Map.put(PlaywrightEx.Request.headers(Route.request(route)), "x-fluffy-routed", "yes")
        )
      end)

      assert fetch(session, fixture) == ~s({"name":"server"})
      assert [%{headers: headers}] = Enum.filter(TestHTTPFixtures.requests(fixture), &(&1.path == "/api"))
      assert {"x-fluffy-routed", "yes"} in headers
    end

    @tag driver: :playwright
    @tag capture_log: true
    test "abort fails the request" do
      {session, fixture} = session()
      route(session, "**/api", fn route -> Route.abort!(route, "accessdenied") end)
      assert fetch(session, fixture) == "rejected"
    end

    @tag driver: :playwright
    test "a handler can pass the route on, so the test asserts a loading state and answers it" do
      {session, fixture} = session()
      test = self()
      route(session, TestHTTPFixtures.path(fixture, "/api/prophet"), &send(test, {:held, &1}))

      session
      |> visit(TestHTTPFixtures.path(fixture, "/prophet"))
      |> expect("Loading the Daily Prophet" |> by_text() |> to_be_visible())

      assert_receive {:held, %Route{} = held}, 5_000
      assert Route.fulfill!(held, json: %{title: "Evening Edition"}) == :ok

      expect(session, "Daily Prophet: Evening Edition" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "fulfill serves a file" do
      {session, fixture} = session()
      route(session, "**/api", fn route -> Route.fulfill!(route, path: "mix.exs") end)
      assert fetch(session, fixture) =~ "defmodule"
    end
  end

  describe "url" do
    @tag driver: :playwright
    test "a glob, a regular expression and a predicate each match" do
      {session, fixture} = session()
      answer = fn body -> fn route -> Route.fulfill!(route, body: body) end end

      route(session, "**/glob", answer.("glob"))
      route(session, ~r{/regex$}, answer.("regex"))
      route(session, &String.ends_with?(&1, "/predicate?a=1"), answer.("predicate"))

      assert fetch(session, fixture, "/glob") == "glob"
      assert fetch(session, fixture, "/regex") == "regex"
      assert fetch(session, fixture, "/predicate?a=1") == "predicate"
      assert fetch(session, fixture, "/predicate?a=2") =~ "server"
    end

    @tag driver: :playwright
    test "a glob resolves against the session's base_url" do
      {session, fixture} = session()
      route(session, TestHTTPFixtures.path(fixture, "/api"), fn route -> Route.fulfill!(route, body: "relative") end)
      assert fetch(session, fixture) == "relative"
    end
  end

  describe "precedence" do
    @tag driver: :playwright
    test "the last registered route wins" do
      {session, fixture} = session()
      route(session, "**/api", fn route -> Route.fulfill!(route, body: "first") end)
      route(session, "**/api", fn route -> Route.fulfill!(route, body: "second") end)
      assert fetch(session, fixture) == "second"
    end

    @tag driver: :playwright
    test "fallback hands the request to the route registered before, then to the server" do
      {session, fixture} = session()
      owner = self()

      route(session, "**/api", fn route ->
        send(owner, {:first, PlaywrightEx.Request.headers(Route.request(route))["x-fallback"]})
        Route.fulfill!(route, body: "first")
      end)

      route(session, "**/api", fn route ->
        Route.fallback!(route, headers: Map.put(PlaywrightEx.Request.headers(Route.request(route)), "x-fallback", "yes"))
      end)

      assert fetch(session, fixture) == "first"
      assert_receive {:first, "yes"}

      unroute(session, "**/api")
      route(session, "**/api", &Route.fallback!/1)
      assert fetch(session, fixture) == ~s({"name":"server"})
    end

    @tag driver: :playwright
    test "times: expires a route, leaving the earlier one" do
      {session, fixture} = session()
      route(session, "**/api", fn route -> Route.fulfill!(route, body: "always") end)
      route(session, "**/api", fn route -> Route.fulfill!(route, body: "once") end, times: 1)
      assert fetch(session, fixture) == "once"
      assert fetch(session, fixture) == "always"
    end

    @tag driver: :playwright
    test "unroute removes a url's routes, or only one handler's, and accepts an equal matcher" do
      {session, fixture} = session()
      first = fn route -> Route.fulfill!(route, body: "first") end
      second = fn route -> Route.fulfill!(route, body: "second") end
      route(session, ~r{/api$}, first)
      route(session, ~r{/api$}, second)

      unroute(session, ~r{/api$}, second)
      assert fetch(session, fixture) == "first"

      unroute(session, Regex.compile!("/api$"))
      assert fetch(session, fixture) == ~s({"name":"server"})
    end
  end

  describe "a handler" do
    @tag driver: :playwright
    test "runs outside the test process, with $callers through it" do
      {session, fixture} = session()
      owner = self()

      route(session, "**/api", fn route ->
        send(owner, {:handler, self(), Process.get(:"$callers")})
        Route.fulfill!(route, body: "ok")
      end)

      fetch(session, fixture)
      assert_receive {:handler, pid, callers}
      assert pid != owner
      assert owner in callers
    end

    @tag driver: :playwright
    test "one awaiting Playwright does not delay another" do
      {session, fixture} = session()

      route(session, "**/slow", fn route ->
        Route.fulfill!(route, response: Route.fetch!(route, url: url(fixture, "/held")))
      end)

      route(session, "**/fast", fn route -> Route.fulfill!(route, body: "fast") end)

      Playwright.evaluate(
        session,
        "url => { window.slow = fetch(url).then(r => r.text()); return true }",
        url(fixture, "/slow")
      )

      assert_receive {:held, server}, 5_000
      assert fetch(session, fixture, "/fast") == "fast"
      send(server, :release)
      assert Playwright.evaluate(session, "window.slow") == "held"
    end

    @tag driver: :playwright
    test "that raises fails the test and leaves its request pending, as in Playwright" do
      {session, fixture} = session()
      route(session, "**/api", fn _route -> raise "boom" end)
      start_held_fetch(session, fixture)

      assert [{:error, %RuntimeError{message: "boom"}, [_ | _]}] = take_test_errors()
      assert Playwright.evaluate(session, @pending) == "pending"
    end

    @tag driver: :playwright
    test "that answers twice fails the test" do
      {session, fixture} = session()

      # Two simultaneous answers: the second comes back from the server like this.
      route(session, "**/api", fn route ->
        Route.fulfill!(route, body: "first")
        raise %PlaywrightEx.PlaywrightError{message: "route.fulfill: Route is already handled!"}
      end)

      assert fetch(session, fixture) == "first"
      assert [{:error, %PlaywrightEx.PlaywrightError{}, [_ | _]}] = take_test_errors()
    end

    @tag driver: :playwright
    test "that a closed target fails gets Playwright's hint and fails the test" do
      {session, fixture} = session()

      # Raised by a call on a page or context closed under the handler.
      route(session, "**/api", fn _route ->
        raise %PlaywrightEx.TargetClosedError{message: "Target page, context or browser has been closed"}
      end)

      start_held_fetch(session, fixture)
      assert [{:error, %PlaywrightEx.TargetClosedError{message: message}, [_ | _]}] = take_test_errors()
      assert message =~ ~s("Target page, context or browser has been closed" while running route callback.)
      assert message =~ "unrouteAll({ behavior: 'ignoreErrors' })"
    end

    @tag driver: :playwright
    test "that returns without answering leaves the action to fail at its own timeout" do
      session = start_session(:playwright, base_url: Fluffy.TestServer.base_url(), timeout: 500)
      fixture = TestHTTPFixtures.register(fn _request -> %{body: "<h1>Never</h1>"} end)
      route(session, "**/never", fn _route -> :ok end)

      started = System.monotonic_time(:millisecond)
      error = assert_raise Fluffy.OperationError, fn -> visit(session, TestHTTPFixtures.path(fixture, "/never")) end
      assert %PlaywrightEx.TimeoutError{} = error.cause
      assert System.monotonic_time(:millisecond) - started < 5_000
    end
  end

  describe "cleanup" do
    @tag driver: :playwright
    test "an answer after the session closed fails nothing, as in Playwright" do
      {session, fixture} = session()
      test = self()
      route(session, "**/api", &send(test, {:route, &1}))

      Playwright.evaluate(session, "url => { fetch(url).catch(() => {}); return true }", url(fixture, "/api"))
      assert_receive {:route, route}, 5_000

      close_session(session)
      assert Route.fulfill!(route, body: "late") == :ok
      refute_test_errors()
    end

    @tag driver: :playwright
    test "a route outlives the process that registered it" do
      {session, fixture} = session()

      fn -> route(session, "**/api", fn route -> Route.fulfill!(route, body: "routed") end) end
      |> Task.async()
      |> Task.await()

      assert fetch(session, fixture) == "routed"
    end

    @tag driver: :playwright
    test "a request reaching a removed route falls back to the next one" do
      {session, fixture} = session()
      route(session, "**/api", fn route -> Route.fulfill!(route, body: "earlier") end)
      handler = fn route -> Route.fulfill!(route, body: "removed") end
      route(session, "**/api", handler)

      # Queue requests behind the removal; each is answered, by whichever route it reaches.
      Playwright.evaluate(
        session,
        "url => { window.results = Promise.all([...Array(20)].map(() => fetch(url).then(r => r.text()))); return true }",
        url(fixture, "/api")
      )

      unroute(session, "**/api", handler)

      assert session |> Playwright.evaluate("window.results") |> Enum.uniq() |> Enum.all?(&(&1 in ["earlier", "removed"]))
    end

    @tag driver: :playwright
    test "unrouting the last route frees a held request, whose late answer fails, as in Playwright" do
      {session, fixture} = session()
      test = self()
      route(session, "**/api", &send(test, {:route, &1}))

      start_held_fetch(session, fixture)
      assert_receive {:route, route}, 5_000
      unroute(session, "**/api")

      assert Playwright.evaluate(session, "window.result") == ~s({"name":"server"})
      assert_raise PlaywrightEx.PlaywrightError, ~r/Route is already handled!/, fn -> Route.fulfill!(route) end
    end

    @tag driver: :playwright
    test "unroute_all with behavior: :wait waits for a held route's answer, which the request gets" do
      {session, fixture} = session()
      test = self()
      route(session, "**/api", &send(test, {:route, &1}))

      start_held_fetch(session, fixture)
      assert_receive {:route, route}, 5_000
      unrouting = Task.async(fn -> Playwright.unroute_all(session, behavior: :wait) end)
      refute Task.yield(unrouting, 200)

      Route.fulfill!(route, body: "finished")
      assert Task.await(unrouting) == session
      assert Playwright.evaluate(session, "window.result") == "finished"
    end

    @tag driver: :playwright
    test "unroute_all with behavior: :ignore_errors does not wait, and a running handler's failure fails nothing" do
      {session, fixture} = session()

      route(session, "**/api", fn route ->
        Route.fetch!(route, url: url(fixture, "/held"))
        raise "late"
      end)

      start_held_fetch(session, fixture)
      assert_receive {:held, server}, 5_000
      assert Playwright.unroute_all(session, behavior: :ignore_errors) == session

      send(server, :release)
      assert Playwright.evaluate(session, "window.result") == ~s({"name":"server"})
      refute_test_errors()
    end
  end

  describe "navigation" do
    @tag driver: :playwright
    test "a fulfilled document on a link is adopted, and later actions continue" do
      {session, fixture} = session()
      child = url(fixture, "/child")

      route(session, "**/child", fn route ->
        Route.fulfill!(route,
          content_type: "text/html",
          body: ~s(<!doctype html><title>Routed</title><h1>Routed child</h1><a href="next">Next</a>)
        )
      end)

      session
      |> click(by_role(:link, name: "Child"))
      |> expect(:heading |> by_role(name: "Routed child") |> to_be_visible())
      |> page_to_have_url_ok(child)
      |> click(by_role(:link, name: "Next"))
      |> expect(:heading |> by_role(name: "Server next") |> to_be_visible())
      |> page_to_have_url_ok(url(fixture, "/next"))
    end

    @tag driver: :playwright
    test "a fulfilled document on a visit is adopted" do
      {session, fixture} = session()

      route(session, "**/fulfilled", fn route ->
        Route.fulfill!(route, content_type: "text/html", body: "<!doctype html><h1>Fulfilled visit</h1>")
      end)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/fulfilled"))
      |> expect(:heading |> by_role(name: "Fulfilled visit") |> to_be_visible())
      |> page_to_have_url_ok(url(fixture, "/fulfilled"))
    end

    @tag driver: :playwright
    @tag capture_log: true
    test "an aborted navigation fails the visit" do
      {session, fixture} = session()
      route(session, "**/blocked", fn route -> Route.abort!(route) end)

      error = assert_raise Fluffy.OperationError, fn -> visit(session, TestHTTPFixtures.path(fixture, "/blocked")) end
      assert %PlaywrightEx.PlaywrightError{} = error.cause
    end

    @tag driver: :playwright
    test "a route over every request leaves a LiveView working" do
      session =
        start_session(:playwright, base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)

      route(session, "**/*", &Route.continue!/1)

      session
      |> visit("/live/three-heads")
      |> click(by_role(:button, name: "Play the flute"))
      |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "a popup's requests are routed, since routes are context-scoped" do
      {session, _fixture} = session()

      route(session, "**/popup-child", fn route ->
        Route.fulfill!(route, content_type: "text/html", body: "<!doctype html><h1>Routed popup</h1>")
      end)

      popup = wait_for(session, Event.popup())
      click(session, by_role(:link, name: "Popup"))

      session
      |> switch_page(await(popup))
      |> expect(:heading |> by_role(name: "Routed popup") |> to_be_visible())
    end
  end

  test "Phoenix sessions raise a capability error" do
    session = start_session(:phoenix, endpoint: Endpoint)
    handler = fn route -> Route.continue!(route) end

    assert_raise Fluffy.CapabilityError, ~r/:routing requires a Playwright session/, fn ->
      route(session, "**/*", handler)
    end

    assert_raise Fluffy.CapabilityError, ~r/:routing requires a Playwright session/, fn ->
      unroute(session, "**/*")
    end
  end

  # A failing handler fails the test, as in Playwright: take its errors back, so this one passes.
  defp take_test_errors(attempts \\ 100) do
    case TestInfo.take_errors(self()) do
      [] when attempts > 0 ->
        Process.sleep(50)
        take_test_errors(attempts - 1)

      errors ->
        errors
    end
  end

  defp refute_test_errors do
    Process.sleep(200)
    assert TestInfo.take_errors(self()) == []
  end

  defp page_to_have_url_ok(session, url), do: expect(session, page_to_have_url(url))

  defp url(fixture, suffix), do: TestHTTPFixtures.url(fixture, suffix)

  defp start_held_fetch(session, fixture) do
    Playwright.evaluate(
      session,
      "url => { window.result = fetch(url).then(r => r.text()); return true }",
      url(fixture, "/api")
    )
  end

  defp fetch(session, fixture, suffix \\ "/api") do
    Playwright.evaluate(session, @fetch, url(fixture, suffix))
  end

  defp session do
    test = self()

    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/held" ->
            send(test, {:held, self()})

            receive do
              :release -> %{body: "held"}
            end

          "/start" ->
            %{
              body: """
              <!doctype html><html><body>
              <a href="child">Child</a>
              <a href="popup-child" target="_blank">Popup</a>
              </body></html>
              """
            }

          "/next" ->
            %{body: "<h1>Server next</h1>"}

          "/prophet" ->
            %{
              body: """
              <!doctype html><html><body>
              <p id="prophet">Loading the Daily Prophet</p>
              <script>
                fetch("api/prophet").then(r => r.json()).then(({title}) => {
                  document.getElementById("prophet").textContent = "Daily Prophet: " + title
                })
              </script>
              </body></html>
              """
            }

          _api ->
            %{headers: [{"content-type", "application/json"}], body: ~s({"name":"server"})}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end
end
