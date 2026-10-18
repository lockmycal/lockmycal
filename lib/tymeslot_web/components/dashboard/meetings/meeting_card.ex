defmodule TymeslotWeb.Components.Dashboard.Meetings.MeetingCard do
  @moduledoc """
  One booking on the Meetings page: who booked, which meeting type, when, how
  to reach them, their guests, notes, attachments and answers, reminders, and
  the actions the booking allows.

  A booking the signed-in user made on someone else's page is shown from their
  side (`attending?`): named after its host, with the host's contact details as
  far as the host shared them.

  Split out of `MeetingListComponents`, which keeps the list around it.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.CustomFields.AnswerRenderer
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.Seats
  alias TymeslotWeb.Components.CoreComponents.Buttons
  alias TymeslotWeb.Components.CoreComponents.Containers
  alias TymeslotWeb.Components.CoreComponents.Feedback
  alias TymeslotWeb.Components.CoreComponents.Icons
  alias TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachments
  alias TymeslotWeb.Components.Dashboard.Meetings.GuestStatusPill
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers
  alias TymeslotWeb.Components.Dashboard.Meetings.MeetingActions
  alias TymeslotWeb.Components.Dashboard.Meetings.MeetingStatusBadge
  alias TymeslotWeb.Components.Dashboard.Meetings.RemindersSection

  attr :meeting, :map, required: true
  attr :profile, :any, required: false
  attr :time_format, :string, required: true
  attr :cancelling_meeting, :any, required: false
  attr :sending_reschedule, :any, required: false
  attr :answering_request, :any, default: nil
  attr :deleting_meeting, :any, required: false
  attr :current_user_email, :string, default: nil
  attr :target, :any, required: true

  @spec meeting_card(map()) :: Phoenix.LiveView.Rendered.t()
  def meeting_card(assigns) do
    timezone = Helpers.get_meeting_timezone(assigns.meeting, assigns[:profile])
    attending? = Meetings.attended_by?(assigns.meeting, assigns.current_user_email)

    assigns =
      assign(assigns,
        timezone: timezone,
        attending?: attending?,
        organizer?: Meetings.organized_by?(assigns.meeting, assigns.current_user_email),
        guests: guest_list(assigns.meeting),
        group?: Helpers.group_meeting?(assigns.meeting),
        participants: Helpers.participants(assigns.meeting),
        answered_fields: answered_fields(assigns.meeting),
        cancelled_on:
          assigns.meeting.status == "cancelled" &&
            Helpers.format_cancelled_at_date(assigns.meeting, timezone),
        contact_email: contact_email(assigns.meeting, attending?),
        contact_phone: contact_phone(assigns.meeting, attending?)
      )

    ~H"""
    <Containers.card>
      <.calendar_sync_banner
        :if={
          @meeting.calendar_sync_status == "externally_deleted" or
            (@meeting.calendar_sync_status in ["externally_modified", "creation_failed"] and
               is_nil(@meeting.calendar_sync_status_dismissed_at))
        }
        meeting={@meeting}
        profile={@profile}
        organizer?={@organizer?}
        target={@target}
      />
      <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-8">
        <%!-- A container, so the details run three to a row by the room this
              column has beside the action bar, not by the window's width. --%>
        <div class="@container flex-1 min-w-0">
          <div class="flex items-center gap-3 flex-wrap mb-6">
            <h2 class="text-token-lg font-semibold text-neutral-900 dark:text-neutral-50">
              {if @attending?, do: @meeting.organizer_name, else: meeting_title(@meeting)}
            </h2>
            <span
              :if={@meeting.attendee_company && !@attending?}
              class="text-token-sm font-bold text-neutral-400 bg-neutral-50 px-3 py-1 rounded-token-lg dark:text-twilight-indigo-300 dark:bg-twilight-indigo-900/60"
            >
              {@meeting.attendee_company}
            </span>
            <MeetingStatusBadge.status_badges meeting={@meeting} organizer?={@organizer?} />
            <Feedback.pill
              :if={@group?}
              tone={:brand}
              size={:sm}
              icon="hero-users"
              data-testid="group-seats-badge"
            >
              {seats_label(@meeting, @guests)}
            </Feedback.pill>
            <Feedback.pill
              :if={Meetings.organizer_join_url(@meeting)}
              tone={:info}
              size={:sm}
              icon="hero-video-camera"
            >
              {dgettext("dashboard_bookings", "Video Call")}
            </Feedback.pill>
            <AttendeeAttachments.badge attachments={@meeting.attendee_attachments} />
          </div>

          <div class="grid grid-cols-1 @lg:grid-cols-2 @2xl:grid-cols-3 gap-x-6 gap-y-4">
            <Containers.detail_line
              variant={:tile}
              icon="hero-calendar-days"
              label={dgettext("dashboard_bookings", "Date & Time")}
              data-testid="meeting-date-time"
            >
              {Helpers.format_meeting_date(@meeting, @timezone)}
              <span class="block text-primary-600 dark:text-primary-400">
                {Helpers.format_meeting_time(@meeting, @timezone, @time_format)}
              </span>
            </Containers.detail_line>
            <Containers.detail_line
              :if={@cancelled_on}
              variant={:tile}
              tone={:danger}
              icon="hero-x-circle"
              label={dgettext("dashboard_bookings", "Cancelled On")}
            >
              {@cancelled_on}
            </Containers.detail_line>
            <Containers.detail_line
              :if={@meeting.meeting_type && @meeting.meeting_type != ""}
              variant={:tile}
              icon="hero-squares-2x2"
              label={dgettext("dashboard_bookings", "Meeting type")}
              data-testid="meeting-type"
            >
              {@meeting.meeting_type}
            </Containers.detail_line>
            <RemindersSection.reminders_section meeting={@meeting} />
            <%!-- A group slot has no single attendee: every booker is listed
                 in the participants panel below. --%>
            <Containers.detail_line
              :if={not @group? and @contact_email}
              variant={:tile}
              tone={:info}
              icon="hero-envelope"
              label={
                if @attending?,
                  do: dgettext("dashboard_bookings", "Host Email"),
                  else: dgettext("dashboard_bookings", "Attendee Email")
              }
            >
              <a href={"mailto:#{@contact_email}"} class="hover:text-primary-600 transition-colors">
                {@contact_email}
              </a>
            </Containers.detail_line>
            <Containers.detail_line
              :if={@contact_phone}
              variant={:tile}
              tone={:info}
              icon="hero-phone"
              label={
                if @attending?,
                  do: dgettext("dashboard_bookings", "Host Phone"),
                  else: dgettext("dashboard_bookings", "Attendee Phone")
              }
            >
              <a href={"tel:#{@contact_phone}"} class="hover:text-primary-600 transition-colors">
                {@contact_phone}
              </a>
            </Containers.detail_line>
          </div>

          <%!-- Participants panel, group meetings only. The preload keeps to
               live participants, except on a cancelled meeting, where it also
               brings those who left the slot (released or moved their seat),
               marked as such. --%>
          <.sub_panel
            :if={@participants != []}
            icon="hero-users"
            title={dgettext("dashboard_bookings", "Participants")}
          >
            <ul class="space-y-2.5">
              <li :for={participant <- @participants} class="flex items-center justify-between gap-3">
                <span class="flex items-center gap-2.5 min-w-0">
                  <.initial person={participant} />
                  <span class="truncate text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
                    {participant.name}
                  </span>
                  <Feedback.pill
                    :if={participant.cancelled_at}
                    class="flex-none"
                    data-testid="participant-released"
                  >
                    {dgettext("dashboard_bookings", "Left this slot")}
                  </Feedback.pill>
                </span>
                <a
                  href={"mailto:#{participant.email}"}
                  class="truncate text-token-sm font-medium text-neutral-500 hover:text-primary-600 transition-colors dark:text-twilight-indigo-300"
                >
                  {participant.email}
                </a>
              </li>
            </ul>
          </.sub_panel>

          <.sub_panel
            :if={@guests != []}
            icon="hero-user-group"
            title={dgettext("dashboard_bookings", "Guests")}
          >
            <:aside>{guest_summary_label(@guests)}</:aside>
            <ul class="space-y-2.5">
              <li :for={guest <- @guests} class="flex items-center justify-between gap-3">
                <span class="flex items-center gap-2.5 min-w-0">
                  <.initial person={guest} />
                  <span class="truncate text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
                    {guest.name || guest.email}
                  </span>
                </span>
                <GuestStatusPill.guest_status_pill status={guest.status} />
              </li>
            </ul>
          </.sub_panel>

          <.sub_panel
            :if={@meeting.attendee_message && @meeting.attendee_message != ""}
            icon="hero-pencil-square"
            title={dgettext("dashboard_bookings", "Meeting Notes")}
          >
            <p class="text-neutral-600 font-medium leading-relaxed dark:text-neutral-300">
              {@meeting.attendee_message}
            </p>
          </.sub_panel>

          <.sub_panel
            :if={@meeting.attendee_attachments != [] and @organizer?}
            icon="hero-paper-clip"
            title={dgettext("dashboard_bookings", "Attachments")}
          >
            <AttendeeAttachments.links
              meeting_id={@meeting.id}
              attachments={@meeting.attendee_attachments}
            />
          </.sub_panel>

          <.sub_panel
            :if={@answered_fields != []}
            icon="hero-list-bullet"
            title={dgettext("dashboard_bookings", "Custom answers")}
          >
            <dl class="space-y-3">
              <div
                :for={field <- @answered_fields}
                class="grid grid-cols-1 md:grid-cols-[1fr_2fr] gap-x-6 gap-y-1"
              >
                <dt class="text-token-sm font-semibold text-neutral-500 dark:text-twilight-indigo-300">
                  {field["label"]}
                </dt>
                <dd class="text-token-sm text-neutral-700 font-medium dark:text-neutral-200">
                  {AnswerRenderer.render(field, @meeting.custom_field_answers[field["id"]])}
                </dd>
              </div>
            </dl>
          </.sub_panel>
        </div>

        <MeetingActions.action_bar
          meeting={@meeting}
          target={@target}
          answering_request={@answering_request}
          cancelling_meeting={@cancelling_meeting}
          deleting_meeting={@deleting_meeting}
          current_user_email={@current_user_email}
          attending?={@attending?}
        />
      </div>
    </Containers.card>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :rest, :global
  slot :aside, doc: "A short note at the far end of the header, such as a count"
  slot :inner_block, required: true

  @doc """
  A tinted panel inside a card, under a small icon and a title, for a
  secondary block of the card's content (guests, notes, attachments, answers). Close to the details above and to each other, so a booking with several of them stays short.
  """
  @spec sub_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def sub_panel(assigns) do
    ~H"""
    <section
      class="mt-4 p-5 bg-neutral-50/50 rounded-token-2xl border-2 border-neutral-300 dark:bg-twilight-indigo-900/40 dark:border-twilight-indigo-800"
      {@rest}
    >
      <div class="flex items-center justify-between gap-4 mb-4">
        <div class="flex items-center gap-4">
          <div class="w-8 h-8 rounded-token-lg bg-white shadow-sm flex items-center justify-center shrink-0 border border-neutral-300 dark:bg-twilight-indigo-950 dark:border-twilight-indigo-700">
            <Icons.icon name={@icon} class="w-4 h-4 text-neutral-400 dark:text-twilight-indigo-300" />
          </div>
          <h3 class="text-token-base font-semibold text-neutral-900 dark:text-neutral-50">
            {@title}
          </h3>
        </div>
        <span
          :if={@aside != []}
          class="text-token-sm font-bold text-neutral-500 dark:text-twilight-indigo-300"
        >
          {render_slot(@aside)}
        </span>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :person, :map, required: true

  defp initial(assigns) do
    ~H"""
    <span class="flex h-7 w-7 flex-none items-center justify-center rounded-token-full bg-primary-100 text-token-xs font-bold uppercase text-primary-700 dark:bg-primary-900 dark:text-primary-300">
      {person_initial(@person)}
    </span>
    """
  end

  attr :meeting, :map, required: true
  attr :profile, :any, default: nil
  attr :organizer?, :boolean, required: true
  attr :target, :any, required: true

  # "externally_deleted" has no dismiss button: the meeting was auto-cancelled
  # because of it, so the banner stays as the reason until the meeting itself
  # is deleted (by hand or by the organiser's cancelled-meeting cleanup).
  defp calendar_sync_banner(assigns) do
    assigns = assign(assigns, :auto_delete_date, banner_auto_delete_date(assigns))

    ~H"""
    <div class={[
      "flex items-start justify-between gap-4 rounded-token-2xl px-5 py-4 mb-6 border-2",
      if(@meeting.calendar_sync_status == "externally_deleted",
        do:
          "bg-red-50 border-red-200 text-red-800 dark:bg-red-950/40 dark:border-red-800 dark:text-red-200",
        else:
          "bg-amber-50 border-amber-200 text-amber-800 dark:bg-amber-950/40 dark:border-amber-800 dark:text-amber-200"
      )
    ]}>
      <p class="font-medium text-token-sm">
        <span :if={@meeting.calendar_sync_status == "externally_deleted"}>
          {if @organizer?,
            do:
              dgettext(
                "dashboard_bookings",
                "This meeting's event was deleted from your external calendar."
              ),
            else:
              dgettext(
                "dashboard_bookings",
                "The organiser removed this meeting's event from their calendar."
              )}
          <span :if={@auto_delete_date}>
            {dgettext(
              "dashboard_bookings",
              "It will be deleted automatically after %{date}.",
              date: @auto_delete_date
            )}
          </span>
        </span>
        <span :if={@meeting.calendar_sync_status == "externally_modified"}>
          {dgettext(
            "dashboard_bookings",
            "This meeting's event was rescheduled in your external calendar."
          )}
        </span>
        <span :if={@meeting.calendar_sync_status == "creation_failed"}>
          {dgettext(
            "dashboard_bookings",
            "This meeting's event could not be added to your external calendar."
          )}
        </span>
      </p>
      <Buttons.action_button
        :if={@meeting.calendar_sync_status != "externally_deleted"}
        variant={:outline}
        size={:sm}
        phx-click="dismiss_calendar_sync_banner"
        phx-value-id={@meeting.id}
        phx-target={@target}
        class="shrink-0"
      >
        {dgettext("dashboard_bookings", "Dismiss")}
      </Buttons.action_button>
    </div>
    """
  end

  # Only the organiser's own profile carries the cleanup setting that will
  # delete this meeting; an attendee's card has no date to show.
  defp banner_auto_delete_date(%{meeting: meeting, profile: profile, organizer?: true}) do
    if meeting.calendar_sync_status == "externally_deleted" do
      Helpers.format_auto_delete_date(
        meeting,
        profile,
        Helpers.get_meeting_timezone(meeting, profile)
      )
    end
  end

  defp banner_auto_delete_date(_assigns), do: nil

  # The host's details reach the attendee only as far as the host shared them
  # when the meeting was booked (`share_organizer_email`, `organizer_phone`).
  defp contact_email(%{share_organizer_email: true} = meeting, true = _attending?),
    do: meeting.organizer_email

  defp contact_email(_meeting, true = _attending?), do: nil
  defp contact_email(meeting, false = _attending?), do: meeting.attendee_email

  defp contact_phone(meeting, true = _attending?), do: meeting.organizer_phone
  defp contact_phone(meeting, false = _attending?), do: meeting.attendee_phone

  # The custom-field questions this booking actually answered.
  defp answered_fields(meeting) do
    Enum.filter(meeting.custom_fields_snapshot, fn field ->
      AnswerRenderer.render(field, meeting.custom_field_answers[field["id"]]) != ""
    end)
  end

  defp guest_list(%{guests: guests}) when is_list(guests), do: guests
  defp guest_list(_meeting), do: []

  # A cancelled group meeting holds no seats any more, so "0/3" would only
  # say that it is cancelled. What the host wants to know is who was still
  # booked when it was called off: the participants whose own seat was never
  # released (the host cancelled the slot, or its calendar event was deleted).
  # A slot cancelled because its last seat was released had nobody left.
  defp seats_label(%{status: "cancelled"} = meeting, _guests) do
    case Enum.count(Helpers.participants(meeting), &is_nil(&1.cancelled_at)) do
      0 ->
        dgettext("dashboard_bookings", "Every spot was released")

      booked ->
        dngettext(
          "dashboard_bookings",
          "%{count} person was booked",
          "%{count} people were booked",
          booked
        )
    end
  end

  # Seats, not headcount. A booker who brings a guest occupies two of the
  # slot's seats, which is what the public booking page counts down and what
  # the organiser needs to read here: a card saying "1/4" beside a slot
  # advertising "2 seats left" is two answers to the same question.
  defp seats_label(meeting, guests) do
    dgettext("dashboard_bookings", "%{count}/%{capacity} seats taken",
      count: Seats.seats_taken(Helpers.participants(meeting), guests),
      capacity: meeting.capacity
    )
  end

  # A solo card is titled after its attendee. A group card has no single
  # attendee, so it is named after what was booked: `title` is a required
  # field on every meeting, snapshotted at creation, so it survives the
  # meeting type being edited or deleted.
  defp meeting_title(meeting) do
    if Helpers.group_meeting?(meeting),
      do: group_title(meeting),
      else: solo_title(meeting)
  end

  defp solo_title(%{attendee_name: name}) when is_binary(name) and name != "", do: name
  defp solo_title(meeting), do: group_title(meeting)

  defp group_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp group_title(_meeting), do: dgettext("dashboard_bookings", "Group booking")

  defp person_initial(%{name: name}) when is_binary(name) and name != "",
    do: name |> String.first() |> String.upcase()

  defp person_initial(%{email: email}) when is_binary(email) and email != "",
    do: email |> String.first() |> String.upcase()

  defp person_initial(_person), do: "?"

  defp guest_summary_label(guests) do
    summary = Meetings.guest_rsvp_summary(guests)

    dgettext("dashboard_bookings", "%{going} of %{total} going",
      going: summary.accepted,
      total: summary.total
    )
  end
end
