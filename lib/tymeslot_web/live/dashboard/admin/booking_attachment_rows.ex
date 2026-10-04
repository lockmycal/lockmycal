defmodule TymeslotWeb.Dashboard.Admin.BookingAttachmentRows do
  @moduledoc """
  The "Booking attachments" section of the General settings tab: which file
  types a booker may attach on the booking page, how large each file may be
  and how many one booking may carry. Hosts can only switch the field on or
  off per meeting type; these limits are the admin's.

  Its own section rather than the generic loop in
  `TymeslotWeb.Dashboard.Admin.SettingsView` because the file types are one
  list-valued setting shown as a pill per type, which the generic row has no
  control for. The two numeric limits reuse `SettingsView.setting_row/1`, so
  they look and save like every other number setting. The type pills fire
  `"toggle_booking_attachment_type"`, handled by
  `TymeslotWeb.Dashboard.Admin.HubComponent`.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.AppSettings.AppSettingsSchema
  alias TymeslotWeb.Dashboard.Admin.Formatters
  alias TymeslotWeb.Dashboard.Admin.SettingsView

  attr :effective_values, :map, required: true
  attr :target, :any, required: true

  @spec booking_attachments_section(map()) :: Phoenix.LiveView.Rendered.t()
  def booking_attachments_section(assigns) do
    assigns =
      assigns
      |> assign(:all_types, AppSettingsSchema.booking_attachment_types())
      |> assign(:selected, Map.fetch!(assigns.effective_values, :booking_attachment_types).value)

    ~H"""
    <section>
      <.subsection_header
        icon="hero-paper-clip"
        title={Formatters.section_label(:booking_attachments)}
        class="mb-3"
      />

      <div class="card-glass p-0! overflow-hidden divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <div
          id="admin-setting-row-booking_attachment_types"
          class="px-8 py-6 flex flex-col gap-4"
        >
          <SettingsView.row_header key={:booking_attachment_types} muted={@selected == []} />

          <div
            role="group"
            aria-label={
              dgettext("dashboard_admin", "Set %{name}",
                name: Formatters.humanise(:booking_attachment_types)
              )
            }
            class="inline-flex flex-wrap self-start max-w-full p-1 bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1"
          >
            <button
              :for={type <- @all_types}
              type="button"
              id={"admin-attachment-type-#{type}"}
              phx-click="toggle_booking_attachment_type"
              phx-value-type={type}
              phx-target={@target}
              aria-pressed={to_string(type in @selected)}
              class={[
                "px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all cursor-pointer",
                if(type in @selected,
                  do: "bg-primary-600 text-white",
                  else:
                    "text-neutral-500 dark:text-neutral-50 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-50"
                )
              ]}
            >
              {type}
            </button>
          </div>
        </div>

        <SettingsView.setting_row
          key={:max_booking_attachment_size_mb}
          effective_values={@effective_values}
          target={@target}
        />
        <SettingsView.setting_row
          key={:max_booking_attachments}
          effective_values={@effective_values}
          target={@target}
        />
      </div>
    </section>
    """
  end
end
