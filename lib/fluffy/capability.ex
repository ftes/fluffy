defmodule Fluffy.Capability do
  @moduledoc """
  The support contract of the Phoenix page drivers, against Playwright as the reference.

  `matrix/0` is the machine-readable source used by the published capability
  table. It retains Static and LiveView detail, while the published table
  combines them under the Phoenix backend and uses the applicable status for
  features that are inherently LiveView-only. Playwright supports every feature. A
  status describes only the named, documented public behavior; it is not a claim
  that an in-process DOM is a complete browser implementation.

  Every `Fluffy.CapabilityError` names one of these features in `capability`.
  """

  @drivers [:static, :live]
  @statuses [:equivalent, :structural_subset, :not_applicable, :browser_only]

  @matrix [
    %{
      id: :frames,
      feature: "Frame locators and traversal",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Frame traversal follows Playwright and is not supported by Static and LiveView. Querying the iframe element itself remains ordinary DOM behavior."
    },
    %{
      id: :css_locators,
      feature: "Conformance-tested CSS locators",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "The shared contract covers the selectors in the CSS conformance corpus; arbitrary browser-only pseudo-classes are not advertised."
    },
    %{
      id: :text_label_attribute_locators,
      feature: "Text, label, and attribute locators",
      drivers: %{static: :equivalent, live: :equivalent},
      detail: "Matching, normalization, exactness, composition, and strictness use the paired corpus."
    },
    %{
      id: :role_locators,
      feature: "Structural role and accessible-name subset",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset
      },
      detail:
        "Static and LiveView port Playwright's role, accessible-name and description computation to markup, for role locators, `to_have_role`, `to_have_accessible_name` and `to_have_accessible_description`. They do not interpret CSS-generated content or computed visibility."
    },
    %{
      id: :playwright_locator_options,
      feature: "Role-state locator options",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Options such as `pressed:` and `level:` compile into the Playwright selector. Static and LiveView raise when they resolve such a locator."
    },
    %{
      id: :playwright_action_options,
      feature: "Playwright action options",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Options such as `force:`, `modifiers:`, and `wait_until:` pass through to the Playwright call behind `click`, `reload`, and other actions. Static and LiveView raise when an action receives one."
    },
    %{
      id: :dom_assertions,
      feature: "DOM assertions and strictness",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "Counts, text, attributes, values, and checked state are paired. Assertions raise ExUnit.AssertionError with Phoenix structural diagnostics or native Playwright details."
    },
    %{
      id: :page_title_assertions,
      feature: "Page title assertions",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "Exact, regular-expression, whitespace-normalized, negated, and dynamic LiveView title assertions are paired."
    },
    %{
      id: :indeterminate_checked_state,
      feature: "Indeterminate checkbox/radio DOM property",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Indeterminate has no HTML representation and is normally set by application JavaScript, so in-process drivers do not infer it."
    },
    %{
      id: :focus,
      feature: "Focus, blur, and focus assertions",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Phoenix does not track focus. Use Fluffy.Playwright.focus/3 and blur/3, and focus assertions with a Playwright session."
    },
    %{
      id: :element_actions,
      feature: "Structural element actions",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset
      },
      detail:
        "Static and LiveView model structural visibility, enabledness, editability, and control state from markup. Focus, CSS layout-dependent actionability, and filling contenteditable elements require Playwright."
    },
    %{
      id: :static_navigation,
      feature: "Visits, reloads, links, redirects, cookies, and HTTP forms",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "LiveView classifies each document transition afresh, so ordinary HTTP navigation uses this same contract. WebKit 26.5 does not send a Secure cookie to the HTTP loopback fixture; that engine-specific assertion is excluded from its scheduled job."
    },
    %{
      id: :external_navigation,
      feature: "Off-origin links, forms, and redirects",
      drivers: %{static: :structural_subset, live: :structural_subset},
      detail:
        "Static and LiveView end at a page with only the off-origin URL, without requesting it, so URL expectations can check where the app sent the test. Everything else there raises, as do a `visit` to another origin and a navigation to a scheme other than HTTP, such as `mailto:`."
    },
    %{
      id: :phoenix_html_actions,
      feature: "Phoenix.HTML data-method/data-to actions",
      drivers: %{static: :structural_subset, live: :structural_subset},
      detail:
        "Static and plain LiveView elements reproduce the pinned Phoenix.HTML hidden-form algorithm. Custom phoenix.link.click listeners, cancellation, and a competing phx-click or LiveView navigation on the same element require Playwright."
    },
    %{
      id: :live_events,
      feature: "LiveView events, patches, navigation, and structural action retry",
      drivers: %{static: :not_applicable, live: :equivalent},
      detail:
        "LiveView retries expectations and typed transient structural action failures against fresh renders under one monotonic deadline."
    },
    %{
      id: :live_document,
      feature: "LiveView root layout, title updates, and portals",
      drivers: %{static: :not_applicable, live: :structural_subset},
      detail:
        "LiveView keeps the dead-rendered root layout around each render, applies live_title updates, and teleports portal content. Layout bindings reach the main LiveView. LiveViews rendered in the root layout stay unconnected and raise a named capability on actions."
    },
    %{
      id: :live_change_timing,
      feature: "LiveView form-change delivery and timing",
      drivers: %{
        static: :not_applicable,
        live: :structural_subset
      },
      detail:
        "LiveView eagerly dispatches each applicable phx-change and ignores phx-debounce/phx-throttle scheduling. Playwright owns delay, blur-only delivery, coalescing, cancellation, and throttle suppression."
    },
    %{
      id: :liveview_keyboard_events,
      feature: "Declarative LiveView keyboard events",
      drivers: %{
        static: :not_applicable,
        live: :structural_subset
      },
      detail:
        "LiveView forwards arbitrary keys unchanged through LiveViewTest keydown/keyup handlers on the selected element. No browser default actions, phx-key filtering, key translation, or synthesized field values are simulated. Static does not support press."
    },
    %{
      id: :supported_form_model,
      feature: "Supported mutable form state and ordered submission",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "The supported subset includes current values, checkedness, selectedness, successful controls, submitters, dynamic controls, and URL encoding."
    },
    %{
      id: :implicit_enter_submission,
      feature: "Enter implicit form submission",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Only Playwright performs implicit Enter submission. Use submit or click a submitter for explicit form submission with Phoenix."
    },
    %{
      id: :native_constraint_validation,
      feature: "Native constraint validation",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Static and LiveView bypass validation and submit structurally; only Playwright runs native browser validation and invalid-event behavior."
    },
    %{
      id: :specialized_input_values,
      feature: "Specialized scalar input values",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset
      },
      detail:
        "Static and LiveView retain supplied values as strings; browser sanitization, defaults, and type validation remain Playwright behavior."
    },
    %{
      id: :computed_browser_semantics,
      feature: "Computed style, layout, rendering, and browser accessibility tree",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Use Playwright when matching or actionability depends on layout, generated content, computed visibility, or a browser accessibility tree; in-process drivers do not diagnose those dependencies. Bounding boxes, ARIA snapshots, screenshots, and PDFs require Playwright too."
    },
    %{
      id: :downloads,
      feature: "Downloads",
      drivers: %{static: :equivalent, live: :equivalent},
      detail: "HTTP downloads return handles with metadata and explicit read/save operations on both backends."
    },
    %{
      id: :pages,
      feature: "Multiple pages and new tabs",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Multiple pages, new tabs, page lifecycle operations and events, bringing a page to front, and load-state waits require Playwright."
    },
    %{
      id: :browser_history,
      feature: "Browser history navigation",
      drivers: %{static: :browser_only, live: :browser_only},
      detail: "Back and forward navigation require a real browser history."
    },
    %{
      id: :cookies,
      feature: "Adding, reading, and clearing cookies",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "add_cookies/2, cookies/2 and clear_cookies/2 follow Playwright's browserContext cookie methods. Phoenix keeps the cookies in the session's jar, which every request sends from; it does not enforce SameSite and ignores partitionKey."
    },
    %{
      id: :browser_context_state,
      feature: "Browser storage: Web Storage reads and storage-state export and restoration",
      drivers: %{static: :browser_only, live: :browser_only},
      detail: "Storage reads, export, and restoration operate on the Playwright browser context and page."
    },
    %{
      id: :browser_context_setters,
      feature: "Runtime permissions, geolocation, offline mode, and HTTP credentials",
      drivers: %{static: :browser_only, live: :browser_only},
      detail: "These change a real browser context; a Phoenix session has none."
    },
    %{
      id: :browser_pointer_typing,
      feature: "Hover, drag-and-drop, typing, keyboard, mouse, viewport, and media emulation",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Native pointer, touch, and keyboard events, dispatched DOM events, text selection, scrolling, and viewport and media emulation require Playwright."
    },
    %{
      id: :browser_events,
      feature: "Dialogs, console, page errors, frames, workers, WebSockets, and browser network events",
      drivers: %{static: :browser_only, live: :browser_only},
      detail: "JavaScript and subresource network streams do not run in an in-process page driver."
    },
    %{
      id: :routing,
      feature: "Browser request routing",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Fluffy.Playwright.route/4 routes matching requests of a session's context through Playwright's route handlers. Phoenix raises Fluffy.CapabilityError."
    },
    %{
      id: :javascript_evaluation,
      feature: "Active-page JavaScript evaluation",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Only the Playwright driver can execute JavaScript in a real browser context, including init scripts and script and style tags."
    },
    %{
      id: :clock,
      feature: "Fake page clock and timers",
      drivers: %{static: :browser_only, live: :browser_only},
      detail: "Only browser pages run JavaScript timers and Date for Playwright's clock to control."
    },
    %{
      id: :scripted_default_actions,
      feature: "JavaScript-owned DOM and default actions",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Inline/listener DOM mutation, inline submit and formdata handlers, and arbitrary script-created navigation require Playwright."
    },
    %{
      id: :native_form_events,
      feature: "Native invalid, submit, and formdata event ordering",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "In-process LiveView events are server protocol operations, not a claim to execute native browser event listeners."
    },
    %{
      id: :advanced_form_entries,
      feature: "Browser-dependent form entries and submissions",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Hard-wrapped textareas, `dirname`, object and form-associated custom-element entries, image-submitter coordinates, `method=\"dialog\"`, and Static `text/plain` encoding depend on layout, plugin or element state, or script, and raise in-process."
    },
    %{
      id: :playwright_only_api,
      feature: "Page content, locator lists and waits, native locators, and download files",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "`Fluffy.Playwright.content/2`, `title/2`, `all/2`, `unwrap/3`, `wait_for/3` on a locator, and a download's file path and native Playwright value work on Playwright only. On Phoenix use expectations, `Fluffy.unwrap/2`, and `Fluffy.Download.read/2` or `save_as/2`."
    },
    %{
      id: :test_isolation,
      feature: "Per-test sessions, cleanup, and Ecto sandbox propagation",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "One test scope owns all sessions and tears pages and LiveViews down before the application's sandbox owner stops."
    },
    %{
      id: :url_matching,
      feature: "URL matching",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "page_to_have_url/2 takes what Playwright's toHaveURL takes: a string resolved against the base URL that must equal the URL, a regex, or a predicate over the URL as a %URI{}. Phoenix drivers match with Playwright.Isomorphic.UrlMatch."
    },
    %{
      id: :file_uploads,
      feature: "Typed file selection and supported upload lifecycle",
      drivers: %{static: :equivalent, live: :equivalent},
      detail:
        "set_input_files/3,4 supports bounded local paths, typed in-memory payloads, multiple selection, clearing, ordinary multipart forms, and the documented managed LiveView lifecycle. Native picker UI, external uploaders, directories, drag-and-drop, and arbitrary FileList mutation are outside this capability."
    },
    %{
      id: :file_chooser_events,
      feature: "Script-opened file chooser events",
      drivers: %{static: :browser_only, live: :browser_only},
      detail:
        "Event.file_chooser/1 captures a Playwright chooser before its triggering action; the chooser can be passed to set_input_files/4. In-process drivers do not execute the application JavaScript that opens a chooser."
    }
  ]

  @doc "Returns the ordered, machine-readable driver capability matrix."
  def matrix, do: @matrix

  @doc "Returns the status of a feature on a Phoenix page driver, `:static` or `:live`."
  def status(feature, driver) when driver in @drivers do
    case Enum.find(@matrix, &(&1.id == feature)) do
      nil -> raise ArgumentError, "unknown Fluffy capability #{inspect(feature)}"
      capability -> Map.fetch!(capability.drivers, driver)
    end
  end

  @doc false
  def statuses, do: @statuses

  @doc false
  def ids, do: Enum.map(@matrix, & &1.id)

  @doc "Renders the backend-oriented Markdown table from the machine-readable matrix."
  def markdown do
    header = [
      "| Feature | Phoenix |",
      "| --- | --- |"
    ]

    rows =
      Enum.map(@matrix, fn capability ->
        phoenix =
          capability.drivers.static
          |> phoenix_status(capability.drivers.live)
          |> display_status()

        "| #{capability.feature} | #{phoenix} |"
      end)

    Enum.join(header ++ rows, "\n")
  end

  defp phoenix_status(status, status), do: status
  defp phoenix_status(:not_applicable, live_status), do: live_status
  defp phoenix_status(static_status, :not_applicable), do: static_status

  defp display_status(status) when status in [:browser_only, :not_applicable], do: "-"

  defp display_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
