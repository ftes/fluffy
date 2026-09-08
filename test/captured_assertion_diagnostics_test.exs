defmodule Fluffy.CapturedAssertionDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Fluffy.Download
  alias Fluffy.Expect
  alias Fluffy.Response

  test "captured assertions name their subject only once, including under negation" do
    expectation = Download.to_have_content_type(:report, "text/csv")

    assert Expect.describe(expectation) == ~s(download :report to have content type "text/csv")

    assert expectation |> Fluffy.not_() |> Expect.describe() ==
             ~s(not download :report to have content type "text/csv")
  end

  test "response diagnostics distinguish request metadata from the response body" do
    assert :save |> Response.to_have_request_method("POST") |> Expect.describe() ==
             ~s(response :save to have request method "POST")

    assert :save |> Response.to_have_request_post_data("payload") |> Expect.describe() ==
             ~s(response :save to have request post data "payload")
  end
end
