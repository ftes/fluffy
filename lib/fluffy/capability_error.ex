defmodule Fluffy.CapabilityError do
  @moduledoc """
  Raised when a backend or page driver cannot support a requested operation.

  `capability` is the feature's id in `Fluffy.Capability.matrix/0`, and `operation` the
  call that needs it, or `nil` when the feature is in the page rather than the call.
  `backend` is `:phoenix` or `:playwright`, and `driver` the active page driver, or `nil`
  when no page is involved, such as for a session option.
  """

  alias Fluffy.Session

  defexception [:capability, :operation, :backend, :driver, :detail, :message]

  @impl true
  def exception(options) do
    capability = Keyword.fetch!(options, :capability)
    operation = Keyword.get(options, :operation)
    driver = Keyword.get(options, :driver)
    backend = Keyword.get_lazy(options, :backend, fn -> backend!(driver) end)
    detail = Keyword.fetch!(options, :detail)

    %__MODULE__{
      capability: capability,
      operation: operation,
      backend: backend,
      driver: driver,
      detail: detail,
      message: "#{subject(backend, driver)} does not support #{feature(capability, operation)}: #{detail}"
    }
  end

  @doc false
  # The one check for an operation only a Playwright session has, on a session or, for a
  # session option, a backend name.
  @spec require_playwright!(Session.t() | :phoenix | :playwright, atom(), atom(), String.t()) :: :ok
  def require_playwright!(session_or_backend, capability, operation, detail \\ "it requires a Playwright session")

  def require_playwright!(:playwright, _capability, _operation, _detail), do: :ok

  def require_playwright!(:phoenix, capability, operation, detail),
    do: raise(__MODULE__, capability: capability, operation: operation, backend: :phoenix, detail: detail)

  def require_playwright!(%Session{} = session, capability, operation, detail) do
    if Session.backend(session) != Fluffy.Backend.Playwright do
      raise __MODULE__,
        capability: capability,
        operation: operation,
        driver: Session.current_driver(session),
        detail: detail
    end

    :ok
  end

  defp backend!(driver) when driver in [:unvisited, :static, :live, :external], do: :phoenix
  defp backend!(:playwright), do: :playwright

  defp subject(:phoenix, nil), do: "Phoenix"
  defp subject(:playwright, nil), do: "Playwright"
  defp subject(:phoenix, driver), do: "Phoenix (#{inspect(driver)})"
  defp subject(:playwright, :playwright), do: "Playwright"

  defp feature(capability, nil), do: inspect(capability)
  defp feature(capability, operation), do: "#{inspect(operation)} (#{inspect(capability)})"
end
