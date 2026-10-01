defmodule Fluffy.SandboxConfigurationTest do
  use Fluffy.TestCase, async: false

  alias Fluffy.Sandbox

  test "provides safe defaults" do
    assert Sandbox.validate_config!([]) ==
             [header: "x-fluffy-sandbox", sandbox: Ecto.Adapters.SQL.Sandbox, trap_exit: true]
  end

  test "accepts a custom header and module or MFA allowance adapter" do
    assert Sandbox.validate_config!(header: "user-agent", sandbox: MyApp.TestSandbox) ==
             [header: "user-agent", sandbox: MyApp.TestSandbox, trap_exit: true]

    mfa = {MyApp.TestSandbox, :allow, [extra: true]}
    assert Sandbox.validate_config!(header: "x-my-sandbox", sandbox: mfa)[:sandbox] == mfa
  end

  test "can disable exit trapping in the emitted sandbox metadata" do
    original = Application.get_env(:fluffy, Sandbox)
    on_exit(fn -> Application.put_env(:fluffy, Sandbox, original) end)
    Application.put_env(:fluffy, Sandbox, trap_exit: false)

    assert {[], {"x-fluffy-sandbox", metadata}} = Sandbox.acquire(%{async: true}, [])
    assert %{trap_exit: false, owner: owner} = Phoenix.Ecto.SQL.Sandbox.decode_metadata(metadata)
    assert owner == self()
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(trap_exit: :invalid) end
  end

  test "rejects unknown, malformed, and inconsistent configuration" do
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(unknown: true) end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(header: "X-Sandbox") end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(header: "not a header") end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(sandbox: {:invalid, :mfa}) end
    assert_raise ArgumentError, fn -> Sandbox.validate_config!(%{}) end
  end
end
