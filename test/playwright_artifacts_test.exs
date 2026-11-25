defmodule Fluffy.PlaywrightArtifactsTest.TraceCase do
  # Playwright.Test writes `trace.zip` in the `on_exit` its registration adds. A case
  # template's `setup` runs before the `use Playwright.Test` of its `using`, so this `on_exit` is
  # added before that one and runs after it, reading the path the test's setup puts in.
  @moduledoc false
  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)
    end
  end

  setup context do
    {:ok, path} = Agent.start(fn -> nil end)

    on_exit(fn ->
      path = Agent.get(path, & &1)
      {:ok, entries} = :zip.extract(String.to_charlist(path), [:memory])
      File.rm_rf!(Path.dirname(path))
      trace = Enum.map_join(entries, "\n", fn {_name, contents} -> contents end)
      for expected <- context[:trace_has] || [], do: assert(trace =~ expected)
      for unexpected <- context[:trace_lacks] || [], do: refute(trace =~ unexpected)

      methods = action_methods(entries)
      for expected <- context[:actions_has] || [], do: assert(expected in methods)
      for unexpected <- context[:actions_lack] || [], do: refute(unexpected in methods)
    end)

    %{trace_path: path}
  end

  # The protocol methods of the actions the browser recorded, in every context's `trace.trace`
  # (the archive prefixes each one's), each with its snapshots; `test.trace` holds the test's steps.
  defp action_methods(entries) do
    for {name, contents} <- entries,
        name = List.to_string(name),
        String.ends_with?(name, ".trace") and Path.basename(name) != "test.trace",
        line <- String.split(contents, "\n", trim: true),
        %{"type" => "before", "method" => method} <- [JSON.decode!(line)],
        do: method
  end
end

defmodule Fluffy.PlaywrightArtifactsTest do
  # Fluffy's side of Playwright.Test's recording: the contexts of a test's sessions are
  # the test's, and steps are its test steps.
  use ExUnit.Case, async: true
  use Fluffy.PlaywrightArtifactsTest.TraceCase

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.FilePayload
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server

  # Derived, so the trace's copy of this source file does not contain it.
  @secret "FLUFFY-" <> Base.encode16("upload secret of gringotts")

  @subtitle "past the harp"

  @moduletag Playwright.Test.use(trace: :on)

  setup %{trace_path: path} do
    trace_path = Playwright.Test.output_path("trace.zip")
    Agent.update(path, fn _ -> trace_path end)
  end

  @tag trace_has: [
         ~s("method":"goto"),
         ~s(internal:role=button[name=\\"Open popup\\"i]),
         ~s(Traced popup),
         ~s("url":"/stage")
       ]
  test "records every page of every session into the test's trace" do
    fixture =
      HTTPFixtures.register(fn request ->
        case request.path do
          "/start" -> %{body: html(~s|<button onclick="window.open('popup')">Open popup</button>|)}
          "/popup" -> %{body: html("<h1>Traced popup</h1>")}
        end
      end)

    :playwright
    |> start_session(base_url: Server.base_url())
    |> visit(HTTPFixtures.path(fixture, "/start"))
    |> then(fn session ->
      pending = wait_for(session, Event.popup())
      click(session, by_role(:button, name: "Open popup"))
      switch_page(session, await(pending))
    end)
    |> expect("Traced popup" |> by_text() |> to_be_visible())

    :playwright |> start_session(base_url: Server.base_url()) |> visit("/stage")
  end

  # Fluffy's own calls around them (its document probes and LiveView waits) are internal: no
  # actions, so no snapshots.
  @tag actions_has: ["goto", "click", "expect"], actions_lack: ["evaluateExpression", "waitForFunction", "addInitScript"]
  test "records the test's actions but not Fluffy's own calls" do
    :playwright
    |> start_session(base_url: Server.base_url())
    |> visit("/live/three-heads")
    |> click(by_role(:button, name: "Play the flute"))
    |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())
  end

  @tag trace_has: ["Outer workflow", "Inner operation", Path.absname(__ENV__.file)]
  test "records steps as nested test steps with source locations" do
    :playwright
    |> start_session(base_url: Server.base_url())
    |> visit("/stage")
    |> step("Outer workflow", fn session ->
      step(session, "Inner operation", fn session ->
        Fluffy.Playwright.evaluate(session, "document.body.dataset.stepped = 'yes'")
        session
      end)
    end)
  end

  @tag trace_has: ["Approach Fluffy", "Tiptoe in", ~s("subtitle":"#{@subtitle}"), Path.absname(__ENV__.file)]
  test "records a Phoenix session's steps with Playwright.Test.step's options" do
    :phoenix
    |> start_session(endpoint: Fluffy.Support.Web.Endpoint)
    |> step("Approach Fluffy", fn session ->
      step(session, "Tiptoe in", &visit(&1, "/chamber"), subtitle: @subtitle)
    end)
  end

  @tag trace_has: ["set_input_files", "setInputFiles"], trace_lacks: [@secret]
  test "does not copy in-memory upload contents into the trace" do
    :playwright
    |> session_for_html(~s(<label>Attachment <input type="file"></label>), base_url: Server.base_url())
    |> set_input_files(by_label("Attachment"), %FilePayload{
      name: "private.txt",
      bytes: @secret,
      content_type: "text/plain"
    })
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end

