defmodule Fluffy.Internal.NavigationFailure do
  @moduledoc false

  # A navigation Fluffy found failed: an aborted or unfollowable response, a LiveView that
  # rejected or failed its connection, or a browser page whose LiveViews did not become
  # ready. `Fluffy.Internal.OperationFailure` raises it to the user as the message of a
  # `Fluffy.OperationError` of the operation that navigated.

  defexception [:message]
end
