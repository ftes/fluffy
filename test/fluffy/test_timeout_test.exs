defmodule Fluffy.TestTimeoutTest do
  # The test timeout's backstop on its own, without waiting one out: the conformance tests
  # (`Fluffy.Conformance.TestTimeoutTest`) do that, once per driver class. The backstop comes
  # from Playwright.Test's registration of the test, so the tests run at once.
  use ExUnit.Case, async: true
  use Playwright.Test

  alias Fluffy.Deadline
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

  test "a process outside the test has no backstop" do
    test = self()
    timeout = 60_000

    spawn(fn ->
      earliest = Deadline.new(timeout)
      deadline = TestTimeout.deadline(timeout)
      latest = Deadline.new(timeout)
      send(test, {:outside, TestTimeout.fetch(), TestTimeout.deadline(:infinity), deadline, earliest..latest})
    end)

    assert_receive {:outside, nil, :infinity, deadline, expected}
    assert deadline in expected
  end

  test ":once is already expired" do
    assert Deadline.expired?(TestTimeout.deadline(:once))
  end

  @tag timeout: 10_000
  test "a shorter timeout keeps its own deadline" do
    earliest = Deadline.new(100)
    deadline = TestTimeout.deadline(100)
    latest = Deadline.new(100)
    {_timeout, backstop} = TestTimeout.fetch()

    assert deadline in earliest..latest
    assert deadline < backstop
  end

  test "the backstop bounds a longer or unlimited timeout" do
    {timeout, backstop} = TestTimeout.fetch()

    assert TestTimeout.deadline(:infinity) == backstop
    assert TestTimeout.deadline(timeout + 1_000) == backstop
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
