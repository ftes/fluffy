defmodule Fluffy.SandboxConfigurationTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.Sandbox

  test "provides safe defaults" do
    assert Sandbox.validate_config!([]) ==
             [header: "x-fluffy-sandbox", sandbox: Ecto.Adapters.SQL.Sandbox]
  end

  test "accepts a custom header and module or MFA allowance adapter" do
    assert Sandbox.validate_config!(header: "user-agent", sandbox: MyApp.TestSandbox) ==
             [header: "user-agent", sandbox: MyApp.TestSandbox]

    mfa = {MyApp.TestSandbox, :allow, [extra: true]}
    assert Sandbox.validate_config!(header: "x-my-sandbox", sandbox: mfa)[:sandbox] == mfa
  end

  test "rejects unknown, malformed, and inconsistent configuration" do
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(unknown: true) end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(header: "X-Sandbox") end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(header: "not a header") end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(sandbox: {:invalid, :mfa}) end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(%{}) end
  end
end
