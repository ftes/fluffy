defmodule Fluffy.Driver.Phoenix.Actionability do
  @moduledoc false

  import Fluffy.Driver.Phoenix.HTML.Semantics, only: [has_attribute?: 2, input_type: 1, value_mode?: 1]

  alias Fluffy.Driver.Phoenix.HTML.Target

  # The click's enabled check follows the label, see `Fluffy.Driver.Phoenix.ClientDOM.click/3`.
  def ensure_clickable!(%Target{} = target, action, locator) do
    if has_attribute?(target.attributes, "hidden") do
      raise_error(action, :hidden, locator)
    end

    :ok
  end

  # Fill's own check, after the editable state: an input it can type into, a
  # textarea, or contenteditable.
  def ensure_fillable!(%Target{} = target, content_editable?, action, locator) do
    if not value_mode?(target) and not content_editable? do
      raise_error(action, :not_editable, locator)
    end

    :ok
  end

  def ensure_checkable!(%Target{} = target, action, locator) do
    if input_type(target) not in ["checkbox", "radio"] do
      raise_error(action, :not_checkable, locator)
    end

    :ok
  end

  def ensure_selectable!(%Target{} = target, action, locator) do
    if target.tag != "select" do
      raise_error(action, :not_selectable, locator)
    end

    :ok
  end

  def ensure_file_input_files!(%Target{} = target, files, action, locator) when is_list(files) do
    # Playwright's setInputFiles validates the element type and multiplicity,
    # but intentionally does not require the file input to be enabled or
    # visible. Keep the portable action aligned with that contract.
    if input_type(target) != "file" do
      raise_error(action, :not_file_input, locator)
    end

    if match?([_, _ | _], files) and not has_attribute?(target.attributes, "multiple") do
      raise_error(action, :multiple_files_not_allowed, locator)
    end
  end

  defp raise_error(action, reason, locator) do
    raise Fluffy.ActionabilityError,
      action: action,
      reason: reason,
      locator: locator
  end
end
