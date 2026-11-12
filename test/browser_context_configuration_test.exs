defmodule Fluffy.BrowserContextConfigurationTest do
  use Fluffy.Support.Case, async: true

  import Fluffy

  alias Fluffy.Playwright
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint
  alias PlaywrightEx.Test.BrowserPool

  test "applies typed BrowserContext options in isolated contexts on one browser" do
    origin = Server.base_url()

    configured =
      :playwright
      |> start_session(
        base_url: origin,
        browser_context: [
          color_scheme: :dark,
          locale: "de-DE",
          permissions: ["geolocation"],
          storage_state: %{
            cookies: [],
            origins: [
              %{
                origin: origin,
                localStorage: [%{name: "fluffy-state", value: "configured"}]
              }
            ]
          },
          timezone_id: "Europe/Berlin",
          viewport: %{width: 900, height: 700}
        ]
      )
      |> visit("/stage")

    defaults = start_session(:playwright, base_url: origin)

    refute Map.has_key?(Fluffy.Session.context(configured), :browser_id)
    refute Map.has_key?(Fluffy.Session.context(defaults), :browser_id)
    refute Fluffy.Session.context(configured).browser_context == Fluffy.Session.context(defaults).browser_context

    assert %{
             "color_scheme" => true,
             "height" => 700,
             "language" => "de-DE",
             "permission" => "granted",
             "storage" => "configured",
             "timezone" => "Europe/Berlin",
             "width" => 900
           } =
             Playwright.evaluate(
               configured,
               """
               async () => ({
                 color_scheme: matchMedia('(prefers-color-scheme: dark)').matches,
                 height: innerHeight,
                 language: navigator.language,
                 permission: (await navigator.permissions.query({name: 'geolocation'})).state,
                 storage: localStorage.getItem('fluffy-state'),
                 timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                 width: innerWidth
               })
               """
             )

    # Playwright Test's default locale.
    assert Playwright.evaluate(defaults, "navigator.language") == "en-US"
  end

  test "rejects unknown session and BrowserContext options before creation" do
    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:page/, fn ->
      start_session(:playwright,
        base_url: Server.base_url(),
        page: [viewport: %{width: 100, height: 100}]
      )
    end

    assert_raise ArgumentError, ~r/mystery/, fn ->
      start_session(:playwright, base_url: Server.base_url(), browser_context: [mystery: true])
    end
  end

  test "BrowserContext options are rejected by the Phoenix backend" do
    assert_raise ArgumentError, ~r/browser_context.*Playwright/, fn ->
      start_session(:phoenix,
        endpoint: Endpoint,
        browser_context: [locale: "de-DE"]
      )
    end

    assert_raise ArgumentError, ~r/browser.*Playwright/, fn ->
      start_session(:phoenix, endpoint: Endpoint, browser: BrowserPool.shared())
    end
  end

  test "creates the context in the browser: given, else in the default one" do
    browser = BrowserPool.exclusive()
    session = start_session(:playwright, base_url: Server.base_url(), browser: browser)
    assert Fluffy.Session.context(session).browser_context.guid in browser_context_guids(browser)

    # On Firefox, the suite's default is this test's exclusive browser too.
    default = start_session(:playwright, base_url: Server.base_url())
    in_browser? = Fluffy.Session.context(default).browser_context.guid in browser_context_guids(browser)
    assert in_browser? == playwright_engine?(:firefox)
  end
end
