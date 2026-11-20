defmodule Fluffy.Driver.Live.Upload do
  @moduledoc false

  # LiveView-managed file uploads of the Live driver: selecting files starts an upload
  # client per batch, and a submit or auto-upload sends their entries through the view.
  # The page's state keeps them (`Fluffy.Driver.Live.UploadState`) until a submit, a
  # render that drops them or the page's release.

  import Fluffy.Driver.Phoenix.HTML.Semantics, only: [attribute: 2]
  import Phoenix.LiveViewTest, except: [open_browser: 1, open_browser: 2]

  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.Driver.Live.Processes
  alias Fluffy.Driver.Live.UploadCompat
  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.Driver.Live.View
  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Driver.Phoenix.Form
  alias Fluffy.Driver.Phoenix.HTML.DocumentIndex
  alias Fluffy.Locator
  alias Fluffy.Session

  def set_live_upload(session, locator, selected_files) do
    state = Session.page_state(session)

    if !ClientDOM.live_change_form?(state.client_dom, locator) do
      raise Fluffy.CapabilityError,
        capability: :file_uploads,
        driver: :live,
        detail: "LiveView-managed file uploads require a phx-change form"
    end

    target = ClientDOM.control!(state.client_dom, locator)

    with {:ok, event_context} <- View.owning_view_context(session, target) do
      if is_nil(event_context.root_id) do
        raise Fluffy.CapabilityError,
          capability: :file_uploads,
          driver: :live,
          detail: "LiveView-managed file uploads outside the LiveView container, such as in a portal, require Playwright"
      end

      index = ClientDOM.index(state.client_dom)
      form_id = Form.owner_id(index, target)
      ensure_upload_form_id!(DocumentIndex.target_by_id(index, form_id))

      form_selector =
        View.selector_for_view(state.client_dom, ClientDOM.selector_for_node_id(state.client_dom, form_id), event_context)

      input_selector = View.selector_for_view(state.client_dom, target.selector, event_context)
      upload_name = existing_upload_name!(target)
      # Validate the selection before starting an upload client it would leak.
      client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)

      # Starting the upload client reads the view's upload config.
      with {:ok, upload} <-
             View.read_view(session, fn ->
               file_input!(session, event_context.view, form_selector, upload_name, selected_files)
             end) do
        upload = UploadCompat.at_input(upload, input_selector)
        form_key = View.node_identity(state.client_dom, %{id: form_id})
        start_live_upload(session, client_dom, selected_files, target, event_context, form_key, form_selector, upload)
      end
    end
  end

  # A form without an id has only a position, which a patch can shift or hand
  # to another form. LiveView's own form recovery needs an id too.
  defp ensure_upload_form_id!(form) do
    if is_nil(attribute(form.attributes, "id")) do
      raise ArgumentError,
            "set_input_files/3 on a LiveView upload requires its form to have an id; give the form an id"
    end
  end

  defp file_input!(session, view, form_selector, upload_name, selected_files) do
    entries =
      Enum.map(selected_files, fn selected_file ->
        %{
          content: selected_file.bytes,
          last_modified: nil,
          name: selected_file.name,
          size: selected_file.size,
          type: selected_file.content_type
        }
      end)

    UploadCompat.file_input!(view, form_selector, upload_name, entries, Session.context(session).http.endpoint)
  end

  defp start_live_upload(session, client_dom, selected_files, target, event_context, form_key, form_selector, upload) do
    auto_upload? = live_auto_upload?(target)
    append? = live_multiple_file_input?(target) and live_upload_present?(session, form_key)
    session = if append?, do: session, else: release_live_upload_for_form(session, form_key)

    :ok = Processes.register(session.runtime, :upload_client, upload.pid)

    # The selection-triggered `phx-change` may replace or remove this input.
    # Register its client state before reconciling that render, so stale-input
    # cleanup can release the upload rather than leaving an unreachable ref.
    session =
      put_live_upload(
        session,
        client_dom,
        form_key,
        target,
        upload,
        selected_files,
        false,
        append?
      )

    result =
      View.dispatch_view_event(session, fn ->
        event_context.view
        |> element(form_selector)
        |> render_change(upload)
        |> ActionScope.delivered()
      end)

    case View.commit_render_result(session, client_dom, result, &prune_stale_live_uploads/1) do
      %Session{} = session when auto_upload? ->
        if live_upload_present?(session, form_key) do
          case dispatch_live_upload(session, form_key, upload, upload_entry_names(upload)) do
            {:ok, session} -> session |> mark_live_upload_uploaded(form_key, upload.pid) |> prune_stale_live_uploads()
            {reason, session} when reason in [:entry_error, :input_gone] -> prune_stale_live_uploads(session)
            {:navigation, navigation} -> navigation
          end
        else
          session
        end

      %Session{} = session ->
        session

      navigation ->
        navigation
    end
  end

  defp put_live_upload(session, client_dom, form_id, target, upload, selected_files, uploaded?, append?) do
    state = Session.page_state(session)

    live_uploads =
      UploadState.put(
        state.live_uploads,
        form_id,
        View.node_identity(client_dom, target),
        upload,
        selected_files,
        uploaded: uploaded?,
        append: append?
      )

    state
    |> Map.put(:client_dom, client_dom)
    |> Map.put(:live_uploads, live_uploads)
    |> then(&Session.put_page_state(session, &1))
  end

  defp live_upload_present?(session, form_id) do
    session |> Session.page_state() |> Map.fetch!(:live_uploads) |> UploadState.present?(form_id)
  end

  defp mark_live_upload_uploaded(session, form_id, upload_pid) do
    state = Session.page_state(session)

    state = %{
      state
      | live_uploads: UploadState.mark_uploaded(state.live_uploads, form_id, upload_pid)
    }

    Session.put_page_state(session, state)
  end

  defp live_auto_upload?(target) do
    attribute(target.attributes, "data-phx-auto-upload") not in [nil, false, "false"]
  end

  defp live_multiple_file_input?(target) do
    attribute(target.attributes, "multiple") not in [nil, false, "false"]
  end

  defp existing_upload_name!(target) do
    case attribute(target.attributes, "name") do
      name when is_binary(name) and name != "" ->
        case existing_atom(name) do
          {:ok, atom} ->
            atom

          :error ->
            raise Fluffy.CapabilityError,
              capability: :file_uploads,
              driver: :live,
              detail: "LiveView-managed file uploads require the input name to be an existing upload atom"
        end

      _missing_name ->
        raise Fluffy.CapabilityError,
          capability: :file_uploads,
          driver: :live,
          detail: "LiveView-managed file uploads require a named file input"
    end
  end

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  def live_upload_for_submit(session, target) do
    state = Session.page_state(session)

    case Form.owner_id(ClientDOM.index(state.client_dom), target) do
      nil ->
        :none

      form_id ->
        form_key = View.node_identity(state.client_dom, %{id: form_id})

        case UploadState.get(state.live_uploads, form_key) do
          nil -> :none
          upload_state -> {:ok, form_key, upload_state}
        end
    end
  end

  defp release_live_upload_for_form(session, form_id) do
    state = Session.page_state(session)

    case UploadState.fetch(state.live_uploads, form_id) do
      {:ok, upload_state} ->
        release_live_upload_clients(session, upload_state)
        {_form, live_uploads} = UploadState.delete_form(state.live_uploads, form_id)
        Session.put_page_state(session, %{state | live_uploads: live_uploads})

      :error ->
        session
    end
  end

  # Like LiveView's client after each patch, drop the selected files whose
  # entries the input's `data-phx-active-refs` no longer lists, such as ones
  # `cancel_upload/3` removed, so a later submit does not upload them. The
  # client is released with the last entry of its batch.
  defp prune_cancelled_live_uploads(session, form_id) do
    state = Session.page_state(session)
    upload_state = UploadState.get(state.live_uploads, form_id)

    with %{attributes: attributes} <- View.find_by_identity(state.client_dom, upload_state.input_identity),
         refs when is_binary(refs) <- attribute(attributes, "data-phx-active-refs") do
      active_refs = String.split(refs, ",")

      upload_state.batches
      |> Enum.reject(& &1.uploaded?)
      |> Enum.reduce(session, fn batch, session ->
        case Enum.split_with(batch.entries, &(&1.ref in active_refs)) do
          {_active, []} -> session
          {active, _cancelled} -> cancel_live_upload_entries(session, form_id, upload_state, batch, active)
        end
      end)
    else
      _no_active_refs -> session
    end
  end

  defp cancel_live_upload_entries(session, form_id, upload_state, batch, []) do
    session
    |> release_live_upload_client(batch.upload)
    |> remove_live_upload(form_id, batch.upload.pid)
    |> put_selected_live_upload_files(form_id, upload_state)
  end

  defp cancel_live_upload_entries(session, form_id, upload_state, batch, active_entries) do
    session
    |> put_live_upload_entries(form_id, batch.upload.pid, active_entries)
    |> put_selected_live_upload_files(form_id, upload_state)
  end

  defp put_selected_live_upload_files(session, form_id, upload_state) do
    selected_files =
      case UploadState.get(Session.page_state(session).live_uploads, form_id) do
        nil -> []
        form -> UploadState.selected_files(form.batches)
      end

    put_live_upload_files(session, upload_state, selected_files)
  end

  defp put_live_upload_files(session, %{input_identity: identity}, selected_files) do
    state = Session.page_state(session)

    # A finished upload outlives its input, so the input may be gone.
    case View.find_by_identity(state.client_dom, identity) do
      nil ->
        session

      input ->
        client_dom = ClientDOM.set_input_files(state.client_dom, Locator.by_css(input.selector), selected_files)
        Session.put_page_state(session, %{state | client_dom: client_dom})
    end
  end

  defp put_live_upload_entries(session, form_id, upload_pid, entries) do
    state = Session.page_state(session)
    live_uploads = UploadState.put_entries(state.live_uploads, form_id, upload_pid, entries)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  def dispatch_live_upload_submit(session, form_key, upload_state, submission) do
    # LiveView marks the form before any upload runs, so the marks survive a
    # submit that an upload entry error blocks.
    # A click's phx-click render may have removed the form; the uploads below
    # then find their input gone.
    state = Session.page_state(session)

    session =
      case View.find_by_identity(state.client_dom, form_key) do
        nil ->
          session

        form ->
          Session.put_page_state(session, %{state | client_dom: ClientDOM.mark_form_used(state.client_dom, form.id)})
      end

    upload_result =
      Enum.reduce_while(upload_state.batches, {:ok, session}, fn entry_upload, {:ok, session} ->
        case entry_upload do
          %{uploaded?: true} ->
            {:cont, {:ok, session}}

          %{entries: entries, upload: upload} ->
            case dispatch_live_upload(session, form_key, upload, entry_names(entries)) do
              {:ok, session} -> {:cont, {:ok, session}}
              {:input_gone, session} -> {:halt, {:input_gone, session}}
              {:entry_error, session} -> {:halt, {:entry_error, session}}
              {:navigation, navigation} -> {:halt, {:navigation, navigation}}
            end
        end
      end)

    case upload_result do
      {:ok, session} ->
        submit_after_uploads(session, form_key, submission)

      {reason, session} when reason in [:entry_error, :input_gone] ->
        prune_stale_live_uploads(session)

      {:navigation, navigation} ->
        navigation
    end
  end

  # A patch during the uploads can move or remove the form.
  defp submit_after_uploads(session, form_key, submission) do
    case current_upload_form(session, form_key) do
      nil ->
        session

      form ->
        with {:ok, event_context} <- View.owning_view_context(session, form) do
          dispatch_live_upload_submit_event(session, form_key, form, submission, event_context)
        end
    end
  end

  # A file input always has an id, so its form is the one to trust. Only when
  # the input is gone or left its form does the form's own identity decide.
  defp current_upload_form(session, form_key) do
    state = Session.page_state(session)
    form_of_upload_input(state, form_key) || View.find_by_identity(state.client_dom, form_key)
  end

  defp form_of_upload_input(state, form_key) do
    with %{} = input <- live_upload_input(state, form_key) do
      index = ClientDOM.index(state.client_dom)
      DocumentIndex.target_by_id(index, Form.owner_id(index, input))
    end
  end

  defp live_upload_input(state, form_key) do
    with %{input_identity: identity} <- UploadState.get(state.live_uploads, form_key) do
      View.find_by_identity(state.client_dom, identity)
    end
  end

  defp dispatch_live_upload_submit_event(session, form_key, form, submission, event_context) do
    state = Session.page_state(session)

    payload = Form.to_params(submission.fields)

    submit_result =
      View.dispatch_view_event(session, fn ->
        View.render_view_event(state.client_dom, event_context, form.selector, :submit, payload)
      end)

    case View.commit_render_result(session, state.client_dom, submit_result, &prune_stale_live_uploads/1) do
      %Session{} = session ->
        release_live_upload_for_form(session, form_key)

      {kind, %Session{} = session, navigation} when kind in [:navigate, :redirected] ->
        {kind, release_live_upload_for_form(session, form_key), navigation}
    end
  end

  defp remove_live_upload(session, form_id, upload_pid) do
    state = Session.page_state(session)
    live_uploads = UploadState.remove_batch(state.live_uploads, form_id, upload_pid)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  def release_live_upload_clients(session, %{batches: batches}) do
    Enum.each(batches, &release_live_upload_client(session, &1.upload))
  end

  defp release_live_upload_client(session, upload) do
    release_upload_client(session, upload)
    session
  end

  defp dispatch_live_upload(session, form_key, upload, entry_names) do
    Enum.reduce_while(entry_names, {:ok, session}, fn entry_name, {:ok, session} ->
      # A patch during the uploads can remove the input, releasing its client,
      # or move it away from its client's selector.
      with %{} = input <- live_upload_input(Session.page_state(session), form_key),
           {:ok, upload} <- upload_at_current_input(session, input, upload) do
        dispatch_live_upload_entry(session, upload, entry_name)
      else
        nil -> {:halt, {:input_gone, session}}
        navigation -> {:halt, {:navigation, navigation}}
      end
    end)
  end

  defp upload_at_current_input(session, input, upload) do
    client_dom = Session.page_state(session).client_dom

    with {:ok, context} <- View.owning_view_context(session, input) do
      {:ok, UploadCompat.at_input(upload, View.selector_for_view(client_dom, input.selector, context))}
    end
  end

  defp dispatch_live_upload_entry(session, upload, entry_name) do
    upload_result = View.dispatch_view_upload(session, upload, entry_name)

    case upload_result do
      # A progress callback that navigates returns its redirect, which
      # commits like any other render result.
      {:error, entry_errors} when not is_tuple(entry_errors) ->
        {:halt, {:entry_error, session}}

      _result ->
        state = Session.page_state(session)

        # The caller prunes once the uploads end: the view still has to consume
        # an upload whose own progress removed its input.
        case View.commit_render_result(session, state.client_dom, upload_result, & &1) do
          %Session{} = session -> {:cont, {:ok, session}}
          navigation -> {:halt, {:navigation, navigation}}
        end
    end
  end

  defp upload_entry_names(upload), do: Enum.map(upload.entries, &Map.fetch!(&1, "name"))
  defp entry_names(entries), do: Enum.map(entries, & &1.name)

  def prune_stale_live_uploads(%Session{} = session) do
    state = Session.page_state(session)

    {live_uploads, stale_uploads} =
      UploadState.prune(state.live_uploads, fn upload_state ->
        DocumentIndex.identity_present?(ClientDOM.index(state.client_dom), upload_state.input_identity) or
          UploadState.uploaded?(upload_state)
      end)

    Enum.each(stale_uploads, &release_live_upload_clients(session, &1))
    session = Session.put_page_state(session, %{state | live_uploads: live_uploads})

    live_uploads |> UploadState.form_ids() |> Enum.reduce(session, &prune_cancelled_live_uploads(&2, &1))
  end

  defp release_upload_client(session, upload) do
    Processes.release(session.runtime, :upload_client, upload.pid)

    UploadCompat.stop(upload)
  end
end
