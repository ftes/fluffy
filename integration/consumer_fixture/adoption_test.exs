defmodule FluffyConsumer.AdoptionTest do
  use FluffyConsumerWeb.ConnCase, async: true
  use Playwright.Test
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Event

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "one vanilla ExUnit scenario runs with #{backend}", %{session: session} do
      session
      |> visit("/")
      |> assert(by_role(:heading, name: "Platform Nine and Three-Quarters") |> count(1))
      |> click(by_role(:link, name: "Board the Hogwarts Express"))
      |> assert(by_text("Welcome to Hogwarts") |> visible())
      |> assert(page_url("/hogwarts"))
    end

    @tag backend: backend
    test "download events compose with ordinary assertions using #{backend}", %{session: session} do
      session
      |> visit("/")
      |> assert_event(
        Event.download(),
        &click(&1, by_role(:link, name: "Marauder's Map")),
        fn download ->
          assert download.suggested_filename == "marauders_map.csv"
          assert Fluffy.Download.read(download) == "student,house\nHermione,Gryffindor\n"
        end
      )
      |> assert(page_url("/"))
    end

    @tag backend: backend
    test "the public native escape hatch remains pipeable with #{backend}", %{session: session} do
      session
      |> visit("/")
      |> unwrap(fn
        %Plug.Conn{} = conn ->
          %{
            conn
            | resp_body:
                String.replace(
                  conn.resp_body,
                  "Platform Nine and Three-Quarters",
                  "Mischief managed"
                )
          }

        %Playwright.Page{} = page ->
          Playwright.Page.evaluate!(
            page,
            "document.querySelector('h1').textContent = 'Mischief managed'"
          )
      end)
      |> assert(by_text("Mischief managed") |> visible())
    end
  end
end
