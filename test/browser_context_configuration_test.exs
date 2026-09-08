defmodule Fluffy.BrowserContextConfigurationTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Playwright

  test "applies typed BrowserContext options in isolated contexts on one browser" do
    origin = Fluffy.TestServer.base_url()

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
                local_storage: [%{name: "fluffy-state", value: "configured"}]
              }
            ]
          },
          timezone_id: "Europe/Berlin",
          viewport: %{width: 900, height: 700}
        ]
      )
      |> visit("/stage")

    defaults = start_session(:playwright, base_url: origin)

    refute Map.has_key?(configured.context, :browser_id)
    refute Map.has_key?(defaults.context, :browser_id)
    refute configured.context.context_id == defaults.context.context_id

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
               """,
               is_function: true
             )
  end

  test "rejects unknown and malformed BrowserContext options before creation" do
    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:page/, fn ->
      start_session(:playwright,
        base_url: Fluffy.TestServer.base_url(),
        page: [viewport: %{width: 100, height: 100}]
      )
    end

    assert_raise NimbleOptions.ValidationError,
                 ~r/:viewport.*invalid value|invalid value.*:viewport/,
                 fn ->
                   start_session(:playwright,
                     base_url: Fluffy.TestServer.base_url(),
                     browser_context: [viewport: %{width: 0, height: 700}]
                   )
                 end
  end

  test "BrowserContext options are rejected by the Phoenix backend" do
    assert_raise ArgumentError, ~r/browser_context.*Playwright/, fn ->
      start_session(:phoenix,
        endpoint: Fluffy.TestWeb.Endpoint,
        browser_context: [locale: "de-DE"]
      )
    end
  end
end
