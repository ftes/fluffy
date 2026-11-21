defmodule Fluffy.AssertTest do
  use ExUnit.Case, async: true
  use Playwright.Test
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

  # ExUnit's `refute match?(...)` calls an unqualified `refute(value, expr: ...)`, which resolves
  # to `use Fluffy.Assert`'s `refute/2`: it passes and fails as ExUnit's.
  test "refute match? passes and fails as ExUnit's" do
    owl = Process.get(:owl, {:ok, :hedwig})

    refute match?({:error, _}, owl)
    assert match?({:ok, _}, owl)

    error = assert_raise ExUnit.AssertionError, fn -> refute match?({:ok, _}, owl) end
    assert error.message == "match (match?) succeeded, but should have failed"
    assert Macro.to_string(error.expr) == "refute match?({:ok, _}, owl)"
  end

  test "typed expectations and session expressions are evaluated once" do
    session = Fluffy.session_for_html(:static, "<p>Response</p>")

    session_fun = fn ->
      send(self(), :session_evaluated)
      session
    end

    expectation_fun = fn ->
      send(self(), :expectation_evaluated)
      visible(Fluffy.Locator.by_text("Response"))
    end

    assert assert(session_fun.(), expectation_fun.()) == session
    assert_received :session_evaluated
    assert_received :expectation_evaluated
    refute_received :session_evaluated
    refute_received :expectation_evaluated
  end
end

defmodule Fluffy.AssertTest.QualifiedHelper do
  # A helper next to `ExUnit.Assertions` calls `Fluffy.Assert` qualified, with no `require`.
  @moduledoc false
  import ExUnit.Assertions

  def owl_arrives(session), do: Fluffy.Assert.assert(session, Fluffy.Assert.visible(Fluffy.Locator.by_text("Hedwig")))
  def no_howler(session), do: Fluffy.Assert.refute(session, Fluffy.Assert.visible(Fluffy.Locator.by_text("Howler")))
  def letter(value), do: Fluffy.Assert.assert(value, "a letter arrives")
  def plain(value), do: assert(value)
end

defmodule Fluffy.AssertTest.QualifiedTest do
  use ExUnit.Case, async: true
  use Playwright.Test

  alias Fluffy.AssertTest.QualifiedHelper

  test "Fluffy.Assert's assert/2 and refute/2 can be called qualified, without require" do
    session = Fluffy.session_for_html(:static, "<p>Hedwig</p>")

    assert %Fluffy.Session{} = session |> QualifiedHelper.owl_arrives() |> QualifiedHelper.no_howler()
    assert QualifiedHelper.letter(:owl) == true
    assert QualifiedHelper.plain(:owl) == :owl

    error = assert_raise ExUnit.AssertionError, fn -> QualifiedHelper.letter(nil) end
    assert error.message == "a letter arrives"
  end
end
