defmodule Fluffy.TestTimeoutTest do
  # The test timeout's backstop on its own, without waiting one out: the conformance tests
  # (`Fluffy.Conformance.TestTimeoutTest`) do that, once per driver class. The backstop comes
  # from Playwright.Test's registration of the test, so the tests run at once.
  use ExUnit.Case, async: true
  use Playwright.Test

  alias Fluffy.TestTimeout

  @tag timeout: 10_000
  test "a test's backstop is when Playwright.Test closes its contexts" do
    %{timeout: 10_000, deadline: deadline} = Playwright.Test.info()
    assert TestTimeout.fetch() == {10_000, deadline}
  end

  @tag timeout: :infinity
  test "a test without a timeout has no backstop" do
    assert TestTimeout.fetch() == nil
    assert TestTimeout.deadline(:infinity) == :infinity
  end

  test "a Task of the test gets the test's backstop" do
    assert {_timeout, _backstop} = test_timeout = TestTimeout.fetch()
    assert Task.await(Task.async(&TestTimeout.fetch/0)) == test_timeout
  end

  test "a process outside the test has no backstop, so a deadline stays as it is" do
    test = self()

    spawn(fn ->
      before = System.monotonic_time(:millisecond)
      outside = {:outside, TestTimeout.fetch(), TestTimeout.deadline(:infinity), TestTimeout.deadline(42)}
      send(test, {outside, before, System.monotonic_time(:millisecond)})
    end)

    assert_receive {{:outside, nil, :infinity, deadline}, before, later}
    assert deadline in (before + 42)..(later + 42)
  end

  test "the backstop bounds a later deadline and none" do
    {_timeout, backstop} = TestTimeout.fetch()
    remaining = Fluffy.Deadline.remaining(backstop)

    assert TestTimeout.deadline(:infinity) == backstop
    assert TestTimeout.deadline(remaining + 1_000) == backstop
    assert TestTimeout.deadline(0) < backstop
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
