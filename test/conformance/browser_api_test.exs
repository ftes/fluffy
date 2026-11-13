defmodule Fluffy.Conformance.BrowserAPITest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Playwright

  @tag driver: :playwright
  test "creates page handles sharing cookies without changing the selection" do
    session = start_session(:playwright)
    main = current_page(session)
    session = Playwright.add_cookies(session, [%{name: "token", value: "abc", url: Fluffy.TestServer.base_url()}])
    other = new_page(session)
    assert %Fluffy.Page{} = other
    refute other == main
    assert current_page(session) == main
    assert Enum.sort(pages(session)) == Enum.sort([main, other])

    other_session = switch_page(session, other)
    assert Playwright.evaluate(other_session, "document.visibilityState") == "visible"
    other_session = visit(other_session, "/harness")
    assert Playwright.evaluate(other_session, "document.cookie") =~ "token=abc"
    assert current_page(switch_page(other_session, main)) == main
    assert close_page(session, other) == session
    assert pages(session) == [main]
    assert_raise ArgumentError, ~r/closed/, fn -> switch_page(session, other) end
    assert :ok = close_session(session)
  end

  @tag driver: :playwright
  test "grants and clears permissions and sets the geolocation, returning the session" do
    session = :playwright |> start_session() |> visit("/harness")
    state = "navigator.permissions.query({name: 'geolocation'}).then(status => status.state)"

    assert Playwright.grant_permissions(session, ["geolocation"]) == session
    assert Playwright.evaluate(session, state) == "granted"

    assert Playwright.set_geolocation(session, %{latitude: 12.5, longitude: 41.9}) == session

    assert Playwright.evaluate(session, """
           new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(
             ({coords}) => resolve([coords.latitude, coords.longitude]), reject))
           """) == [12.5, 41.9]

    assert Playwright.clear_permissions(session) == session
    # WebKit reports the cleared state to a new document only.
    session = visit(session, "/harness")
    refute Playwright.evaluate(session, state) == "granted"
  end

  @tag driver: :playwright
  test "grant_permissions limits a grant to an origin" do
    session = :playwright |> start_session() |> visit("/harness")
    state = "navigator.permissions.query({name: 'geolocation'}).then(status => status.state)"

    Playwright.grant_permissions(session, ["geolocation"], origin: "https://elsewhere.example")
    refute Playwright.evaluate(session, state) == "granted"

    Playwright.grant_permissions(session, ["geolocation"], origin: Fluffy.TestServer.base_url())
    assert Playwright.evaluate(session, state) == "granted"
  end

  @tag driver: :playwright
  test "emulates going offline and back online, returning the session" do
    session = :playwright |> start_session() |> visit("/harness")
    fetch = "fetch(location.href, {cache: 'no-store'}).then(() => 'online', () => 'offline')"

    # The browser's network layer applies the change after the call returns.
    assert Playwright.set_offline(session, true) == session
    assert_eventually(fn -> Playwright.evaluate(session, fetch) == "offline" end)

    assert Playwright.set_offline(session, false) == session
    assert_eventually(fn -> Playwright.evaluate(session, fetch) == "online" end)
  end

  @tag driver: :playwright
  test "authenticates with HTTP credentials set at runtime, returning the session" do
    fixture =
      Fluffy.TestHTTPFixtures.register(fn request ->
        if List.keymember?(request.headers, "authorization", 0) do
          %{body: "<h1>Authenticated</h1>"}
        else
          %{status: 401, headers: [{"www-authenticate", ~s(Basic realm="fluffy")}], body: "Unauthorized"}
        end
      end)

    session = start_session(:playwright)
    assert Playwright.set_http_credentials(session, %{username: "user", password: "pass"}) == session

    session
    |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/secret"))
    |> expect("Authenticated" |> by_text() |> to_be_visible())

    assert [_, %{headers: headers} | _] = Fluffy.TestHTTPFixtures.requests(fixture)
    assert {"authorization", "Basic " <> _} = List.keyfind(headers, "authorization", 0)
  end

  @tag driver: :playwright
  test "navigates history and handles an empty history" do
    session = :playwright |> start_session() |> go_back() |> go_forward()
    session = session |> visit("/harness") |> visit("/chamber")
    session = session |> go_back() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/harness"))
    session |> go_forward() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber"))
  end

  @tag driver: :playwright
  test "exports and restores storage and filters cookies" do
    session = :playwright |> start_session() |> visit("/harness")

    session =
      Playwright.add_cookies(session, [
        %{name: "keep", value: "yes", url: Fluffy.TestServer.base_url()},
        %{name: "drop", value: "no", url: Fluffy.TestServer.base_url()}
      ])

    Playwright.evaluate(session, "localStorage.setItem('saved', 'value')")
    session = Playwright.clear_cookies(session, name: ~r/^drop$/)
    assert Enum.map(Playwright.cookies(session), & &1.name) == ["keep"]
    path = Path.join(System.tmp_dir!(), "fluffy-storage-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)
    state = Playwright.storage_state(session, path: path)
    assert Jason.decode!(File.read!(path)) == Jason.decode!(Jason.encode!(state))
    restored = :playwright |> start_session(browser_context: [storage_state: state]) |> visit("/harness")
    assert Playwright.evaluate(restored, "localStorage.getItem('saved')") == "value"
    assert Playwright.evaluate(restored, "document.cookie") =~ "keep=yes"
    from_file = :playwright |> start_session(browser_context: [storage_state: path]) |> visit("/harness")
    assert Playwright.evaluate(from_file, "localStorage.getItem('saved')") == "value"
    assert Playwright.cookies(Playwright.clear_cookies(session)) == []
  end

  @tag driver: :playwright
  test "cookie and storage maps use Playwright's camelCase keys" do
    session = :playwright |> start_session() |> visit("/harness")
    url = Fluffy.TestServer.base_url()

    session = Playwright.add_cookies(session, [%{name: "token", value: "abc", url: url, httpOnly: true, sameSite: "Lax"}])
    assert [%{name: "token", httpOnly: true, sameSite: "Lax"}] = Playwright.cookies(session)
    assert [%{name: "token"}] = Playwright.cookies(session, [url])

    # Fluffy 0.8 options would reach Playwright as URLs.
    for options <- [[urls: [url]], [timeout: 1_000]] do
      assert_raise ArgumentError, ~r/cookies\/2 takes the URL list, not the options/, fn ->
        Playwright.cookies(session, options)
      end
    end

    assert %{cookies: [%{httpOnly: true}], origins: _origins} = Playwright.storage_state(session)

    # Playwright would drop these silently.
    for {key, camel_case} <- [http_only: :httpOnly, same_site: :sameSite], cookie_key <- [key, Atom.to_string(key)] do
      assert_raise ArgumentError,
                   ~r/#{inspect(cookie_key)} is not a Playwright cookie field; use #{inspect(camel_case)}/,
                   fn ->
                     Playwright.add_cookies(session, [%{:name => "old", :value => "x", :url => url, cookie_key => true}])
                   end
    end
  end

  @tag driver: :playwright
  test "hover, drag, and typing emit native browser events" do
    session =
      Fluffy.session_for_html(:playwright, """
      <button onmouseover="this.textContent='Hovered'">Hover me</button>
      <input aria-label="Text" onkeydown="window.keys=(window.keys||0)+1">
      <div draggable="true" id="source">Drag me</div>
      <div id="target" style="margin-top:40px;width:200px;height:100px" ondragover="event.preventDefault()" ondrop="this.textContent='Dropped'">Target</div>
      """)

    session = session |> hover(by_role(:button)) |> expect("Hovered" |> by_text() |> to_be_visible())
    session = press_sequentially(session, by_label("Text"), "abc", delay: 1)
    assert Playwright.evaluate(session, "window.keys") == 3

    session
    |> expect("Text" |> by_label() |> to_have_value("abc"))
    |> drag_to(by_css("#source"), by_css("#target"))
    |> expect("Dropped" |> by_text() |> to_be_visible())
  end

  @tag driver: :playwright
  test "typing is strict and reconciles navigation" do
    session = Fluffy.session_for_html(:playwright, "<input><input>")
    error = assert_raise Fluffy.OperationError, fn -> press_sequentially(session, by_css("input"), "x", timeout: 100) end
    assert error.operation == :press_sequentially
    session = Fluffy.set_html(session, ~s(<input oninput="location.href='/chamber'">))

    session
    |> press_sequentially(by_css("input"), "x")
    |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber"))
  end

  @tag driver: :playwright
  test "history reconciles same-document navigation and leaves an empty history unchanged" do
    session = start_session(:playwright)
    session = switch_page(session, new_page(session))
    assert go_back(session) == session
    assert go_forward(session) == session
    session = session |> visit("/harness") |> visit("/harness#other")
    session = session |> go_back() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/harness"))
    session |> go_forward() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/harness#other"))
  end

  @tag driver: :playwright
  test "history without an entry keeps a URL a script changed" do
    session = :playwright |> start_session() |> visit("/harness")
    Playwright.evaluate(session, "history.replaceState(null, '', '/harness?replaced')")
    session = go_forward(session)

    assert Fluffy.Page.url(current_page(session)) == Fluffy.TestServer.base_url() <> "/harness?replaced"
    expect(session, page_to_have_url(Fluffy.TestServer.base_url() <> "/harness?replaced"))
  end

  @tag driver: :playwright
  test "history validates its timeout like other actions" do
    session = start_session(:playwright)
    assert_raise NimbleOptions.ValidationError, ~r/:timeout/, fn -> go_back(session, timeout: :forever) end
    assert_raise NimbleOptions.ValidationError, ~r/:timeout/, fn -> go_forward(session, timeout: -1) end
  end

  test "browser operations reject Phoenix sessions" do
    session = start_session(:phoenix)

    for operation <- [
          fn -> new_page(session) end,
          fn -> go_back(session) end,
          fn -> go_forward(session) end,
          fn -> hover(session, by_css("button")) end,
          fn -> drag_to(session, by_css("a"), by_css("b")) end,
          fn -> press_sequentially(session, by_css("input"), "abc") end,
          fn -> Playwright.cookies(session) end,
          fn -> Playwright.add_cookies(session, []) end,
          fn -> Playwright.clear_cookies(session) end,
          fn -> Playwright.storage_state(session) end,
          fn -> Playwright.grant_permissions(session, ["geolocation"]) end,
          fn -> Playwright.clear_permissions(session) end,
          fn -> Playwright.set_geolocation(session, %{latitude: 1, longitude: 2}) end,
          fn -> Playwright.set_offline(session, true) end,
          fn -> Playwright.set_http_credentials(session, %{username: "user", password: "pass"}) end
        ] do
      assert_raise Fluffy.CapabilityError, operation
    end

    for history <- [&go_back/1, &go_forward/1] do
      error = assert_raise Fluffy.CapabilityError, fn -> history.(session) end
      assert error.capability == :browser_history
    end

    error = assert_raise Fluffy.CapabilityError, fn -> Playwright.set_offline(session, true) end
    assert Fluffy.Capability.status(error.capability, :static) == :browser_only

    assert :ok = close_session(session)
  end
end
