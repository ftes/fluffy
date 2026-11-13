defmodule Fluffy.TestTimeoutTest do
  # The test timeout's backstop on its own, without waiting one out: the conformance tests
  # (`Fluffy.Conformance.TestTimeoutTest`) do that, once per driver class. The registration is
  # the test process's, so the tests run at once.
  use ExUnit.Case, async: true

  alias Fluffy.TestTimeout
  alias PlaywrightEx.Test.Recorder

  # 5% of the timeout, at most 1 s: the moment PlaywrightEx.Test closes a Playwright session's
  # context.
  for {timeout, margin} <- [{500, 25}, {2_000, 100}, {60_000, 1_000}] do
    test "a #{timeout}ms test's backstop is #{margin}ms before its timeout" do
      timeout = unquote(timeout)
      margin = unquote(margin)
      assert Recorder.test_timeout_margin(timeout) == margin

      before = System.monotonic_time(:millisecond)
      :ok = TestTimeout.put(%{timeout: timeout})
      later = System.monotonic_time(:millisecond)

      assert {^timeout, backstop} = TestTimeout.fetch()
      assert backstop in (before + timeout - margin)..(later + timeout - margin)
    end
  end

  test "a test without a timeout has no backstop" do
    :ok = TestTimeout.put(%{timeout: :infinity})
    assert TestTimeout.fetch() == nil
  end

  test "a Task of the test gets the test's backstop" do
    :ok = TestTimeout.put(%{timeout: 2_000})
    assert {2_000, _backstop} = test_timeout = TestTimeout.fetch()
    assert Task.await(Task.async(&TestTimeout.fetch/0)) == test_timeout
  end

  test "without a backstop, a deadline stays as it is" do
    assert TestTimeout.bound(:infinity) == :infinity
    assert TestTimeout.bound(42) == 42
    assert TestTimeout.explain("no matching download event", 42) == "no matching download event"
  end

  test "the backstop bounds a later deadline and none" do
    :ok = TestTimeout.put(%{timeout: 2_000})
    {_timeout, backstop} = TestTimeout.fetch()

    assert TestTimeout.bound(:infinity) == backstop
    assert TestTimeout.bound(backstop + 1) == backstop
    assert TestTimeout.bound(backstop - 1) == backstop - 1
  end

  test "a failure at the backstop says the test timed out, as Playwright's" do
    :ok = TestTimeout.put(%{timeout: 2_000})
    {_timeout, backstop} = TestTimeout.fetch()

    assert TestTimeout.explain("no matching download event", backstop) ==
             "Test timeout of 2000ms exceeded.\nno matching download event"

    assert %RuntimeError{message: "Test timeout of 2000ms exceeded.\nThe trapdoor is shut"} =
             TestTimeout.explain(%RuntimeError{message: "The trapdoor is shut"}, backstop)

    # A deadline of its own, which came first.
    assert TestTimeout.explain("no matching download event", backstop - 1) == "no matching download event"
  end
end
