# Conformance corpus

Fluffy tests compatibility by running the same public API behavior as
independent ExUnit cases against the matching page drivers. No test compares
private driver traces or catches one driver's exception merely to compare it
with another.

The Playwright oracle verifies the shared contract while each case remains an
ordinary Elixir test.

The behavior-oriented corpus remains flat under `test/conformance/` so an
individual behavior and driver stay visible in ExUnit output and command-line
filtering. The filename prefixes form these release groups:

| Group | Corpus |
| --- | --- |
| Locators and assertions | `css_locator`, `text_locator`, `label_locator`, `attribute_locator`, `role_locator`, `composed_locator`, `locator_diagnostics` |
| Actions | `actionability_capability`, `click_action`, `fill_action`, `check_action`, `select_option_action`, `focus_action`, `press_action`, and `implicit_submission` |
| Navigation and transport | `static_http_visit`, `static_http_link`, `static_http_form`, `static_http_cookie`, `static_http_error`, `phoenix_session`, `static_visit`, `reload`, and `initial_conn` |
| Browser readiness | `client_navigation_readiness`, `live_event_navigation_readiness`, `live_popup_readiness`, `live_readiness_error`, and `live_redirect_readiness` |
| LiveView | `live_action`, `live_counter`, `live_form`, `live_keyboard_action`, `live_navigation`, `live_retry`, `live_session_transition`, `live_structural_action_retry`, and `live_timing` |
| Forms and files | action files above plus `form_capability`, `implicit_submission`, `static_http_form`, `live_form`, `file_input_action`, `file_input_browser_contract`, `live_file_input`, and `live_managed_upload` |
| Events and pages | `download_event`, `page_event`, `navigation_event`, `dialog_event`, `network_event`, `file_chooser_event`, and `page_cleanup` |
| Page/native helpers | `page_title`, `playwright_evaluate`, and `unwrap` |
| Harness isolation | `html_isolation` and the root-level runtime, sandbox, registry, and lifecycle tests |

DOM-only cases inject test-local HTML. Transport behavior uses the dynamic
HTTP fixture registry. LiveView behavior uses focused real LiveViews. Each
feature may be marked equivalent only when its public behavior has a pinned
Playwright case and a matched Static or LiveView case.

See [the capability matrix](capabilities.md) for intentional boundaries.
