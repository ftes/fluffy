defmodule Fluffy.TestTimeoutTest do
  # The test timeout's backstop on its own, without waiting one out: the conformance tests
  # (`Fluffy.Conformance.TestTimeoutTest`) do that, once per driver class. The backstop comes
  # from Playwright.Test's registration of the test, so the tests run at once.
  use ExUnit.Case, async: true
  use Fluffy.Case

  alias Fluffy.TestTimeout

  @tag timeout: 10_000
  test "a test's backstop is when Playwright.Test closes its contexts" do
    %{timeout: 10_000, close_deadline: close_deadline} = Playwright.Test.info()
    assert TestTimeout.fetch() == {10_000, close_deadline}
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
