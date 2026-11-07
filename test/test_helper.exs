Application.put_env(:fluffy, :playwright_boot_state, %{
  runtime: Fluffy.BrowserRuntime.status(),
  transport: Process.whereis(Fluffy.PlaywrightDriver)
})

ExUnit.start()

{:ok, _test_server} = Fluffy.TestServer.start_link()
