defmodule Fluffy.OpenBrowser do
  @moduledoc false

  def write(document, resolve_asset, open_fun) do
    html =
      document
      |> LazyHTML.to_tree()
      |> rewrite(resolve_asset)
      |> LazyHTML.from_tree()
      |> LazyHTML.to_html()

    path = Path.join(System.tmp_dir!(), "fluffy-#{Phoenix.LiveView.Utils.random_id()}.html")
    File.write!(path, html)
    open_fun.(path)
  end

  def static_asset_resolver(nil), do: &Function.identity/1

  def static_asset_resolver(endpoint) do
    priv = Application.app_dir(endpoint.config(:otp_app), "priv")
    static_url = endpoint.config(:static_url) || []
    prefix = if static_url[:path], do: priv, else: Path.join(priv, "static")

    fn
      "//" <> _ = path -> path
      "/" <> _ = path -> "file://" <> Path.join(prefix, path)
      path -> path
    end
  end

  def open(path) do
    {command, args} =
      case :os.type() do
        {:win32, _} -> {"cmd", ["/c", "start", "", path]}
        {:unix, :darwin} -> {"open", [path]}
        {:unix, _} -> unix_command(path)
      end

    System.cmd(command, args)
  end

  defp unix_command(path) do
    if path =~ "\\" and System.find_executable("cmd.exe") do
      {"cmd.exe", ["/c", "start", "", path]}
    else
      {"xdg-open", [path]}
    end
  end

  defp rewrite(nodes, resolve_asset) do
    Enum.flat_map(nodes, fn
      {"script", _, _} ->
        []

      {tag, attrs, children} ->
        attrs =
          Enum.map(attrs, fn
            {key, path} when key in ["src", "href"] and tag != "a" -> {key, resolve_asset.(path)}
            attr -> attr
          end)

        [{tag, attrs, rewrite(children, resolve_asset)}]

      node ->
        [node]
    end)
  end
end
