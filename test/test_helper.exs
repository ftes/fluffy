alias Ecto.Adapters.SQL.Sandbox

Application.put_env(:fluffy, :playwright_boot_state, %{pool: Process.whereis(PlaywrightEx.Test.Pool)})

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
ExUnit.start(
  max_cases: max_cases,
  assert_receive_timeout: 2_000,
  # Added to, so `mix test --formatter` still applies.
  formatters:
    ExUnit.configuration()[:formatters] ++
      [Fluffy.Support.FailuresFormatter, Fluffy.Support.ModuleTimesFormatter]
)

{:ok, _test_server} = Fluffy.Support.Server.start_link()

# The repos run for every test: browser sessions carry the sandbox header of `ecto_repos`,
# and the endpoint's plug looks them up, also in tests that start no sandbox owner.
:ok = Sandbox.mode(Fluffy.Support.Repo, :manual)
:ok = Sandbox.mode(Fluffy.Support.RepoTwo, :manual)
