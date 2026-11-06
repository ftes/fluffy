defmodule Fluffy.FailureArtifact do
  @moduledoc false

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Session
  alias Fluffy.TestScope

  def capture(session, operation, error, stacktrace, directory \\ configured_directory())

  def capture(_session, _operation, _error, _stacktrace, nil), do: :disabled

  def capture(%Session{} = session, operation, error, stacktrace, directory) do
    File.mkdir_p!(directory)
    stem = artifact_stem(session, operation)
    page = Session.page_state(session).page

    # Content has no timeout and waits while a script blocks the page.
    with {:ok, {:ok, html}} <- Bounded.within(2_000, fn -> PlaywrightEx.Page.content(page) end) do
      File.write!(Path.join(directory, stem <> ".html"), html)
    end

    PlaywrightEx.Page.screenshot(page, path: Path.join(directory, stem <> ".png"), full_page: true, timeout: 2_000)

    File.write!(
      Path.join(directory, stem <> ".txt"),
      Exception.format(:error, error, stacktrace)
    )

    :ok
  rescue
    _artifact_error -> :error
  catch
    _kind, _artifact_error -> :error
  end

  defp artifact_stem(session, operation) do
    unique = System.unique_integer([:positive, :monotonic])
    prefix = test_prefix(session)
    Enum.join(Enum.reject([prefix, operation, unique], &is_nil/1), "-")
  end

  defp test_prefix(session) do
    if scope = Session.context(session).resource_scope do
      context = TestScope.metadata(scope)
      module = context |> Map.get(:module) |> inspect()
      slug("#{module} #{Map.get(context, :test)}")
    end
  catch
    :exit, _reason -> nil
  end

  defp slug(value) do
    value
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp configured_directory do
    :fluffy
    |> Application.get_env(:playwright, [])
    |> Keyword.get(:artifact_dir)
  end
end
