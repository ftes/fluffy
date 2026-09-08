defmodule Fluffy.SelectedFile do
  @moduledoc false

  alias Fluffy.FilePayload

  @enforce_keys [:bytes, :content_type, :name, :size]
  defstruct [:bytes, :content_type, :name, :size]

  @type t :: %__MODULE__{
          bytes: binary(),
          content_type: String.t(),
          name: String.t(),
          size: non_neg_integer()
        }

  @type source :: {:local_paths, [String.t()]} | {:payloads, [FilePayload.t()]}

  @spec prepare!(String.t() | FilePayload.t() | [String.t()] | [FilePayload.t()], keyword()) ::
          {source(), [t()]}
  def prepare!(selection, options \\ []) do
    max_bytes = Keyword.fetch!(Keyword.validate!(options, [:max_bytes]), :max_bytes)
    validate_max_bytes!(max_bytes)

    case selection do
      path when is_binary(path) ->
        prepare_paths!([path], max_bytes)

      %FilePayload{} = payload ->
        prepare_payloads!([payload], max_bytes)

      [] ->
        {{:payloads, []}, []}

      selections when is_list(selections) ->
        cond do
          Enum.all?(selections, &is_binary/1) ->
            prepare_paths!(selections, max_bytes)

          Enum.all?(selections, &match?(%FilePayload{}, &1)) ->
            prepare_payloads!(selections, max_bytes)

          true ->
            raise ArgumentError,
                  "set_input_files expects a homogeneous list of local path strings or Fluffy.FilePayload structs"
        end

      _other ->
        raise ArgumentError,
              "set_input_files expects one local path string, one Fluffy.FilePayload, a homogeneous list of either, or []"
    end
  end

  defp prepare_paths!(paths, max_bytes) do
    entries = Enum.map(paths, &stat_path!/1)
    ensure_size_limit!(Enum.sum(Enum.map(entries, &elem(&1, 2))), max_bytes)

    {selected, _bytes_read} =
      Enum.map_reduce(entries, 0, fn {path, expanded_path, _stat_size}, bytes_read ->
        bytes = read_path_bounded!(path, expanded_path, max_bytes - bytes_read, max_bytes)

        {{expanded_path,
          %__MODULE__{
            bytes: bytes,
            content_type: MIME.from_path(expanded_path),
            name: Path.basename(expanded_path),
            size: byte_size(bytes)
          }}, bytes_read + byte_size(bytes)}
      end)

    {expanded_paths, selected_files} = Enum.unzip(selected)
    {{:local_paths, expanded_paths}, selected_files}
  end

  defp prepare_payloads!(payloads, max_bytes) do
    selected_files = Enum.map(payloads, &selected_file_from_payload!/1)
    ensure_size_limit!(Enum.sum(Enum.map(selected_files, & &1.size)), max_bytes)
    {{:payloads, payloads}, selected_files}
  end

  defp selected_file_from_payload!(%FilePayload{name: name, bytes: bytes, content_type: content_type})
       when is_binary(name) and is_binary(bytes) and (is_binary(content_type) or is_nil(content_type)) do
    %__MODULE__{
      bytes: bytes,
      content_type: normalize_content_type(content_type || MIME.from_path(name)),
      name: name,
      size: byte_size(bytes)
    }
  end

  defp selected_file_from_payload!(%FilePayload{}) do
    raise ArgumentError,
          "set_input_files expects a Fluffy.FilePayload with binary :name and :bytes and optional binary :content_type"
  end

  defp stat_path!(path) do
    expanded_path = Path.expand(path)

    case File.stat(expanded_path) do
      {:ok, %{type: :regular, size: size}} ->
        {path, expanded_path, size}

      {:ok, %{type: type}} ->
        raise ArgumentError,
              "set_input_files expects a readable regular file, got #{inspect(type)} at #{inspect(path)}"

      {:error, reason} ->
        raise ArgumentError,
              "set_input_files could not stat #{inspect(path)}: #{:file.format_error(reason)}"
    end
  end

  defp read_path_bounded!(path, expanded_path, remaining, max_bytes) do
    case File.open(expanded_path, [:read, :binary]) do
      {:ok, device} ->
        try do
          case IO.binread(device, remaining + 1) do
            bytes when is_binary(bytes) and byte_size(bytes) <= remaining ->
              bytes

            bytes when is_binary(bytes) ->
              raise ArgumentError,
                    "set_input_files selection exceeds :max_bytes limit of #{max_bytes}"

            :eof ->
              ""

            {:error, reason} ->
              raise ArgumentError,
                    "set_input_files could not read #{inspect(path)}: #{:file.format_error(reason)}"
          end
        after
          File.close(device)
        end

      {:error, reason} ->
        raise ArgumentError,
              "set_input_files could not read #{inspect(path)}: #{:file.format_error(reason)}"
    end
  end

  defp validate_max_bytes!(max_bytes) when is_integer(max_bytes) and max_bytes >= 0, do: :ok

  defp validate_max_bytes!(max_bytes) do
    raise ArgumentError, ":max_bytes must be a non-negative integer, got: #{inspect(max_bytes)}"
  end

  defp ensure_size_limit!(size, max_bytes) when size <= max_bytes, do: :ok

  defp ensure_size_limit!(size, max_bytes) do
    raise ArgumentError,
          "set_input_files selection is #{size} bytes, exceeding :max_bytes limit of #{max_bytes}"
  end

  # File's Blob MIME type algorithm lowercases printable ASCII and replaces an
  # invalid type with the empty string. Multipart serialization then uses
  # application/octet-stream for that empty type.
  defp normalize_content_type(content_type) do
    if content_type != "" and
         Enum.all?(:binary.bin_to_list(content_type), &(&1 in 0x20..0x7E)) do
      String.downcase(content_type)
    else
      "application/octet-stream"
    end
  end
end
