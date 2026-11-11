defmodule Fluffy.TestWeb.ExpectationsLive do
  @moduledoc false

  use Phoenix.LiveView

  # The same markup is asserted on Static, LiveView and Playwright.
  @markup """
  <p id="spaced">  Sleeping
       <b>dragon</b>  </p>
  <p id="noise">Seen<script>var skipped = true;</script><style>.skipped {}</style><noscript>skipped</noscript><!-- skipped --><template>skipped</template></p>
  <form id="buttons"><input type="submit" value="Send"><input type="text" value="ignored"><input type="reset" value="Clear"></form>
  <p id="inline"><b>a</b> <i>b</i></p>
  <p id="rendered">Shown<span style="display: none">Concealed</span></p>
  <ul>
    <li class="item first">One</li>
    <li class="item">Two</li>
    <li class="item last">Three</li>
  </ul>
  <a id="link" href="/chamber" data-Note="Lumos  Maxima" data-flag>Go</a>
  <div id="classy" class="middle  selected row"></div>
  <div id="plain"></div>
  <div id="blank">
  </div>
  <div id="comment"><!-- skipped --></div>
  <input id="vacant">
  <input id="filled" value="x">
  <textarea id="area"></textarea>
  <textarea id="area-filled">x</textarea>
  <textarea id="area-blank">   </textarea>
  <p id="concealed" hidden>Secret</p>
  <div hidden><p id="nested-concealed">Secret</p></div>
  <input id="hidden-input" type="hidden" value="secret">
  <svg id="vector" viewBox="0 0 10 10"></svg>
  """

  def markup, do: @markup

  # With `?delay=`, each element below reaches its final state one tick after the last.
  @impl true
  def mount(params, _session, socket) do
    delay = params |> Map.get("delay", "0") |> String.to_integer()

    if connected?(socket) and delay > 0 do
      Process.send_after(self(), :tick, delay)
    end

    {:ok, assign(socket, delay: delay, step: 0)}
  end

  @impl true
  def handle_info(:tick, socket) do
    if socket.assigns.step < 9 do
      Process.send_after(self(), :tick, socket.assigns.delay)
    end

    {:noreply, assign(socket, :step, socket.assigns.step + 1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      {Phoenix.HTML.raw(markup())}
      <section :if={@delay > 0}>
        <p data-testid="text">{if @step >= 1, do: "ready", else: "waiting"}</p>
        <p data-testid="contain-text">{if @step >= 2, do: "now ready", else: "still waiting"}</p>
        <p data-testid="attribute" data-state={if @step >= 3, do: "ready", else: "waiting"}></p>
        <p data-testid="class" class={if @step >= 4, do: "ready", else: "waiting"}></p>
        <p data-testid="contain-class" class={if @step >= 5, do: "base ready", else: "base waiting"}>
        </p>
        <p data-testid="id" id={if @step >= 6, do: "ready", else: "waiting"}></p>
        <p :if={@step >= 7} data-testid="attached"></p>
        <p data-testid="hidden" hidden={@step >= 8}></p>
        <p data-testid="empty">{if @step < 9, do: "content"}</p>
      </section>
    </main>
    """
  end
end
