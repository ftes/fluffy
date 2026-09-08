defmodule Fluffy.FilePayload do
  @moduledoc """
  An in-memory file selected with `Fluffy.set_input_files/4`.

  `bytes` contains the raw file bytes. `content_type` may be omitted; Fluffy
  then infers it from `name`, falling back to `application/octet-stream` in
  the same way as Playwright.

  Use this value for generated fixtures and for tests that run against a
  remote Playwright browser without sharing a filesystem.
  """

  @enforce_keys [:name, :bytes]
  defstruct [:name, :bytes, :content_type]

  @type t :: %__MODULE__{
          name: String.t(),
          bytes: binary(),
          content_type: String.t() | nil
        }
end
