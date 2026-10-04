defmodule TymeslotWeb.Dashboard.MeetingSettings.Card do
  @moduledoc """
  Component for displaying meeting type cards with toggle and action buttons.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext
  import TymeslotWeb.Components.PaymentHelpers, only: [format_amount: 2]
  alias Tymeslot.Availability.Schedules
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Integrations.Calendar.DisplayHelpers
  alias Tymeslot.Meetings.Approval
  alias Tymeslot.MeetingTypes
  alias Tymeslot.MeetingTypes.LocationOption
  alias Tymeslot.ShareLinks
  alias TymeslotWeb.Components.CoreComponents.Icons
  alias TymeslotWeb.Components.Dashboard.Availability.ScheduleAccents
  alias TymeslotWeb.Components.Icons.ProviderIcon
  alias TymeslotWeb.Components.UI.StatusSwitch

  @doc """
  Renders a meeting type card with status toggle and action buttons.
  """
  attr :type, :map, required: true
  attr :myself, :any, required: true
  attr :currency, :string, default: "eur"

  attr :schedules, :list,
    default: [],
    doc: "the profile's availability schedules, default first (`Schedules.list_for_profile/1`)"

  attr :icon_size, :string, default: "mini", values: ["compact", "medium", "large", "mini"]
  attr :venues, :list, default: [], doc: "the organiser's saved venues, to name them"

  attr :can_share, :boolean,
    default: false,
    doc: "whether the dashboard's share modal (`ShareLinksModalComponent`) is available"

  @spec meeting_type_card(map()) :: Phoenix.LiveView.Rendered.t()
  def meeting_type_card(assigns) do
    # The host's own translation for the language the dashboard is shown in,
    # as the booking page does for a guest.
    locale = Gettext.get_locale(TymeslotWeb.Gettext)

    assigns =
      assigns
      |> assign(:name, MeetingTypes.localized_name(assigns.type, locale))
      |> assign(:description, MeetingTypes.localized_description(assigns.type, locale))

    ~H"""
    <div class={[
      "card-glass py-3 px-4",
      if(@type.is_active, do: "card-glass-available", else: "card-glass-unavailable")
    ]}>
      <div class="flex items-center gap-3">
        <%!-- Drag Handle --%>
        <div class="cursor-grab active:cursor-grabbing text-neutral-400 dark:text-twilight-indigo-400 shrink-0">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 8h16M4 16h16"
            />
          </svg>
        </div>

        <%= if @type.icon && @type.icon != "none" do %>
          <Icons.icon
            name={@type.icon}
            class="w-5 h-5 text-neutral-600 dark:text-twilight-indigo-200 shrink-0"
          />
        <% end %>

        <%!-- Name + details --%>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 min-w-0">
            <h3 class="text-token-base font-medium text-neutral-800 dark:text-neutral-100 truncate">
              {@name}
            </h3>
            <span
              :if={@type.is_private}
              class="shrink-0 inline-flex items-center gap-1 px-2 py-0.5 rounded-token-full bg-neutral-100 dark:bg-twilight-indigo-800 text-neutral-600 dark:text-twilight-indigo-200 text-token-xs font-medium"
              title={
                dgettext(
                  "dashboard_meeting_types",
                  "Hidden from your public booking page; reachable only by its direct link"
                )
              }
            >
              <Icons.icon name="hero-eye-slash-mini" class="w-3 h-3" />{dgettext(
                "dashboard_meeting_types",
                "Unlisted"
              )}
            </span>
          </div>
          <p
            :if={described?(@description)}
            class="mt-0.5 text-token-xs text-neutral-500 dark:text-twilight-indigo-200 leading-relaxed line-clamp-2"
          >
            {@description}
          </p>
          <div class="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-0.5 text-token-xs text-neutral-600 dark:text-twilight-indigo-300">
            <span class="flex items-center shrink-0">
              <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              {dgettext("dashboard_meeting_types", "%{minutes} min", minutes: @type.duration_minutes)}
            </span>
            <%= if paid?(@type) do %>
              <span class="flex items-center shrink-0 font-medium text-emerald-600">
                <Icons.icon name="hero-banknotes-mini" class="w-3.5 h-3.5 mr-1" />
                {format_amount(@type.price_cents, @currency)}
              </span>
            <% end %>
            <.location_summary type={@type} icon_size={@icon_size} venues={@venues} />
            <%= if @type.calendar_integration do %>
              <span class="flex items-center min-w-0">
                <span class="mr-1.5 shrink-0">
                  <ProviderIcon.provider_icon
                    provider={@type.calendar_integration.provider}
                    size={@icon_size}
                  />
                </span>
                <span class="truncate max-w-[8rem]">
                  {@type.calendar_integration.name}
                </span>
                <span class="ml-1 text-neutral-500 dark:text-twilight-indigo-400 shrink-0">
                  ({calendar_display_name(@type)})
                </span>
                <.target_calendar_warning type={@type} />
              </span>
            <% end %>
            <.schedule_summary type={@type} schedules={@schedules} />
            <span
              :if={limits_label(@type)}
              class="flex items-center shrink-0"
              title={dgettext("dashboard_meeting_types", "Booking limits")}
            >
              <Icons.icon name="hero-scale-mini" class="w-3.5 h-3.5 mr-1" />
              {limits_label(@type)}
            </span>
            <span :if={Approval.required?(@type)} class="flex items-center shrink-0">
              <Icons.icon name="hero-shield-check-mini" class="w-3.5 h-3.5 mr-1" />
              {dgettext("dashboard_meeting_types", "Requires approval")}
            </span>
            <span :if={AttendeeAttachments.enabled_for?(@type)} class="flex items-center shrink-0">
              <Icons.icon name="hero-paper-clip-mini" class="w-3.5 h-3.5 mr-1" />
              {dgettext("dashboard_meeting_types", "Attachments")}
            </span>
            <%= if custom_question_count(@type) > 0 do %>
              <span class="flex items-center shrink-0 text-neutral-500 dark:text-twilight-indigo-400">
                <Icons.icon name="hero-question-mark-circle-mini" class="w-3.5 h-3.5 mr-1" />
                {custom_questions_label(@type)}
              </span>
            <% end %>
          </div>
        </div>

        <%!-- Actions --%>
        <div class="flex items-center gap-1.5 shrink-0">
          <StatusSwitch.status_switch
            id={"meeting-type-toggle-#{@type.id}"}
            checked={@type.is_active}
            size={:small}
            on_change="toggle_type"
            target={@myself}
            phx_value_id={to_string(@type.id)}
            aria_label={
              dgettext("dashboard_meeting_types", "Toggle %{name} availability", name: @name)
            }
            show_icon={false}
            class="shrink-0"
          />

          <button
            :if={@can_share && @type.is_active}
            id={"email-meeting-type-link-#{@type.id}"}
            type="button"
            phx-click="open"
            phx-value-preselect={ShareLinks.meeting_type_key(@type)}
            phx-target="#share-links-modal"
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_meeting_types", "Send link by email")}
            aria-label={dgettext("dashboard_meeting_types", "Send link by email")}
          >
            <Icons.icon name="hero-envelope" class="w-5 h-5" />
          </button>

          <button
            phx-click="edit_type"
            phx-value-id={@type.id}
            phx-target={@myself}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_meeting_types", "Edit")}
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
              />
            </svg>
          </button>

          <button
            phx-click="show_delete_modal"
            phx-value-id={@type.id}
            phx-target={@myself}
            class="row-action-button row-action-button--danger"
            title={dgettext("dashboard_meeting_types", "Delete")}
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Flags a meeting type whose stored booking target can no longer take the
  # booking, so a host reading the list sees the problem without opening the
  # editor. Renders nothing while the target is healthy.
  attr :type, :map, required: true

  @spec target_calendar_warning(map()) :: Phoenix.LiveView.Rendered.t()
  defp target_calendar_warning(assigns) do
    assigns =
      assign(assigns, :warning, target_calendar_warning_text(assigns.type))

    ~H"""
    <span
      :if={@warning}
      class="ml-1 shrink-0 inline-flex items-center gap-1 px-1.5 py-0.5 rounded-token-full bg-amber-50 text-amber-700 text-token-2xs font-semibold"
      title={@warning.title}
    >
      <Icons.icon name="hero-exclamation-triangle-micro" class="w-3 h-3" />{@warning.label}
    </span>
    """
  end

  defp target_calendar_warning_text(type) do
    case MeetingTypes.target_calendar_status(type) do
      :ok ->
        nil

      :read_only ->
        %{
          label: dgettext("dashboard_meeting_types", "Read-only"),
          title:
            dgettext(
              "dashboard_meeting_types",
              "This meeting type books into a calendar you can no longer write to. Edit it and choose another calendar."
            )
        }

      :missing ->
        %{
          label: dgettext("dashboard_meeting_types", "Calendar gone"),
          title:
            dgettext(
              "dashboard_meeting_types",
              "The calendar this meeting type books into is no longer on the connected account. Edit it and choose another calendar."
            )
        }
    end
  end

  defp paid?(%{payment_required: true, price_cents: cents}) when is_integer(cents), do: true
  defp paid?(_type), do: false

  defp described?(nil), do: false
  defp described?(description), do: String.trim(description) != ""

  # One location is named; several are counted. Naming them all would push
  # the calendar and question badges off the row on a card that is already a
  # single line of metadata.
  attr :type, :map, required: true
  attr :icon_size, :string, required: true
  attr :venues, :list, required: true

  defp location_summary(assigns) do
    assigns = assign(assigns, :locations, MeetingTypes.location_options(assigns.type))

    ~H"""
    <span :if={length(@locations) > 1} class="flex items-center shrink-0">
      <Icons.icon name="hero-map-pin-mini" class="w-3.5 h-3.5 mr-1 text-tymeslot-500" />
      <span>
        {dngettext(
          "dashboard_meeting_types",
          "%{count} location",
          "%{count} locations",
          length(@locations)
        )}
      </span>
    </span>
    <span :if={match?([_single], @locations)} class="flex items-center min-w-0">
      <span class="mr-1.5 shrink-0">
        <%!-- A video location keeps its provider's own mark, which is how the
              host recognises which account the rooms land on; the other kinds
              have no provider and take a plain glyph. --%>
        <ProviderIcon.provider_icon
          :if={video_provider(hd(@locations), @type)}
          provider={video_provider(hd(@locations), @type)}
          size={@icon_size}
        />
        <Icons.icon
          :if={is_nil(video_provider(hd(@locations), @type))}
          name={kind_icon(hd(@locations).kind)}
          class="w-3.5 h-3.5 text-tymeslot-500"
        />
      </span>
      <span class="truncate max-w-[10rem]">{single_label(hd(@locations), @venues)}</span>
    </span>
    """
  end

  # A single in-person location reads as where the meeting is: its one saved
  # venue by name, or how many the booker picks between. Venue ids no longer
  # in the library are ignored, so a deleted venue never shows; with none left
  # the location's own label stands.
  defp single_label(%LocationOption{kind: "in_person", venue_ids: ids} = location, venues) do
    case Enum.filter(venues, &(&1.id in ids)) do
      [] ->
        location.label

      [venue] ->
        venue.name

      several ->
        dngettext(
          "dashboard_meeting_types",
          "%{count} location",
          "%{count} locations",
          length(several)
        )
    end
  end

  defp single_label(location, _venues), do: location.label

  # The provider whose mark a video location shows, or nil for a location
  # that is not a video call (or whose integration has since been deleted,
  # leaving nothing to name).
  defp video_provider(%{kind: "video"}, %{video_integration: %{provider: provider}}), do: provider
  defp video_provider(_location, _type), do: nil

  defp kind_icon("video"), do: "hero-video-camera-mini"
  defp kind_icon("phone"), do: "hero-phone-mini"
  defp kind_icon("in_person"), do: "hero-building-office-mini"
  defp kind_icon(_kind), do: "hero-map-pin-mini"

  # The availability schedule the type books against, dotted in the colour the
  # availability page and the editor's schedule chips give it. A type with no
  # schedule of its own follows the profile default, named here so the host
  # sees which hours apply without opening the editor.
  attr :type, :map, required: true
  attr :schedules, :list, required: true

  defp schedule_summary(assigns) do
    assigns = assign(assigns, :schedule, resolve_schedule(assigns.type, assigns.schedules))

    ~H"""
    <span class="flex items-center min-w-0" title={@schedule.title}>
      <span :if={@schedule.dot} class={["w-2 h-2 mr-1.5 shrink-0 rounded-full", @schedule.dot]}></span>
      <Icons.icon :if={!@schedule.dot} name="hero-calendar-days-mini" class="w-3.5 h-3.5 mr-1" />
      <span class="truncate max-w-[10rem]">{@schedule.name}</span>
    </span>
    """
  end

  defp resolve_schedule(type, schedules) do
    indexed = Enum.with_index(schedules)

    {found, follows_default?} =
      case type.availability_schedule_id do
        nil -> {Enum.find(indexed, fn {schedule, _i} -> schedule.is_default end), true}
        id -> {Enum.find(indexed, fn {schedule, _i} -> schedule.id == id end), false}
      end

    {name, dot} =
      case found do
        {schedule, index} -> {schedule.name, ScheduleAccents.at(index)}
        nil -> {Schedules.default_schedule_name(), nil}
      end

    title =
      if follows_default? do
        dgettext("dashboard_meeting_types", "Availability schedule: %{name} (default)",
          name: name
        )
      else
        dgettext("dashboard_meeting_types", "Availability schedule: %{name}", name: name)
      end

    %{name: name, dot: dot, title: title}
  end

  # "2/day · 5/week", from whichever of the three caps are set; nil when none
  # is, so an unlimited type shows nothing.
  defp limits_label(type) do
    parts =
      Enum.reject(
        [
          limit_part(type.max_bookings_per_day, :day),
          limit_part(type.max_bookings_per_week, :week),
          limit_part(type.max_bookings_per_month, :month)
        ],
        &is_nil/1
      )

    if parts == [], do: nil, else: Enum.join(parts, " · ")
  end

  defp limit_part(count, :day) when is_integer(count),
    do: dgettext("dashboard_meeting_types", "%{count}/day", count: count)

  defp limit_part(count, :week) when is_integer(count),
    do: dgettext("dashboard_meeting_types", "%{count}/week", count: count)

  defp limit_part(count, :month) when is_integer(count),
    do: dgettext("dashboard_meeting_types", "%{count}/month", count: count)

  defp limit_part(_no_limit, _period), do: nil

  defp custom_question_count(%{custom_fields: fields}) when is_list(fields), do: length(fields)
  defp custom_question_count(_type), do: 0

  defp custom_questions_label(type) do
    count = custom_question_count(type)

    dngettext(
      "dashboard_meeting_types",
      "+%{count} custom question",
      "+%{count} custom questions",
      count,
      count: count
    )
  end

  defp calendar_display_name(%{calendar_integration: integration} = type) do
    calendar = Enum.find(integration.calendar_list || [], &(&1.id == type.target_calendar_id))

    name =
      if calendar do
        DisplayHelpers.extract_calendar_display_name(calendar)
      else
        dgettext("dashboard_meeting_types", "Calendar")
      end

    truncate_calendar_name(name)
  end

  defp truncate_calendar_name(name) when is_binary(name) do
    max_length = 15
    ellipsis = "..."

    if String.length(name) > max_length do
      String.slice(name, 0, max_length - String.length(ellipsis)) <> ellipsis
    else
      name
    end
  end
end
