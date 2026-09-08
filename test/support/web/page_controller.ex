defmodule Fluffy.TestWeb.PageController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  alias Fluffy.TestRepo

  def health(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  def harness(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Fluffy test stage</title>
        <script type="module" src="/assets/test_browser.js"></script>
      </head>
      <body><main id="fluffy-test-root"></main></body>
    </html>
    """)
  end

  def static(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Sleeping chamber</title></head>
      <body><main><h1>The guardian sleeps</h1><p>The flute has done its work.</p></main></body>
    </html>
    """)
  end

  def redirect_live_ready(conn, %{"topic" => topic}) do
    redirect(conn, to: "/live/redirect-ready?topic=#{URI.encode_www_form(topic)}")
  end

  def click_source(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Chamber entrance</title></head>
      <body><main><a href="/chamber">Enter the chamber</a></main></body>
    </html>
    """)
  end

  def live_source(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Live chamber entrance</title></head>
      <body><main><a href="/live/chamber-map">Enter the live chamber</a></main></body>
    </html>
    """)
  end

  def client_navigation(conn, %{"topic" => topic}) do
    destination = "/live/redirect-ready?topic=#{URI.encode_www_form(topic)}"

    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Client navigation</title></head>
      <body>
        <main>
          <button type="button" onclick="location.assign('#{destination}')">Assign ready</button>
          <button type="button" onclick="location.replace('#{destination}')">Replace ready</button>
        </main>
      </body>
    </html>
    """)
  end

  def history_source(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Secret passage entrance</title></head>
      <body><main><button type="button" onclick="location.assign('/actions/history-target')">Open secret passage</button></main></body>
    </html>
    """)
  end

  def history_target(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Hidden chamber</title></head>
      <body><main><button type="button" onclick="history.back()">Back to chamber entrance</button></main></body>
    </html>
    """)
  end

  def disconnected_live_root(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Sleeping Live guardian</title></head>
      <body><main data-phx-main>The guardian is disconnected</main></body>
    </html>
    """)
  end

  def history_push_state(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Enchanted passage</title></head>
      <body>
        <main>
          <button type="button" onclick="this.closest('main').setAttribute('data-phx-main', ''); history.pushState({}, '', '?step=pushed')">Reveal secret passage</button>
        </main>
      </body>
    </html>
    """)
  end

  def session_start(conn, params) do
    conn
    |> put_session(:identity, params["identity"] || "anonymous")
    |> redirect(to: "/live/session")
  end

  def session_show(conn, _params) do
    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Static session</title></head>
      <body><main><p>Static identity: #{get_session(conn, :identity)}</p></main></body>
    </html>
    """)
  end

  def initial_connection_static(conn, _params) do
    principal = conn.assigns.initial_principal

    send_html(conn, "<main>Static initial principal: #{principal}</main>")
  end

  def initial_connection_redirect(conn, _params) do
    principal = conn.assigns.initial_principal

    conn
    |> put_session(:redirect_principal, principal)
    |> redirect(to: "/initial-connection/redirected")
  end

  def initial_connection_redirected(conn, _params) do
    case get_session(conn, :redirect_principal) do
      nil -> send_html(conn, "<main>Initial authorization required</main>", 403)
      principal -> send_html(conn, "<main>Redirected cookie principal: #{principal}</main>")
    end
  end

  def database(conn, _params) do
    %{rows: rows} = TestRepo.query!("SELECT value FROM fluffy_records ORDER BY value")
    values = Enum.map_join(rows, ", ", &hd/1)

    send_html(conn, """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Database fixture</title></head>
      <body>
        <main>
          <p>Static values: #{values}</p>
          <a href="/live/database">Open database LiveView</a>
        </main>
      </body>
    </html>
    """)
  end

  def databases(conn, _params) do
    %{rows: [[first]]} = TestRepo.query!("SELECT current_database()")
    %{rows: [[second]]} = Fluffy.TestRepoTwo.query!("SELECT current_database()")
    send_html(conn, "<main>Repos: #{first}, #{second}</main>")
  end

  defp send_html(conn, html, status \\ 200) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
  end
end
