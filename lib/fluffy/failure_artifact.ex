defmodule Fluffy.FailureArtifact do
  @moduledoc false

  alias Fluffy.Playwright.Screenshot
  alias Fluffy.Session
  alias Fluffy.TestScope
  alias PlaywrightEx.Frame

  def capture(session, operation, error, stacktrace, directory \\ configured_directory())

  def capture(_session, _operation, _error, _stacktrace, nil), do: :disabled

  def capture(%Session{} = session, operation, error, stacktrace, directory) do
    File.mkdir_p!(directory)
    stem = artifact_stem(session, operation)
    state = Session.page_state(session)
    timeout = min(Map.get(Session.context(session), :timeout, 2_000), 2_000)

    write_content(state.frame_id, Path.join(directory, stem <> ".html"), timeout)

    Screenshot.write(
      state.page_id,
      Path.join(directory, stem <> ".png"),
      full_page: true,
      connection: Session.context(session).connection,
      timeout: timeout
    )

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

  defp write_content(frame_id, path, timeout) do
    case Frame.content(frame_id, timeout: timeout) do
      {:ok, html} -> File.write!(path, html)
      {:error, _reason} -> :error
    end
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
