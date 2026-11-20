defmodule Fluffy.Internal.Navigation.Link do
  @moduledoc false
  @enforce_keys [:destination]
  defstruct [:destination, :download]

  @type t :: %__MODULE__{
          destination: String.t(),
          download: String.t() | nil
        }
end

defmodule Fluffy.Internal.Navigation.Submission do
  @moduledoc false
  # `redirects` counts the redirects that led to this submission, which the
  # redirects following it count on from. `triggered` marks a form a LiveView
  # rendered with phx-trigger-action, which LiveView's client submits only after
  # disconnecting for good.
  @enforce_keys [:submission]
  defstruct [:submission, redirects: 0, triggered: false]
  @type t :: %__MODULE__{submission: map(), redirects: non_neg_integer(), triggered: boolean()}
end

defmodule Fluffy.Internal.Navigation.Redirect do
  @moduledoc false
  # `redirects` counts the redirects that led to this one, which the redirects
  # following it count on from.
  @enforce_keys [:destination]
  defstruct [:destination, :flash, redirects: 0]

  @type t :: %__MODULE__{
          destination: String.t(),
          flash: map() | String.t() | nil,
          redirects: non_neg_integer()
        }
end

defmodule Fluffy.Internal.Navigation.StaticConn do
  @moduledoc false
  @enforce_keys [:conn]
  defstruct [:conn]
  @type t :: %__MODULE__{conn: Plug.Conn.t()}
end

defmodule Fluffy.Internal.Navigation do
  @moduledoc false

  alias Fluffy.Internal.Navigation.Link
  alias Fluffy.Internal.Navigation.Redirect
  alias Fluffy.Internal.Navigation.StaticConn
  alias Fluffy.Internal.Navigation.Submission

  @type t ::
          Link.t()
          | Submission.t()
          | Redirect.t()
          | StaticConn.t()

  def link(destination, options \\ []) do
    options = Keyword.validate!(options, [:download])
    %Link{destination: destination, download: options[:download]}
  end

  def submission(submission, options \\ []) do
    options = Keyword.validate!(options, redirects: 0, triggered: false)
    %Submission{submission: submission, redirects: options[:redirects], triggered: options[:triggered]}
  end

  def redirect(destination, options \\ []) do
    options = Keyword.validate!(options, [:flash])
    %Redirect{destination: destination, flash: options[:flash]}
  end

  def static_conn(%Plug.Conn{} = conn), do: %StaticConn{conn: conn}

  @max_redirects 20

  @doc """
  Counts one more Phoenix redirect at `url` after `redirects`, raising at the limit. HTTP
  redirects, LiveView redirects and an action's retries on a new page all count, so a
  loop through any of them fails at the same limit.
  """
  def count_redirect!(redirects, %URI{} = url) when redirects >= @max_redirects do
    raise Fluffy.Internal.NavigationFailure,
          "Phoenix request exceeded #{@max_redirects} redirects at #{URI.to_string(url)}"
  end

  def count_redirect!(redirects, %URI{}), do: redirects + 1
end
