defmodule Fluffy.Driver.Contract do
  @moduledoc false

  alias Fluffy.Expect
  alias Fluffy.Internal.Navigation
  alias Fluffy.Locator
  alias Fluffy.Session

  # A driver reports a navigation by returning it, for `Fluffy.Backend` to perform, and
  # with it, for a retry on the new page, a continuation to run there with the dispatch
  # function. It never calls up.
  @type result ::
          Session.t()
          | {:navigate, Session.t(), Navigation.t()}
          | {:navigate, Session.t(), Navigation.t(), continuation()}
  @type continuation :: (Session.t(), (Session.t(), atom(), list() -> term()) -> term())

  # A read returns its value, or a navigation it found first with the read to retry there.
  @type read(value) :: {:return, value, result()} | {:navigate, Session.t(), Navigation.t(), continuation()}

  @callback validate_operation!(Session.t(), atom(), list()) :: :ok

  @callback set_html(Session.t(), String.t()) :: result()
  @callback expect(Session.t(), Expect.t()) :: result()
  @callback click(Session.t(), Locator.t(), keyword()) :: result()
  @callback submit(Session.t(), Locator.t(), keyword()) :: result()
  @callback fill(Session.t(), Locator.t(), String.t(), keyword()) :: result()
  @callback clear(Session.t(), Locator.t(), keyword()) :: result()
  @callback set_input_files(
              Session.t(),
              Locator.t() | Fluffy.FileChooser.t(),
              Fluffy.SelectedFile.source(),
              [Fluffy.SelectedFile.t()],
              keyword()
            ) :: result()
  @callback set_checked(Session.t(), Locator.t(), boolean(), keyword()) :: result()
  @callback select_option(Session.t(), Locator.t(), term(), keyword()) :: result()
  @callback press(Session.t(), Locator.t(), String.t(), keyword()) :: result()
  @callback text_content(Session.t(), Locator.t(), keyword()) :: read(String.t() | nil)
  @callback all_text_contents(Session.t(), Locator.t(), keyword()) :: read([String.t()])
  @callback get_attribute(Session.t(), Locator.t(), String.t(), keyword()) :: read(String.t() | nil)
  @callback input_value(Session.t(), Locator.t(), keyword()) :: read(String.t())
  # The number of current matches, which `Fluffy.all/2` turns into locators.
  @callback all(Session.t(), Locator.t(), keyword()) :: read(non_neg_integer())
  @callback wait_for(Session.t(), Locator.t(), keyword()) :: result()
  @callback content(Session.t(), keyword()) :: read(String.t())
  @callback title(Session.t(), keyword()) :: read(String.t())
  @callback open_browser(Session.t(), (String.t() -> term())) :: Session.t()
  @callback unwrap(Session.t(), (term() -> term())) :: result()
  @callback unwrap_and_return(Session.t(), (term() -> value)) :: {:return, value, result()} when value: term()

  @optional_callbacks set_html: 2
end
