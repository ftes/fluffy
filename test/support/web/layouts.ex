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
end
