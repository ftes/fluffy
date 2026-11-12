defmodule Fluffy.Support.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :fluffy,
    adapter: Ecto.Adapters.Postgres
end

defmodule Fluffy.Support.RepoTwo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :fluffy,
    adapter: Ecto.Adapters.Postgres
end
