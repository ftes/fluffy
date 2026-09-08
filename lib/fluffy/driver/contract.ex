defmodule Fluffy.Driver.Contract do
  @moduledoc false

  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Navigation
  alias Fluffy.Session

  @type result ::
          Session.t()
          | {:navigate, Session.t(), Navigation.t()}
          | {:navigate, Session.t(), Navigation.t(), {:retry, non_neg_integer()}}

  @callback set_html(Session.t(), String.t()) :: result()
  @callback expect(Session.t(), Expect.t()) :: result()
  @callback click(Session.t(), Locator.t(), keyword()) :: result()
  @callback submit(Session.t(), Locator.t(), keyword()) :: result()
  @callback fill(Session.t(), Locator.t(), String.t(), keyword()) :: result()
  @callback set_input_files(
              Session.t(),
              Locator.t() | atom(),
              Fluffy.SelectedFile.source(),
              [Fluffy.SelectedFile.t()],
              keyword()
            ) :: result()
  @callback set_checked(Session.t(), Locator.t(), boolean(), keyword()) :: result()
  @callback select_option(Session.t(), Locator.t(), term(), keyword()) :: result()
  @callback focus(Session.t(), Locator.t(), keyword()) :: result()
  @callback blur(Session.t(), Locator.t(), keyword()) :: result()
  @callback press(Session.t(), Locator.t(), String.t(), keyword()) :: result()
  @callback unwrap(Session.t(), (term() -> term())) :: result()

  @optional_callbacks set_html: 2
end
