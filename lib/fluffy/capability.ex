defmodule Fluffy.Capability do
  @moduledoc """
  The versioned support contract for Fluffy page drivers.

  `matrix/0` is the machine-readable source used by the published capability
  table. It retains Static and LiveView detail, while the published table
  combines them under the Phoenix backend and uses the applicable status for
  features that are inherently LiveView-only. A status describes only the named,
  documented public behavior; it is not a claim that an in-process DOM is a
  complete browser implementation.
  """

  @matrix_version 1
  @drivers [:static, :live, :playwright]
  @statuses [:equivalent, :structural_subset, :not_applicable, :browser_only, :experimental]

  @matrix [
    %{
      id: :css_locators,
      feature: "Documented CSS locator subset",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "The shared contract covers the selectors in the CSS conformance corpus; arbitrary browser-only pseudo-classes are not advertised."
    },
    %{
      id: :text_label_attribute_locators,
      feature: "Text, label, and attribute locators",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail: "Matching, normalization, exactness, composition, and strictness use the paired corpus."
    },
    %{
      id: :role_locators,
      feature: "Structural role and accessible-name subset",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset,
        playwright: :equivalent
      },
      detail:
        "Static and LiveView implement the documented HTML/ARIA subset from markup. They do not interpret CSS-generated content or computed visibility."
    },
    %{
      id: :dom_assertions,
      feature: "DOM assertions and strictness",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail: "Counts, text, attributes, values, checked state, focus, and canonical failure classes are paired."
    },
    %{
      id: :page_title_assertions,
      feature: "Page title assertions",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "Exact, regular-expression, whitespace-normalized, negated, and dynamic LiveView title assertions are paired."
    },
    %{
      id: :indeterminate_checked_state,
      feature: "Indeterminate checkbox/radio DOM property",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail:
        "Indeterminate has no HTML representation and is normally set by application JavaScript, so in-process drivers do not infer it."
    },
    %{
      id: :element_actions,
      feature: "Structural element actions",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset,
        playwright: :equivalent
      },
      detail:
        "Static and LiveView model structural visibility, enabledness, editability, focus, and control state from markup. They deliberately ignore CSS layout-dependent actionability. Click-to-focus follows the pinned Chromium baseline; WebKit does not focus a button on click."
    },
    %{
      id: :static_navigation,
      feature: "Visits, reloads, links, redirects, cookies, and HTTP forms",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "LiveView classifies each document transition afresh, so ordinary HTTP navigation uses this same contract. WebKit 26.5 does not send a Secure cookie to the HTTP loopback fixture; that engine-specific assertion is excluded from its scheduled job."
    },
    %{
      id: :phoenix_html_actions,
      feature: "Phoenix.HTML data-method/data-to actions",
      drivers: %{static: :structural_subset, live: :structural_subset, playwright: :equivalent},
      detail:
        "Static and plain LiveView elements reproduce the pinned Phoenix.HTML hidden-form algorithm. Custom phoenix.link.click listeners, cancellation, and competing LiveView actions require Playwright."
    },
    %{
      id: :live_events,
      feature: "LiveView events, patches, navigation, and structural action retry",
      drivers: %{static: :not_applicable, live: :equivalent, playwright: :equivalent},
      detail:
        "LiveView retries expectations and typed transient structural action failures against fresh renders under one monotonic deadline."
    },
    %{
      id: :live_change_timing,
      feature: "LiveView form-change delivery and timing",
      drivers: %{
        static: :not_applicable,
        live: :structural_subset,
        playwright: :equivalent
      },
      detail:
        "LiveView eagerly dispatches each applicable phx-change and ignores phx-debounce/phx-throttle scheduling. Playwright owns delay, blur-only delivery, coalescing, cancellation, and throttle suppression."
    },
    %{
      id: :liveview_keyboard_events,
      feature: "Declarative LiveView keyboard events",
      drivers: %{
        static: :not_applicable,
        live: :structural_subset,
        playwright: :equivalent
      },
      detail:
        "For Enter, Space, and Tab, LiveView reproduces paired direct/window phx-keydown and phx-keyup dispatch, phx-key filtering, payload values, targeting, focus movement, and structural default-action order. Client-side JS commands, LiveSocket metadata callbacks, modifiers, repeat, and browser timing require Playwright."
    },
    %{
      id: :supported_form_model,
      feature: "Supported mutable form state and ordered submission",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "The supported subset includes current values, checkedness, selectedness, successful controls, submitters, dynamic controls, and URL encoding."
    },
    %{
      id: :implicit_enter_submission,
      feature: "Structural Enter implicit form submission",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset,
        playwright: :equivalent
      },
      detail:
        "Static and LiveView reproduce the paired text-control/default-submitter subset, including disabled and external defaults. LiveView composes supported declarative key handlers through the separate keyboard-event contract. Both bypass native validation; validation events/blocking and inline key-handler timing remain browser-only."
    },
    %{
      id: :native_constraint_validation,
      feature: "Native constraint validation",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail:
        "Static and LiveView bypass validation and submit structurally; only Playwright runs native browser validation and invalid-event behavior."
    },
    %{
      id: :specialized_input_values,
      feature: "Specialized scalar input values",
      drivers: %{
        static: :structural_subset,
        live: :structural_subset,
        playwright: :equivalent
      },
      detail:
        "Static and LiveView retain supplied values as strings; browser sanitization, defaults, and type validation remain Playwright behavior."
    },
    %{
      id: :computed_browser_semantics,
      feature: "Computed style, layout, and browser accessibility tree",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail:
        "Use Playwright when matching or actionability depends on layout, generated content, computed visibility, or a browser accessibility tree; in-process drivers do not diagnose those dependencies."
    },
    %{
      id: :downloads,
      feature: "Downloads",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail: "Declarative same-context downloads are normalized to the same pipeable result contract."
    },
    %{
      id: :pages,
      feature: "Named pages and new tabs",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail: "Multiple pages, new tabs, and page lifecycle operations require Playwright."
    },
    %{
      id: :browser_events,
      feature: "Dialogs and browser request/response events",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail: "JavaScript dialogs and subresource network streams do not occur in an in-process page driver."
    },
    %{
      id: :javascript_evaluation,
      feature: "Active-page JavaScript evaluation",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail: "Only the Playwright driver can execute JavaScript in a real browser context."
    },
    %{
      id: :scripted_default_actions,
      feature: "JavaScript-owned DOM and default actions",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail: "Inline/listener DOM mutation and arbitrary script-created navigation require Playwright."
    },
    %{
      id: :native_form_events,
      feature: "Native invalid, submit, and formdata event ordering",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail:
        "In-process LiveView events are server protocol operations, not a claim to execute native browser event listeners."
    },
    %{
      id: :advanced_form_entries,
      feature: "Hard-wrapped textarea, object, and custom-element entries",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail:
        "These entries depend on layout, plugin/object state, ElementInternals, or script and raise a named capability in-process."
    },
    %{
      id: :test_isolation,
      feature: "Per-test sessions, cleanup, and Ecto sandbox propagation",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail: "One test scope owns all sessions and tears pages and LiveViews down before sandbox ownership."
    },
    %{
      id: :regex_url_matching,
      feature: "Regex URL matching",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "Regex expectations run one Elixir Regex against the complete canonical serialized URL above all three drivers."
    },
    %{
      id: :structured_url_matching,
      feature: "Structured path, query, and fragment URL matching",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "Fluffy.Expect.page_to_have_url/1 supports path-only and exact/subset decoded query matching. Distinct-name order is ignored, repeated-value order is retained, and every driver uses the same matcher."
    },
    %{
      id: :file_uploads,
      feature: "Typed file selection and supported upload lifecycle",
      drivers: %{static: :equivalent, live: :equivalent, playwright: :equivalent},
      detail:
        "set_input_files/3,4 supports bounded local paths, typed in-memory payloads, multiple selection, clearing, ordinary multipart forms, and the documented managed LiveView lifecycle. Native picker UI, external uploaders, directories, drag-and-drop, and arbitrary FileList mutation are outside this capability."
    },
    %{
      id: :file_chooser_events,
      feature: "Script-opened file chooser events",
      drivers: %{static: :browser_only, live: :browser_only, playwright: :equivalent},
      detail:
        "Event.file_chooser/2 captures a Playwright chooser before its triggering action; the result key can be passed to set_input_files/4. In-process drivers do not execute the application JavaScript that opens a chooser."
    }
  ]

  @doc "Returns the capability matrix schema version."
  def matrix_version, do: @matrix_version

  @doc "Returns the ordered, machine-readable driver capability matrix."
  def matrix, do: @matrix

  @doc "Returns the status for a feature and page driver."
  def status(feature, driver) when driver in @drivers do
    case Enum.find(@matrix, &(&1.id == feature)) do
      nil -> raise ArgumentError, "unknown Fluffy capability #{inspect(feature)}"
      capability -> Map.fetch!(capability.drivers, driver)
    end
  end

  @doc false
  def statuses, do: @statuses

  @doc false
  def drivers, do: @drivers

  @doc "Renders the backend-oriented Markdown table from the machine-readable matrix."
  def markdown do
    header = [
      "| Feature | Phoenix | Playwright |",
      "| --- | --- | --- |"
    ]

    rows =
      Enum.map(@matrix, fn capability ->
        phoenix =
          capability.drivers.static
          |> phoenix_status(capability.drivers.live)
          |> display_status()

        playwright = display_status(capability.drivers.playwright)

        "| #{capability.feature} | #{phoenix} | #{playwright} |"
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
