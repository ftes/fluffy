defmodule Fluffy.Playwright.Screenshot do
  @moduledoc false

  alias PlaywrightEx.Page

  def write(page_id, path, options) do
    File.mkdir_p!(Path.dirname(path))

    with {:ok, encoded} <- Page.screenshot(page_id, options),
         {:ok, bytes} <- Base.decode64(encoded),
         :ok <- File.write(path, bytes) do
      :ok
    else
      :error -> {:error, :invalid_screenshot_data}
      {:error, _reason} = error -> error
    end
  end
end
