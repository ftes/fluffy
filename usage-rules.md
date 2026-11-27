# Fluffy usage rules

Use these alongside Playwright's rules ([installation](https://hexdocs.pm/fluffy/installation.html#usage-rules-for-coding-agents)). For the guides matching your installed version, read `deps/fluffy/docs/`.

## Starting a test

- [Test setup](https://hexdocs.pm/fluffy/usage.html#your-first-test): use the app's `ConnCase`, then `use Playwright.Test`, then `use Fluffy.Assert`, in that order. Both backends need `Playwright.Test`; neither gets a session, imports or a `Test` alias from it. Start the session explicitly. Write `@tag Playwright.Test.use(...)` in full.
- [Shared case templates](https://hexdocs.pm/fluffy/usage.html#shared-test-case): forward `opts` to `use Playwright.Test` in `using`. If the template's own `setup` starts sessions, it also needs a bare `use Playwright.Test` in its body. Fluffy doesn't read a `backend` tag; your setup does.
- [Sandbox](https://hexdocs.pm/fluffy/installation.html#ecto-sandbox): the app's case must start the sandbox owner before the session. A plain checkout won't work in browser tests. A custom LiveView hook must allow through `Fluffy.Sandbox` for a Fluffy-started session to wait for its LiveViews at teardown.

## Writing tests

- [Locators](https://hexdocs.pm/fluffy/locators.html): use `by_*`, not `get_by_*`. Import `Fluffy.Locator.Roles` for `button`, `link` and `heading`; pass a parent or frame first to scope them. Locate visible copy itself, not `body` filtered by its text. Prefer an existing ID to adding a test ID when a user-facing locator won't work.
- [Assertions](https://hexdocs.pm/fluffy/assertions.html): use `assert_has` / `refute_has` for visibility and `assert` / `refute` for other conditions. A read is a snapshot. For eventual app state or a block of actions, use `assert(poll(...))` or `assert(pass(...))`. Compare JavaScript values explicitly: `:null`, `:nan`, `0` and `""` are all truthy in Elixir.
- [Waiting](https://hexdocs.pm/fluffy/actions.html#actionability-checks-and-waiting): skip sleeps, `render_async`, manual redirects and `.phx-connected` checks. Assert the resulting page. Static checks once. Use `set_input_files` even for a `live_file_input`.
- [Timeouts](https://hexdocs.pm/fluffy/installation.html#timeouts): don't change the native page's defaults. Phoenix uses `phoenix_backend_timeout`. Native calls reject `0`. Use `:once` only for an immediate check or inside a retried block; Playwright actions reject it. Facade assertions use `0` instead.
- [Driver capabilities](https://hexdocs.pm/fluffy/capabilities.html): choose Playwright for CSS visibility, JavaScript, focus and browser events. Phoenix ignores `data-confirm` and LiveView debounce/throttle. For HTTP status, inspect a browser response event.
- [Hidden elements](https://hexdocs.pm/fluffy/assertions.html#visibility-and-dom-presence): check hidden inputs with a CSS locator and `value` or `count`. For a styled checkbox or radio, act on the visible label element; `by_label` targets the input. [Closed dropdown options](https://hexdocs.pm/fluffy/actions.html#selects-and-options) are invisible even in a browser: distinguish available options from the current selection.

## Native calls and existing suites

- [Native access](https://hexdocs.pm/fluffy/debugging.html#native-escape-hatch): prefer Fluffy's reads and actions to `evaluate` or `unwrap`. Don't consume LiveView navigation notifications, close or replace the native page, remove listeners, stop tracing, or pass `no_wait_after:` or `signal:`. Don't alias `Fluffy.Playwright` as `Playwright` where you use the dependency's modules.
- [Events and routing](https://hexdocs.pm/fluffy/advanced-events.html): register before acting, or use `assert_event`. Downloads work on all drivers. Answer each routed request once; delegate database work to a `Task` so the handler doesn't block.
- [PhoenixTest migration](https://hexdocs.pm/fluffy/migration-from-phoenix-test.html): use native Fluffy for new tests and PhoenixTest.Playwright ports. Use `Fluffy.PhoenixTest` only for a minimal-diff port; never import it alongside `Fluffy`. Check the guide for facade-specific visibility, counts and timeout semantics.
