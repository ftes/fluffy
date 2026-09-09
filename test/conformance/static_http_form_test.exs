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
