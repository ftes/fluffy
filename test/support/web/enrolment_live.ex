defmodule Fluffy.Support.Web.EnrolmentLive do
  @moduledoc false

  use Phoenix.LiveView

  # The shape of phx.gen.auth's `--live` registration: `validate` echoes every
  # field, and `save` renders the form again from the enrolled student, without
  # the password or motto, as it triggers the HTTP sign-in. Once given, the owl
  # post address is kept in a hidden input, which `save` lowercases.
  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :student), trigger?: false)}
  end

  @impl true
  def handle_event("validate", %{"student" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: :student))}

  def handle_event("save", %{"student" => params}, socket) do
    enrolled = %{"email" => String.downcase(params["email"])}
    {:noreply, assign(socket, form: to_form(enrolled, as: :student), trigger?: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.form
      for={@form}
      id="enrolment-form"
      action="/session/enrol?_action=registered"
      method="post"
      phx-change="validate"
      phx-submit="save"
      phx-trigger-action={@trigger?}
    >
      <label>
        Owl post
        <input
          type={if @form[:email].value in [nil, ""], do: "email", else: "hidden"}
          name={@form[:email].name}
          value={@form[:email].value}
        />
      </label>
      <label>
        Password <input type="password" name={@form[:password].name} value={@form[:password].value} />
      </label>
      <label>Motto <textarea name={@form[:motto].name}>{@form[:motto].value}</textarea></label>
      <button>Enrol at Hogwarts</button>
    </.form>
    """
  end
end
