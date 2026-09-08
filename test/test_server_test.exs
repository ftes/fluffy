defmodule Fluffy.TestServerTest do
  use Fluffy.TestCase, async: true

  test "serves a health response from its leased loopback port" do
    url = Fluffy.TestServer.base_url() <> "/health"

    assert {:ok, {{_http_version, 200, ~c"OK"}, _headers, ~c"ok"}} =
             :httpc.request(String.to_charlist(url))
  end
end
