Application.put_env(:fluffy, :playwright_boot_state, %{
  runtime: Fluffy.BrowserRuntime.status(),
  transport: Process.whereis(Fluffy.PlaywrightDriver)
})

# As many modules at once as Playwright runs workers (half the logical cores), not ExUnit's
# twice the cores: sessions share one browser (two on Firefox), and Firefox dispatches input
# for all of a browser's pages in one queue. `FLUFFY_MAX_CASES` or `--max-cases` overrides it.
max_cases =
  case System.get_env("FLUFFY_MAX_CASES", "") do
    "" -> max(div(System.schedulers_online(), 2), 1)
    value -> String.to_integer(value)
  end

# A passing assert_receive returns as soon as its message arrives, so a slow CI machine is
# the only thing this longer limit is for.
ExUnit.start(max_cases: max_cases, assert_receive_timeout: 2_000)

{:ok, _test_server} = Fluffy.TestServer.start_link()
