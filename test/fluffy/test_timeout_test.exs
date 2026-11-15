defmodule Fluffy.TestTimeoutTest do
  # The test timeout's backstop on its own, without waiting one out: the conformance tests
  # (`Fluffy.Conformance.TestTimeoutTest`) do that, once per driver class. The backstop comes
  # from PlaywrightEx.Test's registration of the test, so the tests run at once.
  use ExUnit.Case, async: true
  use Fluffy.Case

  alias Fluffy.TestTimeout
  alias PlaywrightEx.Test.Recorder

  # 5% of the timeout, at most 1 s, before ExUnit's deadline: the moment PlaywrightEx.Test
  # closes the test's contexts.
  for {timeout, margin} <- [{2_000, 100}, {10_000, 500}, {60_000, 1_000}] do
    @tag timeout: timeout
    test "a #{timeout}ms test's backstop is #{margin}ms before its deadline" do
      timeout = unquote(timeout)
      margin = unquote(margin)
      assert Recorder.test_timeout_margin(timeout) == margin

      %{timeout: ^timeout, deadline: deadline} = PlaywrightEx.Test.info()
      assert TestTimeout.fetch() == {timeout, deadline - margin}
    end
  end

  @tag timeout: :infinity
  test "a test without a timeout has no backstop" do
    assert TestTimeout.fetch() == nil
    assert TestTimeout.bound(:infinity) == :infinity
  end

  test "a Task of the test gets the test's backstop" do
    assert {_timeout, _backstop} = test_timeout = TestTimeout.fetch()
    assert Task.await(Task.async(&TestTimeout.fetch/0)) == test_timeout
  end

  test "a process outside the test has no backstop, so a deadline stays as it is" do
    test = self()

    spawn(fn ->
      send(test, {:outside, TestTimeout.fetch(), TestTimeout.bound(:infinity), TestTimeout.bound(42)})
    end)

    assert_receive {:outside, nil, :infinity, 42}
  end

  test "the backstop bounds a later deadline and none" do
    {_timeout, backstop} = TestTimeout.fetch()

    assert TestTimeout.bound(:infinity) == backstop
    assert TestTimeout.bound(backstop + 1) == backstop
    assert TestTimeout.bound(backstop - 1) == backstop - 1
  end

  @tag timeout: 2_000
  test "a failure at the backstop says the test timed out, as Playwright's" do
    {_timeout, backstop} = TestTimeout.fetch()

    assert TestTimeout.explain("no matching download event", backstop) ==
             "Test timeout of 2000ms exceeded.\nno matching download event"

    assert %RuntimeError{message: "Test timeout of 2000ms exceeded.\nThe trapdoor is shut"} =
             TestTimeout.explain(%RuntimeError{message: "The trapdoor is shut"}, backstop)

    # A deadline of its own, which came first.
    assert TestTimeout.explain("no matching download event", backstop - 1) == "no matching download event"
  end
end
