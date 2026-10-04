defmodule TymeslotWeb.Dashboard.Contacts.Modals do
  @moduledoc """
  Modal components for the Contacts page: the delete confirmation and the
  "view meetings" list. Rendered inside `HubComponent` — every `phx-click`
  targets `@target` (the hub's `@myself`).
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Utils.DateTimeUtils.TimeFormat
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Helpers.LocaleFormat

  attr :contact, :map, required: true
  attr :target, :any, required: true

  @spec delete_contact_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def delete_contact_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id="delete-contact-modal"
      show={true}
      on_cancel={JS.push("hide_delete_modal", target: @target)}
      size={:small}
    >
      <:header>
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          {dgettext("dashboard_contacts", "Delete Contact?")}
        </div>
      </:header>

      <div class="text-center sm:text-left">
        <p class="text-neutral-600 dark:text-neutral-300 font-medium">
          {dgettext(
            "dashboard_contacts",
            "%{name} will be removed from your contacts. This does not affect their past or upcoming meetings.",
            name: @contact.name
          )}
        </p>
      </div>

      <:footer>
        <div class="flex justify-end gap-3">
          <CoreComponents.action_button
            variant={:secondary}
            phx-click={JS.push("hide_delete_modal", target: @target)}
          >
            {dgettext("dashboard_contacts", "Cancel")}
          </CoreComponents.action_button>
          <CoreComponents.action_button
            variant={:danger}
            phx-click={JS.push("delete_contact", target: @target)}
          >
            {dgettext("dashboard_contacts", "Delete Contact")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :contact, :map, required: true
  attr :meetings, :list, required: true
  attr :time_format, :string, required: true
  attr :target, :any, required: true

  @spec meetings_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def meetings_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id="contact-meetings-modal"
      show={true}
      on_cancel={JS.push("close_meetings_modal", target: @target)}
      size={:large}
    >
      <:header>
        <div class="flex flex-col">
          <span>{@contact.name}</span>
          <span class="text-neutral-500 dark:text-twilight-indigo-300 font-medium font-mono text-token-xs mt-1">{@contact.email}</span>
        </div>
      </:header>

      <%= if @meetings == [] do %>
        <div class="text-center py-12 bg-neutral-50 dark:bg-twilight-indigo-900/60 rounded-token-2xl border-2 border-dashed border-neutral-300 dark:border-twilight-indigo-800">
          <p class="text-neutral-600 dark:text-neutral-300 font-medium">
            {dgettext("dashboard_contacts", "No meetings yet")}
          </p>
        </div>
      <% else %>
        <div class="space-y-3">
          <div
            :for={meeting <- @meetings}
            class="border-2 border-neutral-300 dark:border-twilight-indigo-800 rounded-token-2xl p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <div class="font-black text-neutral-900 dark:text-neutral-50 truncate">
                  {meeting.title}
                </div>
                <div class="text-token-sm text-neutral-600 dark:text-neutral-300 font-medium flex items-center gap-1.5 mt-1">
                  <CoreComponents.icon name="hero-clock" class="w-4 h-4" />
                  {format_datetime(meeting.start_time, @time_format)}
                </div>
              </div>
              <span class="shrink-0 text-token-xs font-black uppercase tracking-wider text-neutral-500 dark:text-twilight-indigo-300 bg-neutral-50 dark:bg-twilight-indigo-900/60 border border-neutral-300 dark:border-twilight-indigo-700 rounded-token-lg px-2 py-1">
                {meeting.status}
              </span>
            </div>
          </div>
        </div>
      <% end %>

      <:footer>
        <div class="flex justify-end">
          <CoreComponents.action_button
            variant={:primary}
            phx-click={JS.push("close_meetings_modal", target: @target)}
          >
            {dgettext("dashboard_contacts", "Close")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  defp format_datetime(%DateTime{} = dt, time_format) do
    locale = Gettext.get_locale(TymeslotWeb.Gettext)
    date = LocaleFormat.format_date(dt, locale)
    time = TimeFormat.format(dt, time_format)
    dgettext("dashboard_contacts", "%{date} at %{time}", date: date, time: time)
  end

  defp format_datetime(_other, _time_format), do: ""
end
