defmodule Fluffy.Conformance.LiveReadinessErrorTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  @tag driver: :playwright
  test "names the destination, page, frame, and expected marker on a readiness timeout" do
    session =
      start_session(:playwright,
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Fluffy.TestWeb.Endpoint,
        timeout: 1_000
      )

    error =
      assert_raise RuntimeError, fn ->
        visit(session, "/actions/disconnected-live-root")
      end

    assert error.message =~ "/actions/disconnected-live-root"
    assert error.message =~ "page \""
    assert error.message =~ "frame \""
    assert error.message =~ "[data-phx-main].phx-connected"
  end
end
