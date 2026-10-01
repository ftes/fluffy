defmodule FluffyConsumer.AdoptionTest do
  use ExUnit.Case, async: true
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  setup context do
    Fluffy.Test.setup(context)
  end

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "one vanilla ExUnit scenario runs with #{backend}", %{backend: backend} do
      session = start_session(backend)

      session
      |> visit("/")
      |> assert(by_role(:heading, name: "External consumer") |> count(1))
      |> click(by_role(:link, name: "Continue"))
      |> assert(by_text("Consumer complete") |> visible())
      |> assert(page_url("/complete"))
    end

    @tag backend: backend
    test "download events compose with ordinary assertions using #{backend}", %{backend: backend} do
      backend
      |> start_session()
      |> visit("/")
      |> assert_event(
        Fluffy.Event.download(),
        &click(&1, by_role(:link, name: "Download report")),
        fn download ->
          assert download.suggested_filename == "report.csv"
          assert Fluffy.Download.read!(download) == "id,total\n1,42\n"
        end
      )
      |> assert(page_url("/"))
    end

    @tag backend: backend
    test "the public native escape hatch remains pipeable with #{backend}", %{backend: backend} do
      session = start_session(backend)

      session
      |> visit("/")
      |> unwrap(fn
        %Plug.Conn{} = conn ->
          %{
            conn
            | resp_body: String.replace(conn.resp_body, "External consumer", "Native result")
          }

        %Fluffy.Playwright.Handle{} = handle ->
          {:ok, _result} =
            PlaywrightEx.Frame.evaluate(handle.frame_id,
              expression: "document.querySelector('h1').textContent = 'Native result'",
              connection: handle.connection,
              timeout: handle.timeout
            )
      end)
      |> assert(by_text("Native result") |> visible())
    end
  end
end
