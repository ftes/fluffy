defmodule Fluffy.Conformance.StaticHTTPFormTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "submits ordered successful controls with GET using #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="get" action="search?discard=old#results">
                <input type="hidden" name="token" value="abc">
                <label>Query <input name="query" value="initial"></label>
                <label><input type="checkbox" name="scope" value="open" checked> Open</label>
                <label><input type="checkbox" name="ignored" value="no"> Ignored</label>
                <label>Sort
                  <select name="sort">
                    <option value="newest" selected>Newest</option>
                    <option value="oldest">Oldest</option>
                  </select>
                </label>
                <button name="commit" value="Search">Search</button>
              </form>
              """)
          },
          %{body: html("<h1>Search results</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> fill(by_label("Query"), "fluffy test")
      |> click(by_role(:button, name: "Search"))
      |> expect("Search results" |> by_text() |> to_be_visible())
      |> expect(
        Fluffy.Expect.page_to_have_url(
          TestHTTPFixtures.url(
            fixture,
            "/forms/search?token=abc&query=fluffy+test&scope=open&sort=newest&commit=Search#results"
          )
        )
      )

      [source, submission] = TestHTTPFixtures.requests(fixture)
      assert source.method == "GET"
      assert submission.method == "GET"
      assert submission.path == "/forms/search"

      assert submission.query ==
               "token=abc&query=fluffy+test&scope=open&sort=newest&commit=Search"

      assert submission.body == ""
    end

    @tag driver: driver
    test "submits a form without a submitter using #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form id="search-form" method="get" action="search">
                <label>Query <input name="query" value="initial"></label>
              </form>
              """)
          },
          %{body: html("<h1>Search results</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> fill(by_label("Query"), "fluffy test")
      |> submit(by_css("#search-form"))
      |> expect("Search results" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "GET"
      assert submission.path == "/forms/search"
      assert submission.query == "query=fluffy+test"
    end

    @tag driver: driver
    test "submit returns once the server has received the submission using #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form id="note" method="post" action="save"><input name="note" value="kept"></form>))},
          %{body: html("<h1>Saved</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "note=kept"
    end

    @tag driver: driver
    test "submit returns once the server has answered the redirected request using #{driver}", %{driver: driver} do
      test = self()

      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form id="note" method="post" action="save"><input name="note" value="kept"></form>))},
          %{status: 303, headers: [{"location", "saved"}]},
          fn _request ->
            Process.sleep(300)
            send(test, :saved_page_served)
            %{body: html("<h1>Saved</h1>")}
          end
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 5_000)

      assert_received :saved_page_served
    end

    # Nothing reads the page after the submit, so submit itself must return. Before
    # Playwright 1.65, Chromium waited on the aborted navigation (microsoft/playwright#43279).
    @tag driver: driver
    test "submit returns after a no-content response using #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form id="note" method="post" action="save"><input name="note" value="kept"></form>))},
          %{status: 204}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 2_000)

      assert [_source, %{method: "POST", body: "note=kept"}] = TestHTTPFixtures.requests(fixture)
    end

    # Browsers abort the navigation and keep the document; none resets the form on 205.
    for status <- [204, 205] do
      @tag driver: driver
      test "a #{status} response to submit keeps the current page and form state using #{driver}", %{driver: driver} do
        fixture =
          TestHTTPFixtures.register_sequence([
            %{
              body:
                html(
                  ~s(<h1>Draft</h1><form id="note" method="post" action="save"><label>Note <input name="note" value="draft"></label></form>)
                )
            },
            %{status: unquote(status)}
          ])

        driver
        |> start_test_session()
        |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
        |> fill(by_label("Note"), "edited")
        |> submit(by_css("#note"), timeout: 2_000)
        |> expect("Draft" |> by_text() |> to_be_visible())
        |> expect("Note" |> by_label() |> to_have_value("edited"))
        |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/forms/start")))

        assert [_source, %{method: "POST", body: "note=edited"}] = TestHTTPFixtures.requests(fixture)
      end
    end

    @tag driver: driver
    test "a download response to submit keeps the current page using #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<h1>Exports</h1><form id="export" method="post" action="export"></form>))},
          %{
            headers: [{"content-type", "text/csv"}, {"content-disposition", ~s(attachment; filename="report.csv")}],
            body: "id\n1\n"
          }
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#export"), timeout: 2_000)
      |> expect("Exports" |> by_text() |> to_be_visible())
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/forms/start")))

      assert [_source, %{method: "POST"}] = TestHTTPFixtures.requests(fixture)
    end

    @tag driver: driver
    test "submits ordered successful controls with URL-encoded POST using #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit?source=form#receipt">
                <label>First <input name="first" value="one"></label>
                <label>Notes <textarea name="notes">initial</textarea></label>
                <button name="commit" value="Save">Save order</button>
              </form>
              """)
          },
          %{body: html("<h1>Order saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> fill(by_label("First"), "updated")
      |> fill(by_label("Notes"), "line one")
      |> click(by_role(:button, name: "Save order"))
      |> expect("Order saved" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/forms/submit?source=form#receipt")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.path == "/forms/submit"
      assert submission.query == "source=form"
      assert submission.body == "first=updated&notes=line+one&commit=Save"

      assert {"content-type", content_type} =
               List.keyfind(submission.headers, "content-type", 0)

      assert content_type =~ "application/x-www-form-urlencoded"
    end

    @tag driver: driver
    test "submits multipart text fields and empty file controls using #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit" enctype="multipart/form-data">
                <label>First <input name="first" value="one"></label>
                <label>Attachment <input type="file" name="attachment"></label>
                <button name="commit" value="Save">Save order</button>
              </form>
              """)
          },
          %{body: html("<h1>Order saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> fill(by_label("First"), "updated")
      |> click(by_role(:button, name: "Save order"))
      |> expect("Order saved" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert {"content-type", "multipart/form-data; boundary=" <> boundary} =
               List.keyfind(submission.headers, "content-type", 0)

      assert submission.body ==
               "--#{boundary}\r\n" <>
                 "Content-Disposition: form-data; name=\"first\"\r\n\r\n" <>
                 "updated\r\n" <>
                 "--#{boundary}\r\n" <>
                 ~s(Content-Disposition: form-data; name="attachment"; filename=""\r\n) <>
                 "Content-Type: application/octet-stream\r\n\r\n\r\n" <>
                 "--#{boundary}\r\n" <>
                 "Content-Disposition: form-data; name=\"commit\"\r\n\r\n" <>
                 "Save\r\n" <>
                 "--#{boundary}--\r\n"
    end

    @tag driver: driver
    test "submits a form whose required checkbox is already satisfied using #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit">
                <label><input type="checkbox" name="confirmed" value="yes" required checked> Confirm</label>
                <button>Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> click(by_role(:button, name: "Save"))
      |> expect("Saved" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "confirmed=yes"
    end

    @tag driver: driver
    test "uses the browser successful-control rules and CRLF encoding with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <input form="target" name="outside_before" value="before">
              <form id="target" method="post" action="submit">
                <fieldset disabled>
                  <legend><input name="legend" value="yes"></legend>
                  <input name="disabled_by_fieldset" value="no">
                </fieldset>
                <input readonly name="readonly" value="kept">
                <input hidden name="invisible" value="hidden">
                <input name="item" value="one">
                <input name="item" value="two">
                <input value="unnamed">
                <datalist><input name="datalist_fallback" value="wrong"></datalist>
                <button type="button" name="drop" value="wrong">Remove row</button>
                <input type="reset" name="reset" value="wrong">
                <label>Notes <textarea name="notes">initial</textarea></label>
                <select name="choice" multiple>
                  <optgroup disabled><option selected value="disabled">Disabled</option></optgroup>
                  <option selected value="kept">Kept</option>
                </select>
                <button name="commit" value="Save">Save</button>
              </form>
              <input form="target" name="outside_after" value="after">
              """)
          },
          %{body: html("<h1>Saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> fill(by_label("Notes"), "first\nsecond")
      |> click(by_role(:button, name: "Save"))
      |> expect("Saved" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert submission.body ==
               "outside_before=before&legend=yes&readonly=kept&invisible=hidden&item=one&item=two&datalist_fallback=wrong&notes=first%0D%0Asecond&choice=kept&commit=Save&outside_after=after"
    end

    @tag driver: driver
    test "unchecking one array-named checkbox preserves only its checked peer with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit">
                <label><input type="checkbox" name="items[]" value="one" checked>One</label>
                <label><input type="checkbox" name="items[]" value="two" checked>Two</label>
                <button name="commit" value="Save">Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> uncheck(by_role(:checkbox, name: "One"))
      |> click(by_role(:button, name: "Save"))
      |> expect("Saved" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "items%5B%5D=two&commit=Save"
    end

    @tag driver: driver
    test "submitter method, action, and encoding override their form with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="get" action="ignored" enctype="multipart/form-data">
                <input name="query" value="fluffy">
                <button
                  formaction="override?source=button"
                  formmethod="post"
                  formenctype="application/x-www-form-urlencoded"
                  name="commit"
                  value="Search"
                >Search</button>
              </form>
              """)
          },
          %{body: html("<h1>Overridden</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> click(by_role(:button, name: "Search"))
      |> expect("Overridden" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.path == "/forms/override"
      assert submission.query == "source=button"
      assert submission.body == "query=fluffy&commit=Search"
    end

    @tag driver: driver
    test "uses the HTML form URL-encoded percent-encode set with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit">
                <input name="symbols" value="a b+c~d!*()é">
                <button>Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> click(by_role(:button, name: "Save"))
      |> expect("Saved" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "symbols=a+b%2Bc%7Ed%21*%28%29%C3%A9"
    end

    @tag driver: driver
    test "uses browser defaults for charset, option text, selection, and form ownership with #{driver}",
         %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <div id="target"></div>
              <input form="target" name="wrong_owner" value="omitted">
              <form id="target" method="post" action="submit">
                <input type="hidden" name="_charset_">
                <select name="plan">
                  <option disabled value="unavailable">Unavailable</option>
                  <optgroup disabled><option value="legacy">Legacy</option></optgroup>
                  <option value="current">Current</option>
                </select>
                <select name="queue" size="2"><option>First</option></select>
                <select name="label"><option>  Gold
                    plan  </option></select>
                <button>Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Saved</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> click(by_role(:button, name: "Save"))
      |> expect("Saved" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "_charset_=UTF-8&plan=current&label=Gold+plan"
    end

    for {status, redirected_method} <- [{303, "GET"}, {307, "POST"}] do
      @tag driver: driver
      test "follows HTTP #{status} after POST with browser method semantics using #{driver}", %{
        driver: driver
      } do
        fixture =
          TestHTTPFixtures.register_sequence([
            %{
              body:
                html("""
                <form method="post" action="submit">
                  <input type="hidden" name="token" value="abc">
                  <button name="commit" value="Save">Save</button>
                </form>
                """)
            },
            %{status: unquote(status), headers: [{"location", "receipt"}]},
            %{body: html("<h1>Redirected receipt</h1>")}
          ])

        session = start_test_session(driver)

        session
        |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
        |> click(by_role(:button, name: "Save"))
        |> expect("Redirected receipt" |> by_text() |> to_be_visible())
        |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/forms/receipt")))

        [_source, submission, redirected] = TestHTTPFixtures.requests(fixture)
        assert submission.method == "POST"
        assert submission.body == "token=abc&commit=Save"
        assert redirected.method == unquote(redirected_method)

        expected_body = if redirected.method == "POST", do: submission.body, else: ""
        assert redirected.body == expected_body
      end
    end
  end

  test "Phoenix submits specialized scalar input values as plain strings" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body:
            html("""
            <form method="post" action="submit">
              <label>Email <input type="email" name="email"></label>
              <label>Number <input type="number" name="number"></label>
              <label>URL <input type="url" name="url"></label>
              <input type="color" name="colour" value="not-a-colour">
              <input type="date" name="date" value="not-a-date">
              <input type="datetime-local" name="datetime" value="soon">
              <input type="month" name="month" value="later">
              <input type="range" name="range" value="wide">
              <input type="time" name="time" value="noon">
              <input type="week" name="week" value="someday">
              <button>Save</button>
            </form>
            """)
        },
        %{body: html("<h1>Saved</h1>")}
      ])

    session = start_test_session(:phoenix)

    session
    |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
    |> fill(by_label("Email"), "not an email")
    |> fill(by_label("Number"), "many")
    |> fill(by_label("URL"), "not a url")
    |> click(by_role(:button, name: "Save"))
    |> expect("Saved" |> by_text() |> to_be_visible())

    [_source, submission] = TestHTTPFixtures.requests(fixture)

    assert submission.body ==
             "email=not+an+email&number=many&url=not+a+url&colour=not-a-colour&date=not-a-date&datetime=soon&month=later&range=wide&time=noon&week=someday"
  end

  # These submissions start no navigation in the page; submit must not wait for one.
  for {name, form} <- [
        {"a new-window target", ~s(<form id="note" method="post" action="save" target="_blank"></form>)},
        {"a named window target", ~s(<form id="note" method="post" action="save" target="elsewhere"></form>)},
        {"dialog method", ~s(<dialog open><form id="note" method="dialog"></form></dialog>)},
        {"a cancelled submit event", ~s[<form id="note" action="save" onsubmit="event.preventDefault()"></form>]}
      ] do
    @tag driver: :playwright
    test "Playwright submit with #{name} does not wait for a page navigation" do
      fixture = TestHTTPFixtures.register(%{body: html("<h1>Draft</h1>" <> unquote(form))})

      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 2_000)
      |> expect("Draft" |> by_text() |> to_be_visible())
    end
  end

  # The GET's URL differs from the current one only by its fragment.
  @tag driver: :playwright
  test "Playwright submit of a GET to a fragment of the current URL navigates within the document" do
    fixture =
      TestHTTPFixtures.register(%{
        body: html(~s(<h1>Draft</h1><form id="note" action="#results"><input name="q" value="fluffy"></form>))
      })

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/forms/start?q=fluffy"))
    |> submit(by_css("#note"), timeout: 2_000)
    |> expect("Draft" |> by_text() |> to_be_visible())
    |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/forms/start?q=fluffy#results")))

    assert [_source] = TestHTTPFixtures.requests(fixture)
  end

  @tag driver: :playwright
  test "Playwright submit intercepted by the Navigation API navigates within the document" do
    intercept = """
    <script>
      navigation.addEventListener('navigate', event => {
        if (event.formData) event.intercept({handler: () => { document.querySelector('h1').textContent = 'Intercepted' }})
      })
    </script>
    """

    fixture =
      TestHTTPFixtures.register(%{
        body: html(~s(<h1>Draft</h1><form id="note" method="post" action="save"></form>) <> intercept)
      })

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
    |> submit(by_css("#note"), timeout: 2_000)
    |> expect("Intercepted" |> by_text() |> to_be_visible())

    assert [_source] = TestHTTPFixtures.requests(fixture)
  end

  # The handler commits a same-document navigation before the form's own starts.
  for {name, attributes, change} <- [
        {"pushState", ~s(action="save"), "history.pushState({}, '', 'edited')"},
        {"replaceState", ~s(action="save"), "history.replaceState({}, '', 'edited')"},
        {"location.hash", ~s(action="save"), "location.hash = 'edited'"},
        {"pushState to the form's URL", ~s(action="save"), "history.pushState({}, '', 'save')"},
        {"replaceState keeping the URL the form posts to", "", "history.replaceState({}, '')"}
      ] do
    @tag driver: :playwright
    test "Playwright submit waits for the server when a submit handler calls #{name}" do
      test = self()
      form = ~s[<form id="note" method="post" #{unquote(attributes)} onsubmit="#{unquote(change)}"></form>]

      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(form)},
          fn _request ->
            Process.sleep(500)
            send(test, :saved_page_served)
            %{body: html("<h1>Saved</h1>")}
          end
        ])

      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 5_000)

      assert_received :saved_page_served
    end
  end

  # The handler's commit comes first; the intercepted navigation's is the one
  # that ends the wait, even at the URL the handler has already moved to.
  for {name, action, change, destination} <- [
        {"pushState elsewhere", "save", "history.pushState({}, '', 'edited')", "/forms/save"},
        {"pushState to the form's URL", "save", "history.pushState({}, '', 'save')", "/forms/save"},
        {"replaceState to the form's URL", "save", "history.replaceState({}, '', 'save')", "/forms/save"},
        {"location.hash to the form's fragment", "#done", "location.hash = 'done'", "/forms/start#done"}
      ] do
    @tag driver: :playwright
    test "Playwright submit intercepted after a submit handler's #{name} ends at the intercepted commit" do
      intercept = """
      <script>
        navigation.addEventListener('navigate', event => {
          if (event.formData) event.intercept({handler: () => { document.querySelector('h1').textContent = 'Intercepted' }})
        })
      </script>
      """

      form =
        ~s[<h1>Draft</h1><form id="note" method="post" action="#{unquote(action)}" onsubmit="#{unquote(change)}"></form>]

      fixture = TestHTTPFixtures.register(%{body: html(form <> intercept)})

      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 2_000)
      |> expect("Intercepted" |> by_text() |> to_be_visible())
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, unquote(destination))))

      assert [_source] = TestHTTPFixtures.requests(fixture)
    end
  end

  # Any commit of the intercepted navigation ends the wait, wherever the browser
  # encoded it.
  for {name, head, attributes, controls} <- [
        {"spaces and line breaks", "", "", ~s(<textarea name="q">fluffy test\nüber</textarea>)},
        {"no successful controls", "", "", ""},
        {"accept-charset", "", ~s(accept-charset="iso-8859-1"), ~s(<input name="q" value="&uuml;ber">)},
        {"a latin1 page", ~s(<meta charset="iso-8859-1">), "", ~s(<input name="q" value="&uuml;ber">)}
      ] do
    @tag driver: :playwright
    test "Playwright submit of an intercepted GET with #{name} ends at the intercepted commit" do
      intercept = """
      <script>
        navigation.addEventListener('navigate', event => {
          if (event.navigationType === 'push' && event.canIntercept) {
            event.intercept({handler: () => { document.querySelector('h1').textContent = 'Intercepted' }})
          }
        })
      </script>
      """

      form =
        ~s(<h1>Draft</h1><form id="note" action="search?old=1#top" #{unquote(attributes)}>#{unquote(controls)}</form>)

      fixture = TestHTTPFixtures.register(%{body: unquote(head) <> html(form <> intercept)})

      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 2_000)
      |> expect("Intercepted" |> by_text() |> to_be_visible())

      assert [_source] = TestHTTPFixtures.requests(fixture)
    end
  end

  @tag driver: :playwright
  test "Playwright submit redirected by a precommit handler ends at the redirected commit" do
    intercept = """
    <script>
      navigation.addEventListener('navigate', event => {
        if (event.formData) event.intercept({precommitHandler: controller => controller.redirect('elsewhere')})
      })
    </script>
    """

    fixture =
      TestHTTPFixtures.register(%{
        body: html(~s(<h1>Draft</h1><form id="note" method="post" action="save"></form>) <> intercept)
      })

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
    |> submit(by_css("#note"), timeout: 2_000)
    |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/forms/elsewhere")))

    assert [_source] = TestHTTPFixtures.requests(fixture)
  end

  # A navigate listener cancels the handler's pushState, so nothing commits and
  # the intercepted navigation's commit is the first.
  @tag driver: :playwright
  test "Playwright submit does not count a submit handler's cancelled pushState" do
    script = """
    <script>
      navigation.addEventListener('navigate', event => {
        if (event.destination.url.endsWith('/edited')) event.preventDefault()
        else if (event.formData) event.intercept({handler: () => { document.querySelector('h1').textContent = 'Intercepted' }})
      })
    </script>
    """

    form =
      ~s[<h1>Draft</h1><form id="note" method="post" action="save" onsubmit="history.pushState({}, '', 'edited')"></form>]

    fixture = TestHTTPFixtures.register(%{body: html(form <> script)})

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
    |> submit(by_css("#note"), timeout: 2_000)
    |> expect("Intercepted" |> by_text() |> to_be_visible())
  end

  # The handler commits in the iframe, which the wait for the main frame never hears of.
  @tag driver: :playwright
  test "Playwright submit does not count a commit in the iframe of a form targeting the top frame" do
    intercept = """
    <script>
      navigation.addEventListener('navigate', event => {
        if (event.formData) event.intercept({handler: () => { document.querySelector('h1').textContent = 'Intercepted' }})
      })
    </script>
    """

    form =
      ~s[<form id="note" method="post" action="save" target="_top" onsubmit="history.pushState({}, '', 'edited')"></form>]

    fixture =
      TestHTTPFixtures.register_sequence([
        %{body: html(~s(<h1>Draft</h1><iframe id="inner" src="frame"></iframe>) <> intercept)},
        %{body: html(form)}
      ])

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
    frame = frame_locator("#inner")

    session
    |> submit(by_css(frame, "#note"), timeout: 2_000)
    |> expect("Intercepted" |> by_text() |> to_be_visible())
  end

  # Firefox reports no response for a redirect a route fulfills, only the request
  # it redirects to. WebKit refuses to fulfill a redirect.
  @tag driver: :playwright
  @tag skip: if(playwright_engine?(:webkit), do: "WebKit cannot fulfill a redirect")
  test "Playwright submit waits for the server after a route fulfills a redirect" do
    test = self()

    fixture =
      TestHTTPFixtures.register_sequence([
        %{body: html(~s(<form id="note" method="post" action="save"></form>))},
        fn _request ->
          Process.sleep(300)
          send(test, :saved_page_served)
          %{body: html("<h1>Saved</h1>")}
        end
      ])

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))

    unwrap(session, fn page ->
      PlaywrightEx.Page.route!(page, "**/forms/save", fn route ->
        PlaywrightEx.Route.fulfill!(route, status: 302, headers: %{"location" => "saved"})
      end)
    end)

    session
    |> submit(by_css("#note"), timeout: 2_000)
    |> expect("Saved" |> by_text() |> to_be_visible())

    assert_received :saved_page_served
  end

  # Page code may reuse the name; the form navigates as usual.
  for {name, script} <- [
        {"a var named navigation", "var navigation = {}"},
        {"window.navigation assigned", "window.navigation = 1"},
        {"window.navigation deleted", "delete window.navigation"}
      ] do
    @tag driver: :playwright
    test "Playwright submit works on a page with #{name}" do
      form = ~s(<form id="note" method="post" action="save"></form><script>#{unquote(script)}</script>)
      fixture = TestHTTPFixtures.register_sequence([%{body: html(form)}, %{body: html("<h1>Saved</h1>")}])

      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> submit(by_css("#note"), timeout: 2_000)
      |> expect("Saved" |> by_text() |> to_be_visible())
    end
  end

  # updateCurrentEntry changes the entry's state without committing a navigation.
  @tag driver: :playwright
  test "Playwright submit does not count a submit handler's updateCurrentEntry" do
    intercept = """
    <script>
      navigation.addEventListener('navigate', event => {
        if (event.formData) event.intercept({handler: () => { document.querySelector('h1').textContent = 'Intercepted' }})
      })
    </script>
    """

    form =
      ~s[<h1>Draft</h1><form id="note" method="post" action="save" onsubmit="navigation.updateCurrentEntry({state: 1})"></form>]

    fixture = TestHTTPFixtures.register(%{body: html(form <> intercept)})

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
    |> submit(by_css("#note"), timeout: 2_000)
    |> expect("Intercepted" |> by_text() |> to_be_visible())

    assert [_source] = TestHTTPFixtures.requests(fixture)
  end

  # A handler's commit does not end the wait, so cancelling the navigation
  # afterwards reads as a browser that sent no request, as it does without one.
  @tag driver: :playwright
  @tag :capture_log
  test "Playwright submit names the navigation request when a page handler blocks it after pushState" do
    block = """
    <script>
      navigation.addEventListener('navigate', event => { if (event.formData) event.preventDefault() })
    </script>
    """

    form = ~s[<form id="note" method="post" action="save" onsubmit="history.pushState({}, '', 'edited')"></form>]
    fixture = TestHTTPFixtures.register(%{body: html(form <> block)})
    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))

    assert_raise Fluffy.OperationError,
                 ~r/Timeout 500ms exceeded while waiting for the submitted form's navigation request/,
                 fn -> submit(session, by_css("#note"), timeout: 500) end

    assert [_source] = TestHTTPFixtures.requests(fixture)
  end

  # Dismissing the prompt cancels the navigation; accepting it lets it go on.
  # Filling the field gives the page the user activation the prompt requires.
  for {outcome, handle, heading, requests} <- [
        {"dismissed", &Fluffy.Dialog.dismiss/1, "Draft", 1},
        {"accepted", &Fluffy.Dialog.accept/1, "Saved", 2}
      ] do
    @tag driver: :playwright
    test "Playwright submit returns when a beforeunload prompt is #{outcome}" do
      body = """
      <h1>Draft</h1><form id="note" method="post" action="save"><label>Title <input name="title"></label></form>
      <script>addEventListener('beforeunload', event => event.preventDefault())</script>
      """

      fixture = TestHTTPFixtures.register_sequence([%{body: html(body)}, %{body: html("<h1>Saved</h1>")}])

      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))
      |> fill(by_label("Title"), "Draft")
      |> once(Fluffy.Event.dialog(), unquote(handle))
      |> submit(by_css("#note"), timeout: 2_000)
      |> expect(unquote(heading) |> by_text() |> to_be_visible())

      assert length(TestHTTPFixtures.requests(fixture)) == unquote(requests)
    end
  end

  @tag driver: :playwright
  @tag :capture_log
  test "Playwright submit names the navigation request it waited for when the browser sends none" do
    body = """
    <!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="form-action 'none'"></head>
    <body><form id="note" method="post" action="save"></form></body></html>
    """

    fixture = TestHTTPFixtures.register(%{body: body})
    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))

    assert_raise Fluffy.OperationError,
                 ~r/Timeout 500ms exceeded while waiting for the submitted form's navigation request/,
                 fn ->
                   submit(session, by_css("#note"), timeout: 500)
                 end
  end

  @tag driver: :playwright
  @tag :capture_log
  test "Playwright submit names its timeout when the server does not answer in time" do
    slow = fn _request ->
      Process.sleep(1_000)
      %{body: html("<h1>Saved</h1>")}
    end

    fixture =
      TestHTTPFixtures.register_sequence([%{body: html(~s(<form id="note" method="post" action="save"></form>))}, slow])

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/forms/start"))

    assert_raise Fluffy.OperationError, ~r/Timeout 300ms exceeded while waiting for the form submission response/, fn ->
      submit(session, by_css("#note"), timeout: 300)
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body) do
    "<!doctype html><html><body><main>#{body}</main></body></html>"
  end
end
