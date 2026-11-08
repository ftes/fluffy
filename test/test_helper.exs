Application.put_env(:fluffy, :playwright_boot_state, %{
  runtime: Fluffy.BrowserRuntime.status(),
  transport: Process.whereis(Fluffy.PlaywrightDriver)
})

# As many modules at once as Playwright runs workers (half the logical cores), not ExUnit's
# twice the cores: every session shares one browser, and Firefox dispatches input for all its
# pages in one queue. `FLUFFY_MAX_CASES` or `--max-cases` overrides it.
max_cases =
  case System.get_env("FLUFFY_MAX_CASES", "") do
    "" -> max(div(System.schedulers_online(), 2), 1)
    value -> String.to_integer(value)
  end

ExUnit.start(max_cases: max_cases)

{:ok, _test_server} = Fluffy.TestServer.start_link()
