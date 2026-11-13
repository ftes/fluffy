defmodule Fluffy.Conformance.TemplateContentTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # A template's content lives outside the document: no locator finds it, and it
  # adds nothing to the text of the elements around it.
  @html """
  <p>Shown</p>
  <template>
    <p>Shown</p>
    <button>Ghost button</button>
    <label>Ghost <input></label>
    <img alt="Ghost" title="Ghost" data-testid="ghost">
    <input placeholder="Ghost">
  </template>
  <div id="outer">Outer<template> Inner</template></div>
  <label>Name<template> Nick</template> <input></label>
  <span id="mail">Email<template> Address</template></span><input aria-labelledby="mail">
  <button>Go<template> away</template></button>
  """

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "ignores template content with #{driver}" do
      unquote(driver)
      |> session_for_html(@html, base_url: Fluffy.Support.Server.base_url())
      |> expect("Shown" |> by_text(exact: true) |> to_have_count(1))
      |> expect("Outer" |> by_text(exact: true) |> to_have_count(1))
      |> expect("Inner" |> by_text() |> to_have_count(0))
      |> expect("div" |> by_css() |> filter(has_text: "Inner") |> to_have_count(0))
      |> expect("#outer" |> by_css() |> to_have_text("Outer"))
      |> expect("template p, template button" |> by_css() |> to_have_count(0))
      |> expect("Name" |> by_label(exact: true) |> to_have_count(1))
      |> expect("Nick" |> by_label() |> to_have_count(0))
      |> expect("Email" |> by_label(exact: true) |> to_have_count(1))
      |> expect("Address" |> by_label() |> to_have_count(0))
      |> expect(:button |> by_role(name: "Go", exact: true) |> to_have_count(1))
      |> expect(:button |> by_role(name: "Ghost button") |> to_have_count(0))
      |> expect("Ghost" |> by_label() |> to_have_count(0))
      |> expect("Ghost" |> by_alt_text() |> to_have_count(0))
      |> expect("Ghost" |> by_title() |> to_have_count(0))
      |> expect("ghost" |> by_test_id() |> to_have_count(0))
      |> expect("Ghost" |> by_placeholder() |> to_have_count(0))
    end
  end
end
