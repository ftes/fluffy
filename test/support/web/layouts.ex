defmodule Fluffy.TestWeb.Layouts do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={@csrf_token} />
        <.live_title default="Fluffy's enchanted stage">
          {assigns[:page_title]}
        </.live_title>
        <script type="module" src="/assets/test_browser.js">
        </script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end

  def kennel(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={@csrf_token} />
        <.live_title prefix="Kennel · " default="Den">
          {assigns[:page_title]}
        </.live_title>
        <script type="module" src="/assets/test_browser.js">
        </script>
      </head>
      <body>
        <nav role="navigation" aria-label="Kennel">
          <.link navigate="/live/kennel/kitchen">Kitchen</.link>
          <.link patch="/live/kennel?yard=garden">Garden</.link>
          <a href="/chamber">Chamber</a>
          <button type="button" phx-click="bark" phx-value-volume="loud">Bark</button>
          <form phx-submit="whistle">
            <input name="tune" aria-label="Tune" />
            <button>Whistle</button>
          </form>
        </nav>
        {@inner_content}
        <aside id="portal-root"></aside>
        {live_render(@conn, Fluffy.TestWeb.KennelSidebarLive, id: "kennel-sidebar", sticky: true)}
      </body>
    </html>
    """
  end
end
