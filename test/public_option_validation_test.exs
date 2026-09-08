defmodule Fluffy.PublicOptionValidationTest do
  use ExUnit.Case, async: true

  alias Fluffy.Event
  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Page
  alias Fluffy.Playwright

  setup do
    session = Fluffy.session_for_html(:static, "<button>Save</button>")
    %{session: session, button: Locator.by_role(:button, name: "Save")}
  end

  test "locator option values are validated when the locator is constructed" do
    assert_raise NimbleOptions.ValidationError, ~r/:exact.*boolean/, fn ->
      Locator.by_text("Save", exact: :yes)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:name.*string/, fn ->
      Locator.by_role(:button, name: 123)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:has.*Fluffy.Locator/, fn ->
      "button" |> Locator.by_css() |> Locator.filter(has: "button")
    end
  end

  test "event option values are validated when the event is constructed" do
    assert_raise NimbleOptions.ValidationError, ~r/:max_bytes.*non[- ]negative integer/, fn ->
      Event.download(:report, max_bytes: -1)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:accept/, fn ->
      Event.dialog(:confirmation, accept: :yes)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:timeout.*non[- ]negative integer/, fn ->
      Event.request(:request, "/reports", timeout: -1)
    end
  end

  test "expectation option values are validated when the expectation is constructed", %{button: button} do
    assert_raise NimbleOptions.ValidationError, ~r/:timeout.*non[- ]negative integer/, fn ->
      Expect.visible(button, timeout: -1)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:checked.*boolean/, fn ->
      Expect.checked(button, checked: :yes)
    end
  end

  test "page expectation options share expectation validation" do
    assert_raise NimbleOptions.ValidationError, ~r/:timeout.*non[- ]negative integer/, fn ->
      Page.to_have_title("Accounts", timeout: -1)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:query_mode.*:exact.*:subset/, fn ->
      Page.to_have_url(path: "/accounts", query_mode: :some)
    end

    assert_raise NimbleOptions.ValidationError, ~r/:query.*map/, fn ->
      Page.to_have_url(query: [{"id", "5"}])
    end

    assert_raise NimbleOptions.ValidationError, ~r/:timeout.*non[- ]negative integer/, fn ->
      Page.to_have_opener(:main, timeout: -1)
    end
  end

  test "page-level constructors have one explicit namespace" do
    refute function_exported?(Expect, :url, 1)
    refute function_exported?(Expect, :url, 2)
    refute function_exported?(Expect, :url, 3)
    refute function_exported?(Expect, :status, 1)
    refute function_exported?(Expect, :page_opener, 2)
    refute function_exported?(Event, :page, 1)

    assert %Expect{target: :page, kind: :url} = Page.to_have_url("/accounts")
    assert %Expect{target: :page, kind: :status} = Page.to_have_status(200)
    assert %Expect{target: :page, kind: :opener} = Page.to_have_opener(:main)
  end

  test "action options fail before reaching a driver", %{session: session, button: button} do
    assert_raise NimbleOptions.ValidationError, ~r/:timeout.*non[- ]negative integer/, fn ->
      Fluffy.click(session, button, timeout: -1)
    end

    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:mystery/, fn ->
      Fluffy.reload(session, mystery: true)
    end
  end

  test "file input bounds fail before selection preflight", %{session: session} do
    assert_raise NimbleOptions.ValidationError, ~r/:max_bytes.*non[- ]negative integer/, fn ->
      Fluffy.set_input_files(session, Locator.by_label("Upload"), "/missing", max_bytes: -1)
    end
  end

  test "Playwright evaluate options fail before the backend capability check", %{session: session} do
    assert_raise NimbleOptions.ValidationError, ~r/:is_function.*boolean/, fn ->
      Playwright.evaluate(session, "document.title", is_function: :yes)
    end
  end
end
