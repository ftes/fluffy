defmodule Fluffy.AssertTest do
  use ExUnit.Case, async: true
  use Fluffy.Assert

  test "ordinary ExUnit assertions retain values, patterns, and messages" do
    assert {:ok, value} = {:ok, 42}
    assert value == 42
    assert {:ok, other} = {:ok, 43}, "binds with a message"
    assert other == 43
    assert {:ok, ^value} = {:ok, 42}, "supports pins"
    refute false
    refute nil, "supports refute messages"
    refute match?({:error, _}, {:ok, 42}), "supports pattern checks"
    assert assert(:truthy) == :truthy
    assert assert(:truthy, "message") == true

    error = assert_raise ExUnit.AssertionError, fn -> assert 1 == 2, "custom failure" end
    assert error.message == "custom failure"

    error = assert_raise ExUnit.AssertionError, fn -> assert 1 == 2 end
    assert error.left == 1
    assert error.right == 2

    error = assert_raise ExUnit.AssertionError, fn -> refute 1 == 1, "custom refutation" end
    assert error.message == "custom refutation"
  end

  test "typed expectations and session expressions are evaluated once" do
    session = %Fluffy.Session{
      backend: Fluffy.Backend.Phoenix,
      pages: %{},
      active_page: nil,
      context: nil,
      results: %{response: %{type: :response, value: %{status: 200}}}
    }

    session_fun = fn ->
      send(self(), :session_evaluated)
      session
    end

    expectation_fun = fn ->
      send(self(), :expectation_evaluated)
      response_status(:response, 200)
    end

    assert assert(session_fun.(), expectation_fun.()) == session
    assert_received :session_evaluated
    assert_received :expectation_evaluated
    refute_received :session_evaluated
    refute_received :expectation_evaluated
  end
end
