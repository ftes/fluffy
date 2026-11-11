# Fluffy repository instructions

Phoenix feature tests: one Playwright-shaped API over three drivers (Static, LiveView,
Playwright).

Treat observable public behavior as the contract. Keep driver-specific
boundaries explicit and cover behavior changes with focused conformance tests.

Upstream Playwright is the reference. Fluffy is modeled on Playwright and adds only what Phoenix
LiveView needs (waiting for LiveViews to connect, following their navigations, form state). Before
adding a timeout budget, retry, extra check or browser workaround, check what Playwright does and
match it; the pinned source is in PlaywrightEx's download cache (`<cache_dir>/<version>/upstream`,
see `PlaywrightEx.Driver.cache_dir/1`). Don't work around Playwright, PlaywrightEx or browser bugs
(upstream `fixme` tests mark the known ones); let Playwright's behavior show through. Only as a
last resort, when LiveView support can't work without it, add a workaround, and say why in a
comment. Build Playwright selectors through PlaywrightEx (its `Frame`/`Locator`/`FrameLocator`
API, `Isomorphic.LocatorUtils` and `SelectorParser`); don't write selector strings in Fluffy,
since `internal:*` engine syntax changes between Playwright versions.
Timeouts follow Elixir: `0` means check once and `:infinity` means no limit;
`Fluffy.Deadline.playwright/1` maps `0` to 1ms, since Playwright's 0 means no limit.

Phoenix upstream is the secondary reference, for the Phoenix drivers. Playwright decides what
behavior is correct; LiveView's client JS and `Phoenix.LiveViewTest` decide how the Phoenix drivers
get there. Build on LiveViewTest rather than reimplementing it. Work around its limitations when a
test would see the browser behave differently, matching the browser and mirroring LiveView's JS.
A difference may stay when it's an edge case most users won't hit, or when closing it is very
complicated; document the differences you leave. Ask the maintainer before building a complex
workaround.

Run `mix check` before handing off code changes; use `mix quality` for
release-sensitive changes.

- `mix setup` installs deps, builds test assets and installs Chromium. Tests need PostgreSQL
  (`FLUFFY_DB_*` overrides the defaults in `config/test.exs`); `FLUFFY_BROWSER` picks
  firefox or webkit.
- Tests in `test/conformance/` run the same behavior against several drivers. The matrix in
  `docs/capabilities.md` is rendered from `Fluffy.Capability`, and a test keeps them in sync.
- Docs, doc examples and test fixtures follow the Fluffy / Harry Potter theme; keep new examples on theme.
- The block marked `usage_rules` below is generated: after updating deps run
  `mix usage_rules.sync --yes`; `mix check` fails when it's stale. On Renovate's PRs a workflow
  commits it.
- After upgrading PlaywrightEx or adding an action or locator option, run
  `mix fluffy.gen.native_options`; `mix check` fails if its output is stale.
- The compatibility floor is Elixir 1.18 on OTP 27 (`.tool-versions.oldest`).

The Phoenix rules below are written for applications, so in this library they mainly apply to the
fixtures under `test/`.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- playwright_ex-start -->
## playwright_ex usage
_Elixir client for Playwright: a port of the official JavaScript client._

[playwright_ex usage rules](deps/playwright_ex/usage-rules.md)
<!-- playwright_ex-end -->
<!-- usage-rules-end -->
