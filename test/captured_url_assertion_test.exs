defmodule Fluffy.CapturedURLAssertionTest do
  use ExUnit.Case, async: true

  import Fluffy.Expect, only: [expect: 2, not_: 1]

  alias Fluffy.Backend.Phoenix
  alias Fluffy.Session

  for {module, constructor, type, field} <- [
        {Fluffy.Expect, :download_to_have_url, :download, :url},
        {Fluffy.Expect, :navigation_to_have_url, :navigation, :url},
        {Fluffy.Expect, :navigation_to_have_from_url, :navigation, :from_url},
        {Fluffy.Expect, :request_to_have_url, :request, :url},
        {Fluffy.Expect, :response_to_have_url, :response, :url}
      ] do
    test "#{inspect(module)}.#{constructor} matches structured URL components" do
      url = "https://example.test/reports?tag=one&tag=two&q=hello+world#summary"

      session = %Session{
        backend: Phoenix,
        context: nil,
        pages: %{},
        active_page: nil,
        results: %{captured: %{type: unquote(type), value: %{unquote(field) => url}}}
      }

      assertion = fn expected ->
        apply(unquote(module), unquote(constructor), [:captured, expected])
      end

      for components <- [
            [path: "/reports", fragment: "summary"],
            [query: %{"q" => "hello world", "tag" => ["one", "two"]}],
            [query: %{"tag" => ["one", "two"]}, query_mode: :subset]
          ] do
        assert expect(session, assertion.(components)) == session

        assert_raise ExUnit.AssertionError, fn ->
          expect(session, components |> assertion.() |> not_())
        end
      end

      for components <- [
            [path: "/missing"],
            [fragment: nil],
            [query: %{"tag" => ["one", "two"]}],
            [query: %{"tag" => ["two", "one"]}, query_mode: :subset],
            [query: %{"tag" => "one"}, query_mode: :subset]
          ] do
        error =
          assert_raise ExUnit.AssertionError, fn ->
            expect(session, assertion.(components))
          end

        assert error.message =~ inspect(url)
        assert error.message =~ Fluffy.URLMatcher.describe(Fluffy.URLMatcher.new!(components))
        refute error.message =~ "%Fluffy.URLMatcher{"
        assert expect(session, components |> assertion.() |> not_()) == session
      end

      for invalid <- [[], [query_mode: :subset], [path: ~r/reports/]] do
        assert_raise NimbleOptions.ValidationError, fn -> assertion.(invalid) end
      end
    end

    test "#{inspect(module)}.#{constructor} matches captured URLs" do
      url = "https://example.test/reports/42?format=csv"

      session = %Session{
        backend: Phoenix,
        context: nil,
        pages: %{},
        active_page: nil,
        results: %{
          captured: %{type: unquote(type), value: %{unquote(field) => url}}
        }
      }

      assertion = fn expected ->
        apply(unquote(module), unquote(constructor), [:captured, expected])
      end

      matching = ~r{^https://example\.test/reports/\d+\?format=csv$}
      mismatching = ~r{/invoices/}

      assert expect(session, assertion.(matching)) == session
      assert expect(session, mismatching |> assertion.() |> not_()) == session
      assert expect(session, assertion.(url)) == session

      for expectation <- [
            assertion.(mismatching),
            matching |> assertion.() |> not_(),
            assertion.("/reports/42?format=csv")
          ] do
        assert_raise ExUnit.AssertionError, fn -> expect(session, expectation) end
      end
    end
  end
end
