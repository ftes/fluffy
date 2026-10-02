defmodule Fluffy.Conformance.FrameEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Event
  alias Fluffy.Frame
  alias Fluffy.Playwright

  @tag driver: :playwright
  test "main-frame events return a live handle with its owning page and no parent" do
    session = session_for_html(:playwright, "<h1>Main</h1>")
    pending = wait_for(session, Event.frame_navigated())
    Playwright.evaluate(session, "location.hash = 'first'; true")
    frame = await(pending)
    assert Frame.url(frame) =~ "#first"
    assert Frame.page(frame) == current_page(session)
    assert Frame.parent_frame(frame) == nil
    Playwright.evaluate(session, "location.hash = 'second'; true")
    assert Frame.url(frame) =~ "#second"
  end

  @tag driver: :playwright
  test "observes newly created and existing child frames while excluding other pages" do
    session = session_for_html(:playwright, "<h1>Main</h1>")
    pending = wait_for(session, Event.frame_navigated(&(Frame.url(&1) == "about:srcdoc")))

    Playwright.evaluate(session, """
    (() => {
      const frame = document.createElement('iframe');
      frame.srcdoc = '<p>Child</p>';
      document.body.appendChild(frame);
    })()
    """)

    child = await(pending)
    assert Frame.page(child) == current_page(session)
    parent = Frame.parent_frame(child)
    assert Frame.page(parent) == current_page(session)
    assert Frame.parent_frame(parent) == nil

    pending = wait_for(session, Event.frame_navigated())
    other = switch_page(session, new_page(session))
    Playwright.evaluate(other, "location.hash = 'other'; true")
    Playwright.evaluate(session, "document.querySelector('iframe').contentWindow.location.hash = 'updated'; true")
    assert await(pending) == child
    assert Frame.url(child) == "about:srcdoc#updated"
  end

  test "frame navigation events are browser-only" do
    session = session_for_html(:static, "<p>Main</p>")
    assert_raise Fluffy.CapabilityError, fn -> wait_for(session, Event.frame_navigated()) end
  end
end