defmodule Fluffy.PlaywrightArtifactsTest.UseOptionsTest do
  # `use Playwright.Test, trace: :on`, forwarded from a template's `using`, records with no tag.
  use Fluffy.PlaywrightArtifactsTest.TraceCase, async: true, trace: :on

  import Fluffy

  setup %{trace_path: path} do
    trace_path = Playwright.Test.output_path("trace.zip")
    Agent.update(path, fn _ -> trace_path end)
  end

  @tag trace_has: [~s("method":"goto")]
  test "records the trace of its option" do
    :playwright |> start_session(base_url: Fluffy.Support.Server.base_url()) |> visit("/stage")
  end
end

defmodule Fluffy.PlaywrightArtifactsTest.AssertStepsTest do
  # `use Fluffy.Assert` after a template's `use Playwright.Test`: its assertions record steps,
  # ExUnit's and Fluffy's own with a message, and typed expectations still run.
  use Fluffy.PlaywrightArtifactsTest.TraceCase, async: true, trace: :on
  use Fluffy.Assert

  import Fluffy.Locator

  setup %{trace_path: path} do
    trace_path = Playwright.Test.output_path("trace.zip")
    Agent.update(path, fn _ -> trace_path end)
  end

  # Derived, as the trace's copy of this source file would match a literal title.
  @owl "An owl reaches " <> "Privet Drive"
  @howler "No howler " <> "today"
  @sum "2 + 2" <> " == 4"
  @product "3 * 3" <> " == 9"
  @fluffy_variable "val" <> "ue"

  # With the caller's expression, not Fluffy's (`value`), and `refute match?` once.
  @tag trace_has: [
         ~s(Expect \\"assert\\"),
         ~s("title":"#{@owl}"),
         ~s("expression":"#{@sum}"),
         ~s("expression":"#{@product}"),
         ~s("title":"#{@howler}")
       ],
       trace_lacks: [~s("expression":"#{@fluffy_variable}")]
  test "records ExUnit assertions and Fluffy's with a message as steps" do
    assert 1 + 1 == 2
    assert(2 + 2 == 4, @owl)
    assert(3 * 3 == 9, "Hedwig #{:flies}")
    refute(nil, @howler)
    refute match?({:ok, _}, Process.get(:owl_post))

    :static |> Fluffy.session_for_html("<p>Hedwig</p>") |> assert(visible(by_text("Hedwig")))
  end

  @letter "A letter " <> "for Harry"

  # Each is Playwright's matcher step, with the assertions in it as steps of their own.
  @tag trace_has: [~s(Expect \\"toPass\\"), ~s(Expect \\"poll assert\\"), ~s("title":"#{@letter}")]
  test "records pass and poll as steps" do
    :static
    |> Fluffy.session_for_html("<p>Hedwig</p>")
    |> assert(
      pass(fn session ->
        assert(:letter, @letter)
        assert(session, visible(by_text("Hedwig")), timeout: 0)
      end)
    )
    |> assert(poll(fn _session -> 1 end, &assert(&1 == 1)))
  end
end

defmodule Fluffy.PlaywrightArtifactsTest.AssertStepsOffTest do
  # With `assert_steps: false`, `use Fluffy.Assert` imports ExUnit's assertions: no steps.
  use Fluffy.PlaywrightArtifactsTest.TraceCase, async: true, trace: :on, assert_steps: false
  use Fluffy.Assert

  import Fluffy.Locator

  setup %{trace_path: path} do
    trace_path = Playwright.Test.output_path("trace.zip")
    Agent.update(path, fn _ -> trace_path end)
  end

  @owl "An owl reaches " <> "Privet Drive"

  @tag trace_lacks: [~s(Expect \\"assert\\"), @owl]
  test "records no assertion steps" do
    assert 1 + 1 == 2
    assert(:letter, @owl)

    :static |> Fluffy.session_for_html("<p>Hedwig</p>") |> assert(visible(by_text("Hedwig")))
  end
end
