defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.FormView do
  @moduledoc """
  Markup for the meeting type form.

  Extracted from `MeetingTypeForm` so that module stays focused on lifecycle
  and event routing, matching how `CalendarSettings.ComponentView` sits behind
  `CalendarSettingsComponent`. `form/1` receives the component's assigns
  unchanged (its `render/1` delegates straight to it), so LiveView change
  tracking is preserved.

  The sections are grouped into five panels. In edit mode a tab bar shows one
  panel at a time; in create mode the same panels render stacked, so the
  markup below is the single source of the section grouping and order for
  both modes. Inactive panels are hidden with CSS rather than conditionally
  rendered, keeping every input in the DOM (create mode submits the whole
  form) and preserving the custom-questions component's state across tab
  switches.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Locales
  alias Tymeslot.Meetings.Guests
  alias Tymeslot.Validation.Constraints
  alias TymeslotWeb.Components.Dashboard.LocaleTabSwitcher
  alias TymeslotWeb.Dashboard.MeetingSettings.Helpers

  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.{
    ApprovalSection,
    AttachmentsSection,
    Autosave,
    AvailabilitySection,
    ContactSharingSection,
    CustomQuestionsSection,
    GuestsSection,
    HiddenFields,
    LimitsSection,
    LocationEditorComponent,
    LocationsSection,
    PaymentsSection,
    QuestionEditorComponent,
    ShowAsFreeSection,
    SlotInterval,
    VisibilitySection
  }

  alias TymeslotWeb.Live.Shared.FormValidationHelpers

  import ApprovalSection, only: [approval_section: 1]
  import AvailabilitySection, only: [availability_section: 1]
  import ContactSharingSection, only: [contact_sharing_section: 1]
  import GuestsSection, only: [guests_section: 1]
  import AttachmentsSection, only: [attachments_section: 1]
  import LimitsSection, only: [limits_section: 1]
  import ShowAsFreeSection, only: [show_as_free_section: 1]
  import HiddenFields, only: [hidden_fields: 1]
  import PaymentsSection, only: [payments_section: 1]
  import VisibilitySection, only: [visibility_section: 1]
  import TymeslotWeb.Dashboard.MeetingSettings.Components.BookingComponents
  import TymeslotWeb.Dashboard.MeetingSettings.Components.Reminders

  # Which form-error fields surface an indicator on which tab. Errors on
  # fields absent here (e.g. :base) render below the panels and need no dot.
  @tab_error_fields %{
    "details" => [:name, :duration, :slot_interval, :description, :icon, :translations],
    "location" => [:locations, :video_integration, :calendar_integration, :target_calendar],
    "booking" => [:payment_required, :price_cents, :approval_window_hours],
    "reminders" => [:reminder_config]
  }

  @spec form(map()) :: Phoenix.LiveView.Rendered.t()
  def form(assigns) do
    ~H"""
    <div id={"meeting-type-form-wrapper-#{@id}"}>
      <.subsection_header
        :if={!@is_edit}
        icon="hero-identification"
        title={dgettext("dashboard_meeting_form", "Meeting details")}
        class="mb-2"
      />

      <div class={if @is_edit, do: nil, else: "card-glass"}>
        <form
          id={"meeting-type-form-#{@id}"}
          phx-submit={if @is_edit, do: "flush_autosave", else: "save_meeting_type"}
          phx-target={if @is_edit, do: @myself, else: @parent_myself}
          class={if @is_edit, do: "space-y-6", else: "space-y-8"}
          novalidate
        >
          <.tab_bar
            :if={@is_edit}
            active_tab={@active_tab}
            target={@myself}
            tabs={form_tabs(@form_errors, @custom_questions_allowed)}
          />

          <%!-- Details --%>
          <div
            id="panel-details"
            role={@is_edit && "tabpanel"}
            aria-labelledby={@is_edit && "tab-details"}
            hidden={@is_edit && @active_tab != "details"}
            class={panel_class(@is_edit, @active_tab, "details")}
          >
            <.subsection_header
              :if={@is_edit}
              icon="hero-identification"
              title={dgettext("dashboard_meeting_form", "Meeting details")}
              class="mb-2"
            />

            <LocaleTabSwitcher.locale_tab_switcher
              active_value={@active_translation_locale}
              click_event="switch_translation_locale"
              target={@myself}
            />

            <div :if={@active_translation_locale == Locales.default_locale()} class="space-y-4">
              <div class="card-glass space-y-4">
                <.input
                  name="meeting_type[name]"
                  label={dgettext("dashboard_meeting_form", "Name")}
                  value={Map.get(@form_data, "name", if(@type, do: @type.name, else: ""))}
                  required
                  maxlength={Constraints.name_length_opts()[:max]}
                  placeholder={dgettext("dashboard_meeting_form", "e.g., Quick Chat")}
                  phx-change="validate_meeting_type"
                  phx-debounce="500"
                  phx-target={@myself}
                  errors={
                    FormValidationHelpers.field_errors(@form_errors, :name)
                    |> Enum.map(&Helpers.format_errors/1)
                  }
                  icon="hero-tag"
                />

                <.input
                  name="meeting_type[description]"
                  label={dgettext("dashboard_meeting_form", "Description (optional)")}
                  value={
                    Map.get(@form_data, "description", if(@type, do: @type.description, else: ""))
                  }
                  maxlength={Constraints.description_max_length()}
                  placeholder={
                    dgettext("dashboard_meeting_form", "Brief description of this meeting type")
                  }
                  phx-change="validate_meeting_type"
                  phx-debounce="500"
                  phx-target={@myself}
                  errors={
                    FormValidationHelpers.field_errors(@form_errors, :description)
                    |> Enum.map(&Helpers.format_errors/1)
                  }
                  icon="hero-document-text"
                />

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <.input
                      type="number"
                      name="meeting_type[duration]"
                      label={dgettext("dashboard_meeting_form", "Duration (minutes)")}
                      value={
                        Map.get(
                          @form_data,
                          "duration",
                          if(@type, do: @type.duration_minutes, else: "30")
                        )
                      }
                      min={Constraints.duration_minutes_opts()[:greater_than_or_equal_to]}
                      max={Constraints.duration_minutes_opts()[:less_than_or_equal_to]}
                      step="5"
                      required
                      placeholder="30"
                      phx-change="validate_meeting_type"
                      phx-debounce="500"
                      phx-target={@myself}
                      errors={
                        FormValidationHelpers.field_errors(@form_errors, :duration)
                        |> Enum.map(&Helpers.format_errors/1)
                      }
                      icon="hero-clock"
                    />
                    <p class="mt-1 text-token-sm text-neutral-600 dark:text-neutral-400">
                      {dgettext(
                        "dashboard_meeting_form",
                        "Enter a duration between %{min} and %{max} minutes",
                        min: Constraints.duration_minutes_opts()[:greater_than_or_equal_to],
                        max: Constraints.duration_minutes_opts()[:less_than_or_equal_to]
                      )}
                    </p>
                  </div>

                  <% slot_interval_value =
                    Map.get(
                      @form_data,
                      "slot_interval",
                      if(@type, do: @type.slot_interval_minutes, else: "")
                    ) %>
                  <% slot_interval_custom? = SlotInterval.custom?(assigns, slot_interval_value) %>
                  <div>
                    <.input
                      type="select"
                      name="meeting_type[slot_interval]"
                      label={dgettext("dashboard_meeting_form", "Booking slot interval")}
                      value={
                        if(slot_interval_custom?,
                          do: SlotInterval.custom_option(),
                          else: slot_interval_value
                        )
                      }
                      options={SlotInterval.options(slot_interval_value, slot_interval_custom?)}
                      phx-change="validate_meeting_type"
                      phx-target={@myself}
                      errors={
                        if(slot_interval_custom?,
                          do: [],
                          else:
                            FormValidationHelpers.field_errors(@form_errors, :slot_interval)
                            |> Enum.map(&Helpers.format_errors/1)
                        )
                      }
                      icon="hero-adjustments-horizontal"
                    />
                    <%!-- The number input carries the same param name as the select, so
                        whichever control is on screen is the one that posts the value
                        and the two can never disagree about what is stored. --%>
                    <div :if={slot_interval_custom?} class="mt-2">
                      <.input
                        type="number"
                        name="meeting_type[slot_interval]"
                        label={dgettext("dashboard_meeting_form", "Custom interval (minutes)")}
                        value={slot_interval_value}
                        min={Constraints.slot_interval_minutes_range().first}
                        max={Constraints.slot_interval_minutes_range().last}
                        step="1"
                        phx-change="validate_meeting_type"
                        phx-debounce="500"
                        phx-target={@myself}
                        errors={
                          FormValidationHelpers.field_errors(@form_errors, :slot_interval)
                          |> Enum.map(&Helpers.format_errors/1)
                        }
                        icon="hero-adjustments-horizontal"
                      />
                    </div>
                    <p class="mt-1 text-token-sm text-tymeslot-600">
                      {SlotInterval.hint(slot_interval_value, Map.get(@form_data, "duration"))}
                    </p>
                  </div>
                </div>
              </div>

              <.icon_picker
                selected_icon={@selected_icon}
                form_errors={@form_errors}
                myself={@myself}
              />
            </div>

            <div
              :if={@active_translation_locale != Locales.default_locale()}
              class="card-glass space-y-4"
            >
              <% translation = current_translation(@translations, @active_translation_locale) %>
              <.input
                name="translation[name]"
                label={dgettext("dashboard_meeting_form", "Name")}
                value={(translation && translation.name) || ""}
                maxlength={Constraints.name_length_opts()[:max]}
                placeholder={Map.get(@form_data, "name", if(@type, do: @type.name, else: ""))}
                phx-change="validate_meeting_type_translation"
                phx-debounce="500"
                phx-target={@myself}
                icon="hero-tag"
              />
              <.input
                name="translation[description]"
                label={dgettext("dashboard_meeting_form", "Description (optional)")}
                value={(translation && translation.description) || ""}
                maxlength={Constraints.description_max_length()}
                placeholder={
                  Map.get(@form_data, "description", if(@type, do: @type.description, else: ""))
                }
                phx-change="validate_meeting_type_translation"
                phx-debounce="500"
                phx-target={@myself}
                icon="hero-document-text"
              />
            </div>
          </div>

          <%!-- Location & Calendar --%>
          <div
            id="panel-location"
            role={@is_edit && "tabpanel"}
            aria-labelledby={@is_edit && "tab-location"}
            hidden={@is_edit && @active_tab != "location"}
            class={panel_class(@is_edit, @active_tab, "location")}
          >
            <.live_component
              module={LocationsSection}
              id={"locations-section-#{@id}"}
              locations={@locations}
              video_integrations={@video_integrations}
              venues={@venues}
              form_id={@id}
            />

            <.booking_destination_section
              calendar_integrations={@calendar_integrations}
              selected_calendar_integration_id={@selected_calendar_integration_id}
              refreshing_calendars={@refreshing_calendars}
              available_calendars={@available_calendars}
              no_writable_calendars={@no_writable_calendars}
              target_calendar_status={@target_calendar_status}
              selected_target_calendar_id={@selected_target_calendar_id}
              form_errors={@form_errors}
              myself={@myself}
            />

            <.show_as_free_section show_as_free={@show_as_free} myself={@myself} />
          </div>

          <%!-- Booking Rules --%>
          <div
            id="panel-booking"
            role={@is_edit && "tabpanel"}
            aria-labelledby={@is_edit && "tab-booking"}
            hidden={@is_edit && @active_tab != "booking"}
            class={panel_class(@is_edit, @active_tab, "booking")}
          >
            <.payments_section
              :if={@payments_feature_enabled}
              charges_enabled={@payments_charges_enabled}
              payment_required={@payment_required}
              payment_price={@payment_price}
              currency={@payment_currency}
              currency_minimum_cents={@payment_currency_minimum_cents}
              form_errors={@form_errors}
              myself={@myself}
            />

            <.guests_section
              allow_guests={@allow_guests}
              max_guests={Guests.max_guests()}
              myself={@myself}
            />

            <.attachments_section allow_attachments={@allow_attachments} myself={@myself} />

            <.limits_section booking_limits={@booking_limits} myself={@myself} />

            <.visibility_section :if={@is_edit && @type} type={@type} parent={@parent_myself} />

            <.approval_section
              requires_approval={@requires_approval}
              approval_window_hours={@approval_window_hours}
              errors={
                @form_errors
                |> FormValidationHelpers.field_errors(:approval_window_hours)
                |> Enum.map(&Helpers.format_errors/1)
              }
              myself={@myself}
            />

            <.contact_sharing_section
              show_email_to_bookers={@show_email_to_bookers}
              show_phone_to_bookers={@show_phone_to_bookers}
              myself={@myself}
            />

            <.availability_section
              schedules={@schedules}
              default_schedule_name={@default_schedule_name}
              selected_availability_schedule_id={@selected_availability_schedule_id}
              myself={@myself}
            />
          </div>

          <%!-- Questions --%>
          <div
            id="panel-questions"
            role={@is_edit && "tabpanel"}
            aria-labelledby={@is_edit && "tab-questions"}
            hidden={@is_edit && @active_tab != "questions"}
            class={panel_class(@is_edit, @active_tab, "questions")}
          >
            <.live_component
              module={CustomQuestionsSection}
              id={"custom-questions-section-#{@id}"}
              custom_fields={@custom_fields}
              form_id={@id}
              allowed={@custom_questions_allowed}
              current_user={@current_user}
            />
          </div>

          <%!-- Reminders --%>
          <div
            id="panel-reminders"
            role={@is_edit && "tabpanel"}
            aria-labelledby={@is_edit && "tab-reminders"}
            hidden={@is_edit && @active_tab != "reminders"}
            class={panel_class(@is_edit, @active_tab, "reminders")}
          >
            <.reminders_section
              reminders={@reminders}
              max_reminders={@max_reminders}
              new_reminder_value={@new_reminder_value}
              new_reminder_unit={@new_reminder_unit}
              reminder_error={@reminder_error}
              show_custom_reminder={@show_custom_reminder}
              reminder_confirmation={@reminder_confirmation}
              form_errors={@form_errors}
              myself={@myself}
            />
          </div>

          <%!-- Create-mode form serialisation. Edits auto-save from socket assigns
           (see Autosave/Submission) and never post the form, so these hidden
           inputs are only needed when creating. --%>
          <.hidden_fields
            :if={!@is_edit}
            type={@type}
            selected_icon={@selected_icon}
            locations={@locations}
            venues={@venues}
            selected_calendar_integration_id={@selected_calendar_integration_id}
            selected_target_calendar_id={@selected_target_calendar_id}
            selected_availability_schedule_id={@selected_availability_schedule_id}
            reminders={@reminders}
            custom_fields={@custom_fields}
            custom_questions_allowed={@custom_questions_allowed}
            translations={@translations}
            payments_feature_enabled={@payments_feature_enabled}
            payments_charges_enabled={@payments_charges_enabled}
            payment_required={@payment_required}
            payment_price={@payment_price}
            allow_guests={@allow_guests}
            allow_attachments={@allow_attachments}
            requires_approval={@requires_approval}
            approval_window_hours={@approval_window_hours}
            show_as_free={@show_as_free}
            show_email_to_bookers={@show_email_to_bookers}
            show_phone_to_bookers={@show_phone_to_bookers}
          />

          <%= for error <- FormValidationHelpers.field_errors(@form_errors, :base) do %>
            <p class="form-error">{Helpers.format_errors(error)}</p>
          <% end %>

          <div class="flex items-center justify-between gap-4">
            <%= if @is_edit do %>
              <Autosave.indicator status={@save_status} />
              <button
                type="button"
                phx-click="close_edit_overlay"
                phx-target={@parent_myself}
                class="btn btn-primary"
              >
                {dgettext("dashboard_meeting_form", "Done")}
              </button>
            <% else %>
              <span></span>
              <div class="flex justify-end space-x-3">
                <button
                  type="button"
                  phx-click="toggle_add_form"
                  phx-target={@parent_myself}
                  class="btn btn-secondary"
                >
                  {dgettext("dashboard_meeting_form", "Cancel")}
                </button>
                <button
                  type="submit"
                  disabled={@saving || @refreshing_calendars}
                  class="btn btn-primary"
                >
                  <%= if @saving do %>
                    <span class="flex items-center">
                      <.spinner class="h-4 w-4 mr-2" />
                      {dgettext("dashboard_meeting_form", "Saving...")}
                    </span>
                  <% else %>
                    {dgettext("dashboard_meeting_form", "Create Meeting Type")}
                  <% end %>
                </button>
              </div>
            <% end %>
          </div>
        </form>
      </div>

      <%!-- Location editor modal — rendered outside <form> to avoid nested forms --%>
      <%= if @editing_location do %>
        <.live_component
          module={LocationEditorComponent}
          id={"location-editor-#{@id}"}
          location={@editing_location}
          existing_locations={@locations}
          video_integrations={@video_integrations}
          venues={@venues}
          current_user={@current_user}
          parent_myself={@parent_myself}
          form_id={@id}
          mode={@editing_location_mode}
        />
      <% end %>

      <%!-- Question editor modal — rendered outside <form> to avoid nested forms --%>
      <%= if @editing_question do %>
        <.live_component
          module={QuestionEditorComponent}
          id={"question-editor-#{@id}"}
          definition={@editing_question}
          existing_fields={@custom_fields}
          form_id={@id}
          mode={@editing_question_mode}
        />
      <% end %>
    </div>
    """
  end

  defp form_tabs(form_errors, custom_questions_allowed) do
    tabs = [
      %{
        id: "details",
        label: dgettext("dashboard_meeting_form", "Details"),
        icon: "hero-pencil-square"
      },
      %{
        id: "location",
        label: dgettext("dashboard_meeting_form", "Location & Calendar"),
        icon: "hero-map-pin"
      },
      %{
        id: "booking",
        label: dgettext("dashboard_meeting_form", "Booking Rules"),
        icon: "hero-adjustments-horizontal"
      },
      %{
        id: "questions",
        label: dgettext("dashboard_meeting_form", "Questions"),
        icon: "hero-chat-bubble-left-right",
        badge: !custom_questions_allowed && dgettext("dashboard_common", "Pro")
      },
      %{
        id: "reminders",
        label: dgettext("dashboard_meeting_form", "Reminders"),
        icon: "hero-bell"
      }
    ]

    Enum.map(tabs, &Map.put(&1, :error, tab_has_errors?(form_errors, &1.id)))
  end

  defp tab_has_errors?(form_errors, tab_id) do
    @tab_error_fields
    |> Map.get(tab_id, [])
    |> Enum.any?(&(FormValidationHelpers.field_errors(form_errors, &1) != []))
  end

  defp current_translation(translations, locale),
    do: Enum.find(translations, &(&1.locale == locale))

  # In create mode the panels are invisible groupings in one stacked form;
  # in edit mode each is a card and only the active one is shown.
  defp panel_class(false = _is_edit, _active_tab, _panel_id), do: "space-y-4"

  defp panel_class(true = _is_edit, active_tab, panel_id) do
    ["card-glass space-y-6", active_tab != panel_id && "hidden"]
  end
end
