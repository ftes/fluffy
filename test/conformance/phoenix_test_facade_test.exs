defmodule Fluffy.Conformance.PhoenixTestFacadeTest do
  use Fluffy.TestCase, async: true

  import Fluffy.PhoenixTest

  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.PhoenixTest.Session
  alias Fluffy.TestWeb.Endpoint

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "exact text assertions preserve CSS candidates, counts, positions, and scopes with #{driver}" do
      unquote(driver)
      |> Fluffy.session_for_html("""
      <table><tr><th>Day type</th><th> Day </th><th hidden><span>Day</span></th><th>day</th></tr></table>
      <div><span>Day</span> type</div>
      """)
      |> assert_has("th", text: "Day", exact: true, count: 2)
      |> assert_has("th", "Day", exact: true, at: 2)
      |> refute_has("th", "Day", exact: true, at: 1)
      |> refute_has("div", text: "Day", exact: true)
      |> within("table", fn session ->
        session
        |> assert_has("th[hidden]", text: "Day", exact: true)
        |> refute_has("th", text: "DAY", exact: true)
      end)
    end

    @tag driver: driver
    test "selected option labels track current selection with #{driver}" do
      unquote(driver)
      |> Fluffy.session_for_html("""
      <section id="plans"><select aria-label="Plan">
        <option value="free">Free</option>
        <optgroup label="Paid"><option value="pro" label="Paid plan">Professional</option></optgroup>
      </select></section>
      <select aria-label="Plan"><option>Other</option></select>
      """)
      |> within("#plans", fn session ->
        session
        |> assert_has("select", label: "Plan", selected: "Free")
        |> refute_has("select", selected: "Professional")
        |> select("Plan", option: "Paid plan")
        |> assert_has("select", label: "Plan", selected: " Professional  ")
        |> refute_has("select", selected: "Free")
        |> refute_has("select", selected: "Profession")
        |> refute_has("select", selected: "Paid plan")
        |> refute_has("select", selected: "professional")
      end)
    end

    @tag driver: driver
    test "CSS clicks match ARIA labels and retain text matches with #{driver}" do
      fixture =
        Fluffy.TestHTTPFixtures.register(%{
          body: """
          <main>
            <a href="?delete" aria-label="Delete"><span style="display:inline-block;width:20px;height:20px"></span></a>
            <a href="?other" aria-label="Delete other"><span style="display:inline-block;width:20px;height:20px"></span></a>
            <form><button name="action" value="save" aria-labelledby="save-label"><span style="display:inline-block;width:20px;height:20px"></span></button></form>
            <span id="save-label">Save</span>
          </main>
          <a href="?outside" aria-label="Delete"></a>
          """
        })

      path = Fluffy.TestHTTPFixtures.path(fixture)

      unquote(if driver == :static, do: :phoenix, else: driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit(path)
      |> within("main", fn session -> click_link(session, "a", "Delete", exact: true) end)
      |> assert_path(path, query_params: %{"delete" => ""})
      |> within("main", fn session -> click_button(session, "button", "Save") end)
      |> assert_path(path, query_params: %{"action" => "save"})
    end

    @tag driver: driver
    test "locator unions deduplicate matches and retain document order with #{driver}" do
      native = Fluffy.session_for_html(unquote(driver), "<p id='first'>One</p><p>Two</p>")
      locator = Locator.or_(Locator.by_text("Two"), Locator.by_css("p"))
      Expect.expect(native, Expect.to_have_count(locator, 2))
      Expect.expect(native, Expect.to_have_count(Locator.and_(Locator.first(locator), Locator.by_css("#first")), 1))
    end

    @tag driver: driver
    test "form actions delegate String.Chars values to native actions with #{driver}" do
      unquote(driver)
      |> Fluffy.session_for_html("""
      <input aria-label="Value">
      <select aria-label="Choice" multiple>
        <option value="empty"></option>
        <option value="number">42</option>
        <option value="date">2026-09-30</option>
        <option value="custom">custom:&lt;tag&gt;&amp;</option>
      </select>
      """)
      |> fill_in("Value", with: 42)
      |> assert_has("input", value: "42")
      |> fill_in("input", "Value", with: %Fluffy.TestFormValue{value: "<tag>&"})
      |> assert_has("input", value: "custom:<tag>&")
      |> fill_in("Value", with: nil)
      |> assert_has("input", value: "")
      |> select("Choice", option: nil)
      |> tap(fn %Session{session: fluffy_session} ->
        Expect.expect(fluffy_session, Expect.to_have_values(Locator.by_label("Choice"), ["empty"]))
      end)
      |> select("Choice", option: 42)
      |> tap(fn %Session{session: fluffy_session} ->
        Expect.expect(fluffy_session, Expect.to_have_values(Locator.by_label("Choice"), ["number"]))
      end)
      |> select("select", ~D[2026-09-30], from: "Choice")
      |> tap(fn %Session{session: fluffy_session} ->
        Expect.expect(fluffy_session, Expect.to_have_values(Locator.by_label("Choice"), ["date"]))
      end)
      |> select(%Fluffy.TestFormValue{value: "<tag>&"}, from: "Choice")
      |> tap(fn %Session{session: fluffy_session} ->
        Expect.expect(fluffy_session, Expect.to_have_values(Locator.by_label("Choice"), ["custom"]))
      end)
      |> select("select", "Choice", option: [42, ~D[2026-09-30], ~c"custom:<tag>&"])
      |> tap(fn %Session{session: fluffy_session} ->
        Expect.expect(fluffy_session, Expect.to_have_values(Locator.by_label("Choice"), ["number", "date", "custom"]))
      end)
    end

    @tag driver: driver
    test "presence, text, positions, counts, and field predicates with #{driver}" do
      session =
        Fluffy.session_for_html(unquote(driver), """
        <p hidden>Hidden notice</p><p>Visible notice</p><p>Other</p>
        <label for="email">Email address</label><input id="email" value="reader">
        <label for="other">Email address</label><input id="other" value="other">
        <label for="sub">Subscribe now</label><input id="sub" type="checkbox" checked>
        """)

      returned =
        session
        |> assert_has("p")
        |> assert_has("p", count: 3)
        |> assert_has("p", "notice", count: 2)
        |> assert_has("p", text: "Hidden", at: 1, exact: false)
        |> refute_has("p", "Hidden", at: 2)
        |> refute_has("p", count: 2)
        |> refute_has("#missing")
        |> assert_has("#email", value: "reader", label: "Email")
        |> refute_has("#email", value: "wrong")
        |> assert_has("#sub", checked: true, label: "Subscribe")
        |> refute_has("#sub", checked: false, label: "Subscribe now", exact: true)

      assert returned.session == session

      assert_raise ExUnit.AssertionError, fn -> refute_has(session, "[hidden]", timeout: 0) end
      assert_raise ExUnit.AssertionError, fn -> assert_has(session, "p", "Hidden", at: 2, timeout: 0) end

      assert_raise ExUnit.AssertionError, fn ->
        assert_has(session, "#email", value: "reader", label: "Email", exact: true, timeout: 0)
      end
    end

    @tag driver: driver
    test "labels filter presence, absence, counts, text, and positions with #{driver}" do
      session =
        Fluffy.session_for_html(unquote(driver), """
        <input aria-label="Outside only">
        <section>
          <input aria-label="Other">
          <label for="day">Crew reminder day</label><select id="day"><option>Monday</option></select>
          <input aria-label="Crew reminder time">
          <input aria-label="Crew reminder time" hidden>
          <button aria-label="Delete schedule">Delete</button>
          <a href="/edit" aria-label="Edit schedule">Edit</a>
        </section>
        """)

      session
      |> assert_has("select", label: "Crew reminder day")
      |> refute_has("input", label: "Crew reminder day")
      |> refute_has("select", label: "Missing")
      |> assert_has("input", label: "Crew reminder time")
      |> assert_has("input[hidden]", label: "Crew reminder time")
      |> assert_has("input", label: "Crew reminder", count: 2)
      |> refute_has("input", label: "Crew reminder", count: 1)
      |> assert_has("input", label: "Crew reminder time", exact: true, at: 2)
      |> refute_has("input", label: "Crew reminder time", at: 3)
      |> refute_has("select", label: "Crew reminder", exact: true)
      |> assert_has("select", label: "Crew reminder", text: "Monday")
      |> refute_has("select", label: "Crew reminder", text: "Tuesday")
      |> assert_has("button", label: "Delete schedule", exact: true)
      |> assert_has("a", label: "Edit schedule")
      |> refute_has("a", label: "Missing schedule")
      |> within("section", fn scoped ->
        scoped
        |> assert_has("select", label: "Crew reminder day")
        |> refute_has("input", label: "Outside only")
      end)

      assert_raise ExUnit.AssertionError, fn ->
        assert_has(session, "input", label: "Crew reminder day", timeout: 0)
      end

      assert_raise ExUnit.AssertionError, fn ->
        refute_has(session, "input[hidden]", label: "Crew reminder time", timeout: 0)
      end
    end

    @tag driver: driver
    test "at: positions among label-matching controls with #{driver}" do
      unquote(driver)
      |> Fluffy.session_for_html("""
      <label for="a">Other</label><input id="a" value="a">
      <label for="b">Email</label><input id="b" value="b">
      <label for="c">Email</label><input id="c" value="c">
      """)
      |> assert_has("input", label: "Email", at: 1, value: "b")
      |> assert_has("input", label: "Email", at: 2, value: "c")
      |> refute_has("input", label: "Email", at: 1, value: "a")
    end

    @tag driver: driver
    test "field action overloads, exact labels, and CSS intersections with #{driver}" do
      session =
        Fluffy.session_for_html(unquote(driver), """
        <label for="email">Email</label><input id="email">
        <label for="backup">Email backup</label><input id="backup">
        <label for="duplicate">Email</label><input id="duplicate">
        <label for="sub">Subscribe</label><input id="sub" type="checkbox">
        <label for="more">Subscribe later</label><input id="more" type="checkbox">
        <label for="radio">Express</label><input id="radio" type="radio" name="delivery">
        <label for="plan">Plan</label><select id="plan"><option value="free">Free</option><option value="pro">Professional</option></select>
        <label for="plans">Plans</label><select id="plans" multiple><option value="free">Free</option><option value="pro">Professional</option></select>
        """)

      session =
        session
        |> fill_in("#email", "Email", with: "first")
        |> fill_in("Email back", with: "second", exact: false)
        |> fill_in("#duplicate", "Email", with: "third")
        |> assert_has("#email", value: "first")
        |> assert_has("#backup", value: "second")
        |> check("Subscribe")
        |> assert_has("#more", checked: false)
        |> uncheck("Subscribe", exact: true)
        |> check("#sub", "Subscribe")
        |> uncheck("#sub", "Sub", exact: false)
        |> check("#sub", "Subscribe", exact: true)
        |> uncheck("Subscribe")
        |> check("Subscribe", exact: true)
        |> uncheck("#sub", "Subscribe")
        |> choose("Express")
        |> choose("Express", exact: true)
        |> choose("#radio", "Express")
        |> choose("#radio", "Exp", exact: false)
        |> assert_has("#radio", checked: true)
        |> select("Plan", option: "Professional")
        |> assert_has("#plan", value: "pro")
        |> select("Free", from: "Plan")
        |> assert_has("#plan", value: "free")
        |> select("#plan", "Plan", option: "Professional", exact_option: true)
        |> select("#plan", "Free", from: "Plan")
        |> assert_has("#plan", value: "free")
        |> select("Plans", option: ["Free", "Professional"])
        |> select("#plans", "Plans", option: ["Professional"])

      Expect.expect(session.session, Expect.to_have_values(Locator.by_css("#plans"), ["pro"]))

      assert_raise Fluffy.OperationError, fn -> fill_in(session, "Email", with: "ambiguous") end
    end

    @tag driver: driver
    test "nested scopes retain mutations and restore the outer scope with #{driver}" do
      session =
        Fluffy.session_for_html(unquote(driver), """
        <section id="outer">
          <input aria-label="Name" id="outer-name">
          <section id="inner"><input aria-label="Name" id="inner-name"></section>
        </section>
        <input aria-label="Name" id="outside">
        """)

      updated =
        within(session, "#outer", fn outer ->
          assert %Session{} = outer

          outer
          |> within("#inner", fn inner ->
            inner
            |> fill_in("input", "Name", with: "inner")
            |> assert_has("input", value: "inner", label: "Name")
            |> refute_has("#outer-name")
            |> refute_has("#outside")
          end)
          |> fill_in("#outer-name", "Name", with: "outer")
          |> assert_has("input", count: 2)
        end)

      assert %Session{} = updated

      updated
      |> assert_has("#inner-name", value: "inner")
      |> assert_has("#outer-name", value: "outer")
      |> assert_has("#outside", value: "")
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "exact CSS clicks distinguish overlapping button and link text with #{driver}" do
      fixture =
        Fluffy.TestHTTPFixtures.register(%{
          body: """
          <html><body>
            <form method="get">
              <button name="choice" value="none">Union: None</button>
              <button name="choice" value="construction">Construction union: None</button>
            </form>
            <a href="?choice=none">None</a><a href="?choice=other">None available</a>
          </body></html>
          """
        })

      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit(Fluffy.TestHTTPFixtures.path(fixture))
      |> click_button("button", "Union: None", exact: true)
      |> assert_path(Fluffy.TestHTTPFixtures.path(fixture), query_params: %{choice: "none"})
      |> click_link("a", "None", exact: true)
      |> assert_path(Fluffy.TestHTTPFixtures.path(fixture), query_params: %{choice: "none"})
    end

    @tag driver: driver
    test "submit tracks the last field's owner across scopes and external form controls with #{driver}" do
      fixture =
        Fluffy.TestHTTPFixtures.register_sequence([
          %{
            body: """
            <html><body>
              <form action="wrong"><input aria-label="First" name="first"></form>
              <form id="target" method="post" action="save"></form>
              <section><input form="target" aria-label="Second" name="second"></section>
            </body></html>
            """
          },
          %{body: "<html><body><p>Saved</p></body></html>"}
        ])

      session =
        unquote(driver)
        |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
        |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/start"))

      assert_raise ArgumentError, ~r/no active form/, fn -> submit(session) end
      assert_raise FunctionClauseError, fn -> apply(Fluffy, :fill, [session, Locator.by_label("First"), "native"]) end

      updated =
        session
        |> fill_in("First", with: "wrong form")
        |> within("section", &fill_in(&1, "Second", with: "right form"))
        |> submit()
        |> assert_has("p", text: "Saved")

      assert %Session{} = updated
      assert_raise ArgumentError, ~r/no active form/, fn -> submit(updated) end
      [_source, submission] = Fluffy.TestHTTPFixtures.requests(fixture)
      assert URI.decode_query(submission.body) == %{"second" => "right form"}
    end

    @tag driver: driver
    test "submit tracks forms without ids and clears tracking on submission and navigation with #{driver}" do
      fixture =
        Fluffy.TestHTTPFixtures.register(%{
          body: """
          <html><body><form method="post"><input name="name" aria-label="Name"></form></body></html>
          """
        })

      path = Fluffy.TestHTTPFixtures.path(fixture)

      session =
        unquote(driver)
        |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
        |> visit(path)
        |> fill_in("Name", with: "Ada")

      session |> submit() |> assert_has("input")
      assert_raise ArgumentError, ~r/no active form/, fn -> session |> reload_page() |> submit() end
      assert_raise ArgumentError, ~r/no active form/, fn -> session |> visit(path) |> submit() end
    end

    @tag driver: driver
    test "submit retains the active form across LiveView patches with #{driver}" do
      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/live/chamber-map")
      |> fill_in("Map step", with: "filtered")
      |> assert_path("/live/chamber-map", query_params: %{step: "filtered"})
      |> submit()
      |> assert_has("p", text: "Saved step: filtered")
      |> fill_in("Map step", with: "next")
      |> click_link("Reveal passage")
      |> assert_path("/live/chamber-map", query_params: %{step: "patched"})
      |> submit()
      |> assert_has("p", text: "Saves: 2")
    end

    @tag driver: driver
    test "navigation clears the active form with #{driver}" do
      for link <- ["Secret chamber", "Sleeping chamber"] do
        session =
          unquote(driver)
          |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
          |> visit("/live/chamber-map")
          |> fill_in("Map step", with: "filtered")
          |> click_link(link)

        assert_raise ArgumentError, ~r/no active form/, fn -> submit(session) end
      end
    end

    @tag driver: driver
    test "submit uses current LiveView form state after changes with #{driver}" do
      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/live/potions")
      |> fill_in("First ingredient", with: "moonstone")
      |> submit()
      |> assert_has("p", text: "Saved rows: ash, belladonna, cinder")
    end

    @tag driver: driver
    test "wildcard paths match complete segments and combine with exact queries with #{driver}" do
      fixture = Fluffy.TestHTTPFixtures.register(%{body: "<html><body><main>Draft</main></body></html>"})
      path = Fluffy.TestHTTPFixtures.path(fixture, "/projects/v1.2+/send/drafts/abc/edit")
      pattern = Fluffy.TestHTTPFixtures.path(fixture, "/projects/*/send/drafts/*/edit")
      query = %{page: 2, ready: true, search: "a+b & c"}

      session =
        unquote(driver)
        |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
        |> visit(path <> "?page=2&ready=true&search=a%2Bb+%26+c#section")
        |> assert_path(pattern)
        |> assert_path(pattern, query_params: query, timeout: 0)
        |> assert_path(Fluffy.TestHTTPFixtures.path(fixture, "/projects/v1.2+/send/drafts/*/edit"))
        |> refute_path(pattern <> "/extra")
        |> refute_path(Fluffy.TestHTTPFixtures.path(fixture, "/projects/*/edit"))
        |> refute_path(Fluffy.TestHTTPFixtures.path(fixture, "/projects/v1X2+/send/drafts/*/edit"))
        |> refute_path(Fluffy.TestHTTPFixtures.path(fixture, "/projects/*/send/drafts/ab*/edit"))
        |> refute_path(pattern <> "/")
        |> refute_path(pattern, query_params: %{page: 2})
        |> refute_path(pattern, query_params: %{query | page: 3})
        |> refute_path(pattern <> "/extra", query_params: query)
        |> within("main", &assert_path(&1, pattern))

      assert_raise ExUnit.AssertionError, fn -> refute_path(session, pattern, timeout: 0) end

      assert_raise ExUnit.AssertionError, fn ->
        refute_path(session, pattern, query_params: query, timeout: 0)
      end

      assert_raise ExUnit.AssertionError, fn ->
        assert_path(session, pattern, query_params: %{page: 2}, timeout: 0)
      end

      session
      |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/projects//send/drafts/abc/edit"))
      |> assert_path(pattern, query_params: %{})
      |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/projects/42/send/drafts/abc/edit/"))
      |> refute_path(pattern)
      |> assert_path(pattern <> "/*")
    end

    @tag driver: driver
    test "wildcard paths work after LiveView navigation with #{driver}" do
      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/chamber")
      |> assert_path("/*")
      |> visit("/live/three-heads?ready=true")
      |> assert_path("/live/*", query_params: %{ready: true})
      |> refute_path("/*")
      |> refute_path("/live/*/extra")
      |> within("main", &assert_path(&1, "/*/*"))
    end

    @tag driver: driver
    test "page titles use escaped substring text and exact title expectations with #{driver}" do
      fixture =
        Fluffy.TestHTTPFixtures.register_sequence([
          %{body: "<html><head><title>Potions [ready].</title></head><body><main></main></body></html>"},
          %{body: "<html><head><title></title></head><body></body></html>"}
        ])

      session =
        unquote(driver)
        |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
        |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/title"))

      session
      |> assert_has("title")
      |> assert_has("title", "[ready].")
      |> assert_has("title", text: "Potions [ready].", exact: true)
      |> refute_has("title", "Potions", exact: true)
      |> within("main", &assert_has(&1, "title", text: "Potions"))

      assert_raise ExUnit.AssertionError, fn -> assert_has(session, "title", "[nope].", timeout: 0) end
      empty = visit(session, Fluffy.TestHTTPFixtures.path(fixture, "/empty"))
      refute_has(empty, "title")
    end

    @tag driver: driver
    test "upload overloads retain file submission with #{driver}" do
      fixture =
        Fluffy.TestHTTPFixtures.register_sequence([
          %{
            body: """
            <html><body><form method="post" action="submit" enctype="multipart/form-data">
              <input id="file" name="file" type="file" aria-label="Evidence">
              <button>Upload</button>
            </form></body></html>
            """
          },
          %{body: "<html><body><p>Uploaded</p></body></html>"}
        ])

      path = Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__)

      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/upload/start"))
      |> upload("Evidence", path)
      |> upload("Evidence", path, [])
      |> upload("Evidence", path, exact: true)
      |> upload("#file", "Evidence", path)
      |> upload("#file", "Evi", path, exact: false)
      |> click_button("Upload")
      |> assert_has("p", "Uploaded")

      [_source, submission] = Fluffy.TestHTTPFixtures.requests(fixture)
      assert submission.body =~ ~s(filename="fluffy-upload.txt")
      assert submission.body =~ File.read!(path)
    end

    for variant <- [:label, :label_options, :selector, :selector_options, :clear] do
      @tag driver: driver
      test "multi-file upload #{variant} preserves submitted selection with #{driver}" do
        fixture =
          Fluffy.TestHTTPFixtures.register_sequence([
            %{
              body: """
              <html><body><form method="post" action="submit" enctype="multipart/form-data">
                <input id="file" name="files[]" type="file" multiple aria-label="Evidence">
                <button>Upload</button>
              </form></body></html>
              """
            },
            %{body: "<html><body><p>Uploaded</p></body></html>"}
          ])

        paths =
          Enum.map(["fluffy-upload-second.txt", "fluffy-upload.txt"], &Path.expand("../support/fixtures/#{&1}", __DIR__))

        session =
          unquote(driver)
          |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
          |> visit(Fluffy.TestHTTPFixtures.path(fixture, "/upload/start"))

        session =
          case unquote(variant) do
            :label -> upload(session, "Evidence", paths)
            :label_options -> upload(session, "Evi", paths, exact: false)
            :selector -> upload(session, "#file", "Evidence", paths)
            :selector_options -> upload(session, "#file", "Evi", paths, exact: false)
            :clear -> session |> upload("Evidence", paths) |> upload("#file", "Evidence", [], [])
          end

        session |> click_button("Upload") |> assert_has("p", "Uploaded")

        [_source, submission] = Fluffy.TestHTTPFixtures.requests(fixture)

        filenames =
          ~r/filename="([^"]+)"/
          |> Regex.scan(submission.body, capture: :all_but_first)
          |> List.flatten()

        assert filenames == if(unquote(variant) == :clear, do: [], else: Enum.map(paths, &Path.basename/1))
      end
    end

    @tag driver: driver
    test "scoped LiveView actions and page utilities preserve reconciled sessions with #{driver}" do
      session = start_session(unquote(driver), base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)

      session
      |> visit("/live/three-heads")
      |> within("main", fn scoped ->
        scoped
        |> click_button("Play the flute")
        |> assert_has("p", "Sleeping heads: 1")
        |> click_button("button", "Play the flute")
        |> assert_has("p", "Sleeping heads: 2")
        |> assert_path("/live/three-heads")
        |> reload_page()
        |> assert_has("p", "Sleeping heads: 0")
      end)
      |> assert_has("p", "Sleeping heads: 0")
    end

    @tag driver: driver
    test "assertions forward retry timeouts with #{driver}" do
      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/live/async?delay=40")
      |> assert_has("p", "Status: ready", timeout: 1_000)
      |> refute_has("p", "Status: waiting", timeout: 0)
    end
  end

  test "prepared connections and scoped page operations preserve the updated connection" do
    for conn <- [Phoenix.ConnTest.build_conn(), put_endpoint(Phoenix.ConnTest.build_conn(), Endpoint)] do
      session = conn |> visit("/chamber?count=2&ready=true") |> assert_path("/chamber")
      assert session.session.backend == Fluffy.Backend.Phoenix
      assert_path(session, "/chamber", query_params: %{count: 2, ready: true})
      refute_path(session, "/other", query_params: %{count: 2, ready: true})
      refute_path(session, "/chamber", query_params: %{count: 3, ready: true})

      assert_raise ExUnit.AssertionError, fn ->
        refute_path(session, "/chamber", query_params: %{count: 2, ready: true})
      end

      session
      |> within("body", fn scoped ->
        unwrap(scoped, fn conn -> %{conn | resp_body: "<p>Replaced</p>", status: 202} end)
      end)
      |> assert_has("p", "Replaced")
    end
  end

  test "link overloads navigate and preserve scopes through page operations" do
    for action <- [&click_link(&1, "Enter"), &click_link(&1, "a", "Enter")] do
      :phoenix
      |> start_session()
      |> visit("/chamber")
      |> unwrap(fn conn -> %{conn | resp_body: "<main><a href='/live/three-heads'>Enter</a></main>"} end)
      |> within("main", fn scoped ->
        scoped |> action.() |> assert_path("/live/three-heads") |> assert_has("button", "Play the flute")
      end)
      |> assert_path("/live/three-heads")
      |> within("main", &visit(&1, "/chamber"))
      |> assert_path("/chamber")
    end
  end

  test "within rejects callbacks that discard their updated wrapper" do
    session = Fluffy.session_for_html(:static, "<main></main>")
    assert_raise ArgumentError, ~r/within callback must return/, fn -> within(session, "main", fn _ -> :ok end) end
  end

  test "unsupported combinations and invalid options fail explicitly before driver execution" do
    session = Fluffy.session_for_html(:static, "<main></main>")

    for {options, message} <- [
          {[selected: 42], ~r/selected: must be a string/},
          {[selected: "One", count: 1], ~r/count: cannot be combined/},
          {[at: 0], ~r/at: must be a positive one-based position/},
          {[at: -1], ~r/at: must be a positive one-based position/},
          {[at: 1, count: 1], ~r/count: cannot be combined/},
          {[count: 1, value: "x"], ~r/count: cannot be combined/},
          {[count: 1, checked: true], ~r/count: cannot be combined/},
          {[text: "x", value: "x"], ~r/only one of text:, value:, checked:, or selected:/},
          {[value: "x", checked: true], ~r/only one of text:, value:, checked:, or selected:/},
          {[exact: true], ~r/exact: requires label: or text:/},
          {[count: -1], ~r/count: must be a nonnegative integer/},
          {[timeout: -1], ~r/timeout: must be a nonnegative integer/},
          {[checked: :yes], ~r/checked: must be a boolean/},
          {[value: 42], ~r/value: must be a string/},
          {[text: {:safe, "x"}], ~r/text: must be a string/},
          {[count: 1, count: 2], ~r/duplicate options/}
        ] do
      assert_raise ArgumentError, message, fn -> assert_has(session, "input", options) end
      assert_raise ArgumentError, message, fn -> refute_has(session, "input", options) end
    end

    for options <- [[count: 1], [at: 1], [value: "x"], [label: "x"]] do
      assert_raise ArgumentError, ~r/unsupported options/, fn -> assert_has(session, "title", options) end
    end

    for {message, fun} <- [
          {~r/exact: requires text:/, fn -> assert_has(session, "title", exact: true) end},
          {~r/unsupported options: \[:text\]/, fn -> assert_has(session, "p", "x", text: "y") end},
          {~r/missing required option with:/, fn -> fill_in(session, "Email", exact: true) end},
          {~r/unsupported options: \[:unsupported\]/, fn -> fill_in(session, "Email", with: "x", unsupported: true) end},
          {~r/exact: must be a boolean/, fn -> fill_in(session, "Email", with: "x", exact: :yes) end},
          {~r/exact_option: false is unsupported/, fn -> select(session, "Plan", option: "Pro", exact_option: false) end},
          {~r/either option: or from:/, fn -> select(session, "Plan", option: "Pro", from: "Plan") end},
          {~r/either option: or from:/, fn -> select(session, "Plan", []) end},
          {~r/unsupported options: \[:timeout\]/, fn -> check(session, "Email", timeout: 0) end},
          {~r/exact: must be a boolean/, fn -> uncheck(session, "Email", exact: nil) end},
          {~r/exact: must be a boolean/, fn -> choose(session, "Email", exact: nil) end},
          {~r/exact: must be a boolean/, fn -> upload(session, "File", "path", exact: nil) end},
          {~r/paths must be a string or a list of strings/, fn -> upload(session, "File", ["a", 42]) end},
          {~r/paths must be a string or a list of strings/, fn -> upload(session, "File", ["a", 42], exact: true) end},
          {~r/paths must be a string or a list of strings/, fn -> upload(session, "#file", "File", ["a", 42]) end},
          {~r/paths must be a string or a list of strings/, fn -> upload(session, "File", 42) end},
          {~r/nested queries are unsupported/, fn -> assert_path(session, "/", query_params: %{nested: %{value: 1}}) end},
          {~r/nested queries are unsupported/, fn -> refute_path(session, "/", query_params: %{list: [1, 2]}) end},
          {~r/query_params: must be a flat map/, fn -> assert_path(session, "/", query_params: [key: "value"]) end},
          {~r/unsupported options: \[:exact\]/, fn -> assert_path(session, "/", exact: false) end}
        ] do
      assert_raise ArgumentError, message, fun
    end
  end
end
