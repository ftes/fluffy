defmodule Fluffy.Driver.Live.UploadState.Entry do
  @moduledoc false
  @enforce_keys [:name, :ref, :selected_file]
  defstruct [:name, :ref, :selected_file]

  @type t :: %__MODULE__{
          name: String.t(),
          ref: String.t(),
          selected_file: Fluffy.SelectedFile.t()
        }
end

defmodule Fluffy.Driver.Live.UploadState.Batch do
  @moduledoc false
  @enforce_keys [:entries, :upload]
  defstruct [:entries, :upload, uploaded?: false]

  @type t :: %__MODULE__{
          entries: [Fluffy.Driver.Live.UploadState.Entry.t()],
          upload: term(),
          uploaded?: boolean()
        }
end

defmodule Fluffy.Driver.Live.UploadState.Form do
  @moduledoc false
  @enforce_keys [:input_identity, :input_selector]
  defstruct [:input_identity, :input_selector, batches: []]

  @type t :: %__MODULE__{
          input_identity: term(),
          input_selector: String.t(),
          batches: [Fluffy.Driver.Live.UploadState.Batch.t()]
        }
end

defmodule Fluffy.Driver.Live.UploadState do
  @moduledoc false

  alias Fluffy.Driver.Live.UploadState.Batch
  alias Fluffy.Driver.Live.UploadState.Entry
  alias Fluffy.Driver.Live.UploadState.Form

  defstruct forms: %{}

  @opaque t :: %__MODULE__{forms: %{optional(integer()) => Form.t()}}

  def new, do: %__MODULE__{}
  def empty?(%__MODULE__{forms: forms}), do: map_size(forms) == 0
  def present?(%__MODULE__{forms: forms}, form_id), do: Map.has_key?(forms, form_id)
  def fetch(%__MODULE__{forms: forms}, form_id), do: Map.fetch(forms, form_id)
  def get(%__MODULE__{forms: forms}, form_id), do: Map.get(forms, form_id)
  def forms(%__MODULE__{forms: forms}), do: Map.values(forms)

  def put(%__MODULE__{} = state, form_id, identity, selector, upload, selected_files, options) do
    options = Keyword.validate!(options, append: false, uploaded: false)

    entries =
      upload.entries
      |> Enum.zip(selected_files)
      |> Enum.map(fn {entry, selected_file} ->
        %Entry{
          name: Map.fetch!(entry, "name"),
          ref: Map.fetch!(entry, "ref"),
          selected_file: selected_file
        }
      end)

    batch = %Batch{entries: entries, upload: upload, uploaded?: options[:uploaded]}
    previous = get(state, form_id)
    batches = if options[:append] and previous, do: previous.batches ++ [batch], else: [batch]
    form = %Form{input_identity: identity, input_selector: selector, batches: batches}
    %{state | forms: Map.put(state.forms, form_id, form)}
  end

  def mark_uploaded(%__MODULE__{} = state, form_id, upload_pid) do
    update_form(state, form_id, fn form ->
      %{form | batches: Enum.map(form.batches, &mark_batch_uploaded(&1, upload_pid))}
    end)
  end

  def delete_form(%__MODULE__{} = state, form_id) do
    {Map.get(state.forms, form_id), %{state | forms: Map.delete(state.forms, form_id)}}
  end

  def find_entry(%__MODULE__{forms: forms}, entry_ref) when is_binary(entry_ref) do
    Enum.find_value(forms, fn {form_id, form} ->
      case Enum.find(form.batches, &Enum.any?(&1.entries, fn entry -> entry.ref == entry_ref end)) do
        nil -> nil
        batch -> {form_id, form, batch}
      end
    end)
  end

  def find_entry(%__MODULE__{}, _entry_ref), do: nil

  def put_entries(%__MODULE__{} = state, form_id, upload_pid, entries) do
    entry_refs = MapSet.new(entries, & &1.ref)

    update_form(state, form_id, fn form ->
      batches =
        Enum.map(form.batches, fn batch ->
          if batch.upload.pid == upload_pid do
            upload = %{
              batch.upload
              | entries: Enum.filter(batch.upload.entries, &(&1["ref"] in entry_refs))
            }

            %{batch | entries: entries, upload: upload}
          else
            batch
          end
        end)

      %{form | batches: batches}
    end)
  end

  def remove_batch(%__MODULE__{} = state, form_id, upload_pid) do
    case get(state, form_id) do
      nil ->
        state

      form ->
        batches = Enum.reject(form.batches, &(&1.upload.pid == upload_pid))

        if batches == [] do
          elem(delete_form(state, form_id), 1)
        else
          update_form(state, form_id, &%{&1 | batches: batches})
        end
    end
  end

  def selected_files(batches) when is_list(batches) do
    batches |> Enum.flat_map(& &1.entries) |> Enum.map(& &1.selected_file)
  end

  def prune(%__MODULE__{forms: forms} = state, keep?) when is_function(keep?, 1) do
    {kept, stale} = Enum.split_with(forms, fn {_form_id, form} -> keep?.(form) end)
    {%{state | forms: Map.new(kept)}, Enum.map(stale, &elem(&1, 1))}
  end

  defp update_form(%__MODULE__{} = state, form_id, fun) do
    %{state | forms: Map.update!(state.forms, form_id, fun)}
  end

  defp mark_batch_uploaded(%Batch{upload: %{pid: upload_pid}} = batch, upload_pid), do: %{batch | uploaded?: true}

  defp mark_batch_uploaded(batch, _upload_pid), do: batch
end
