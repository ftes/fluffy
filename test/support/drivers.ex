defmodule Fluffy.Support.Drivers do
  @moduledoc false

  # The driver sets a conformance test runs on, as `for driver <- Drivers.html() do` with
  # `@tag driver: driver`. Plain functions, compiled before the tests, so a module body can
  # call them at compile time.

  # Every page driver.
  def all, do: [:static, :live, :playwright]

  # The Phoenix drivers.
  def phoenix, do: [:static, :live]

  # The drivers `Fluffy.session_for_html/2` loads a page into (`with_html/3`): the in-process
  # DOM, which Static and LiveView share, and the browser.
  def html, do: [:static, :playwright]

  # The backends `start_session/1` takes, whose Phoenix session picks Static or LiveView
  # by the page it visits.
  def backends, do: [:phoenix, :playwright]
end
