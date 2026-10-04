defmodule Tymeslot.Bookings.Policy do
  @moduledoc """
  Business rules and policies for bookings.

  None of the functions here are pure. The attribute assembly performs
  database reads: `scheduling_config/2` resolves the organiser's profile and
  schedule; `build_meeting_attributes/1` additionally resolves the video
  integration and meeting type. The verdict predicates (`can_cancel_meeting?/1`
  and friends) delegate to `Tymeslot.Bookings.MeetingPermissions`: they read
  the system clock (`Tymeslot.Clock`), the blocked branches of the first two
  emit `Logger.info`, and none of them touch the database.
  """
  alias Tymeslot.Availability.Schedules
  alias Tymeslot.Bookings.BookingTitle
  alias Tymeslot.Bookings.BuildParams
  alias Tymeslot.Bookings.MeetingPermissions
  alias Tymeslot.Clock
  alias Tymeslot.Emails.RecipientLocale
  alias Tymeslot.I18n.Resolve
  alias Tymeslot.Integrations.Calendar.Events, as: CalendarEvents
  alias Tymeslot.Integrations.Video
  alias Tymeslot.Locales
  alias Tymeslot.Meetings.Approval
  alias Tymeslot.MeetingTypes
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Timezones
  alias Tymeslot.Utils.ReminderUtils
  alias Tymeslot.Utils.UrlBuilder

  @doc """
  Scheduling policy for a booking: buffer, minimum notice, advance window and
  the organiser's timezone.

  The policy comes from the schedule the meeting type is booked against, so
  server-side validation applies exactly the rules the offered slots were
  computed from. A nil meeting type resolves the organiser's default schedule.
  """
  @spec scheduling_config(integer() | nil, map() | nil) :: %{
          required(:schedule_id) => integer() | nil,
          required(:buffer_minutes) => integer(),
          required(:min_advance_hours) => integer(),
          required(:max_advance_booking_days) => integer(),
          required(:owner_timezone) => String.t(),
          required(:slot_interval_minutes) => pos_integer() | nil
        }
  def scheduling_config(nil, _meeting_type) do
    nil
    |> Schedules.config(nil)
    |> Map.put(:owner_timezone, Profiles.get_default_timezone())
  end

  def scheduling_config(organizer_user_id, meeting_type) do
    # `Profiles.get_profile_settings/1` already resolves a profile with no
    # timezone to `Profiles.get_default_timezone()`, the same fallback the
    # booking page applies, so a nil profile timezone resolves to one zone on
    # both sides.
    settings = Profiles.get_profile_settings(organizer_user_id)

    organizer_user_id
    |> resolve_schedule(meeting_type)
    |> Schedules.config(meeting_type)
    |> Map.put(:owner_timezone, settings.timezone)
  end

  defp resolve_schedule(_organizer_user_id, %{} = meeting_type) do
    Schedules.resolve_for_meeting_type(meeting_type)
  end

  defp resolve_schedule(organizer_user_id, _meeting_type) do
    case ProfileQueries.get_by_user_id(organizer_user_id) do
      {:ok, profile} -> Schedules.get_default(profile.id)
      {:error, :not_found} -> nil
    end
  end

  @typedoc "A single reminder entry with a numeric value and a unit string (e.g. \"minutes\")."
  @type reminder :: %{required(:value) => integer(), required(:unit) => String.t()}

  @typedoc "Complete set of meeting attributes built for persistence or email."
  @type meeting_attributes :: %{
          required(:uid) => String.t(),
          required(:title) => String.t(),
          required(:summary) => String.t(),
          required(:description) => String.t(),
          required(:start_time) => DateTime.t(),
          required(:end_time) => DateTime.t(),
          required(:duration) => integer(),
          required(:location) => String.t() | nil,
          required(:location_kind) => String.t() | nil,
          required(:location_option_id) => String.t() | nil,
          required(:meeting_type) => String.t(),
          required(:meeting_type_id) => integer() | nil,
          required(:organizer_name) => String.t(),
          required(:organizer_email) => String.t(),
          required(:organizer_title) => String.t() | nil,
          required(:organizer_user_id) => integer() | nil,
          required(:calendar_integration_id) => integer() | nil,
          required(:calendar_path) => String.t() | nil,
          required(:video_integration_id) => integer() | nil,
          required(:venue_id) => integer() | nil,
          required(:address_to_arrange) => boolean(),
          required(:attendee_name) => String.t(),
          required(:attendee_email) => String.t(),
          required(:attendee_message) => String.t() | nil,
          required(:attendee_phone) => String.t() | nil,
          required(:attendee_company) => String.t() | nil,
          required(:attendee_timezone) => String.t(),
          required(:attendee_locale) => String.t(),
          required(:status) => String.t(),
          required(:approval_requested_at) => DateTime.t() | nil,
          required(:approval_deadline_at) => DateTime.t() | nil,
          required(:reminders) => [reminder()],
          required(:show_as_free) => boolean(),
          required(:share_organizer_email) => boolean(),
          required(:organizer_phone) => String.t() | nil,
          required(:attachments_snapshot) => [map()],
          required(:attendee_attachments) => [map()],
          required(:view_url) => String.t(),
          required(:reschedule_url) => String.t(),
          required(:cancel_url) => String.t(),
          required(:meeting_url) => String.t() | nil,
          required(:custom_fields_snapshot) => [map()],
          required(:custom_field_answers) => map(),
          required(:utm_source) => String.t() | nil,
          required(:utm_medium) => String.t() | nil,
          required(:utm_campaign) => String.t() | nil,
          required(:utm_content) => String.t() | nil,
          required(:utm_term) => String.t() | nil,
          required(:referrer_host) => String.t() | nil,
          required(:tracking_params) => map(),
          required(:visitor_hash) => String.t() | nil,
          required(:booker_user_id) => integer() | nil
        }

  @typedoc "A meeting record with the fields required by the policy checks."
  @type meeting_record :: MeetingPermissions.meeting_record()

  @doc """
  Builds meeting attributes from parameters and form data.

  Resolves the organiser's profile, schedule and integrations along the way, so
  this reads from the database rather than being a pure transformation.
  """
  @spec build_meeting_attributes(BuildParams.t()) :: meeting_attributes()
  def build_meeting_attributes(%BuildParams{} = params) do
    organizer_user_id = params.organizer_user_id

    # Resolve meeting type if ID provided
    meeting_type_record =
      resolve_meeting_type_record(params.meeting_type_id, organizer_user_id)

    # Get organizer details from profile if available
    {org_name, org_email, org_username, org_phone} = get_organizer_details(organizer_user_id)

    # Resolve attendee timezone
    config = scheduling_config(organizer_user_id, meeting_type_record)
    user_timezone = params.user_timezone || config.owner_timezone

    # Get calendar integration info
    {calendar_integration_id, calendar_path} =
      get_calendar_integration_info(meeting_type_record || organizer_user_id)

    # Resolved once, here, and written back onto `params` so the snapshotted
    # name/description below and the stamped `attendee_locale` column agree.
    attendee_locale = params.attendee_locale || default_locale()
    params = %{params | attendee_locale: attendee_locale}

    # Resolve meeting type details
    {meeting_type_name, resolved_meeting_type_id, video_integration_id} =
      resolve_meeting_type_details(meeting_type_record, params, organizer_user_id)

    resolved = %{
      meeting_type_record: meeting_type_record,
      meeting_type_name: meeting_type_name,
      resolved_meeting_type_id: resolved_meeting_type_id,
      org_name: org_name,
      org_email: org_email,
      org_phone: org_phone,
      org_username: org_username,
      calendar_integration_id: calendar_integration_id,
      calendar_path: calendar_path,
      video_integration_id: video_integration_id,
      user_timezone: user_timezone,
      # Get reminder configuration
      reminders: get_meeting_reminders(meeting_type_record)
    }

    build_attributes_map(params, resolved)
  end

  # Builds the complete meeting attributes map from the raw params plus
  # everything `build_meeting_attributes/1` already resolved — split out on
  # its own since the map literal's per-field defaulting/formatting is what
  # actually drives this transformation's complexity, not the resolution
  # steps above.
  defp build_attributes_map(params, resolved) do
    meeting_uid = params.meeting_uid

    # A meeting type requiring manual approval holds its bookings instead of
    # confirming them. The deadline is stamped here, at request time, rather
    # than derived later: the meeting type's window can be edited — or the type
    # archived — while a request is outstanding, and the deadline promised to
    # the invitee must not move underneath them.
    %{status: status, approval_requested_at: requested_at, approval_deadline_at: deadline_at} =
      approval_attributes(resolved.meeting_type_record, params.start_datetime)

    %{
      uid: meeting_uid,
      description:
        (resolved.meeting_type_record &&
           Resolve.text(
             resolved.meeting_type_record.translations,
             params.attendee_locale,
             :description,
             resolved.meeting_type_record.description
           )) || "",
      start_time: params.start_datetime,
      end_time: params.end_datetime,
      duration: params.duration_minutes,
      meeting_type: resolved.meeting_type_name,
      meeting_type_id: resolved.resolved_meeting_type_id,
      organizer_name: resolved.org_name,
      organizer_email: resolved.org_email,
      organizer_title: nil,
      organizer_user_id: params.organizer_user_id,
      calendar_integration_id: resolved.calendar_integration_id,
      calendar_path: resolved.calendar_path,
      status: status,
      approval_requested_at: requested_at,
      approval_deadline_at: deadline_at,
      reminders: resolved.reminders,
      show_as_free:
        (resolved.meeting_type_record && resolved.meeting_type_record.show_as_free) || false,
      share_organizer_email: shares?(resolved.meeting_type_record, :show_email_to_bookers),
      organizer_phone:
        if(shares?(resolved.meeting_type_record, :show_phone_to_bookers),
          do: resolved.org_phone
        ),
      attachments_snapshot: attachments_snapshot(resolved.meeting_type_record),
      attendee_attachments:
        attendee_attachments(resolved.meeting_type_record, params.attendee_attachments),
      custom_fields_snapshot: params.custom_fields_snapshot,
      custom_field_answers: params.custom_field_answers,
      booker_user_id: booker_user_id(params)
    }
    |> Map.merge(title_attributes(params, resolved.meeting_type_name))
    |> Map.merge(attendee_attributes(params, resolved.user_timezone))
    |> Map.merge(
      location_attributes(resolved.meeting_type_record, params, resolved.video_integration_id)
    )
    |> Map.merge(source_attribution(params))
    |> Map.merge(build_meeting_action_urls(meeting_uid, resolved.org_username))
  end

  # The host's contact details reach the booker only as the meeting type
  # allows, decided once at booking time.
  defp shares?(nil, _setting), do: false
  defp shares?(meeting_type, setting), do: Map.get(meeting_type, setting) == true

  # An organiser booking on their own page already has the meeting in their
  # calendar; a copy would only duplicate it.
  defp booker_user_id(%BuildParams{booker_user_id: id, organizer_user_id: id}), do: nil
  defp booker_user_id(%BuildParams{booker_user_id: id}), do: id

  # The title is stored once and becomes the organiser's calendar event and
  # dashboard entry, so it is rendered in the organiser's language, matching
  # the event description `CalendarEventBuilder` writes alongside it. Mail to
  # the booker renders it again in theirs (`BookingTitle.localise/1`).
  defp title_attributes(%BuildParams{} = params, meeting_type_name) do
    title =
      RecipientLocale.with_user_id_locale(params.organizer_user_id, fn ->
        BookingTitle.render(meeting_type_name, params.form_data["name"])
      end)

    %{title: title, summary: title}
  end

  # Who the booking is for, as they gave it. `attendee_phone` is absent here:
  # `location_attributes/3` sets it, from the chosen location when that asked
  # the booker for a number, otherwise from the booking form's own field.
  defp attendee_attributes(%BuildParams{form_data: form_data} = params, user_timezone) do
    %{
      attendee_name: form_data["name"],
      attendee_email: form_data["email"],
      attendee_message: form_data["message"],
      attendee_company: form_data["company"],
      attendee_timezone: Timezones.normalize(user_timezone),
      attendee_locale: params.attendee_locale
    }
  end

  # Where the meeting is held, and everything that follows from it: the
  # display string, the kind, the video integration a room would be created
  # on, and the saved venue an in-person booking is at.
  #
  # The booker submitted only an option id, and within a video option the
  # provider they picked, or within an in-person option the venue. The rest
  # is re-derived here from the host's own meeting type, so a forged or stale
  # id can only ever select a location, a provider or a venue the host
  # already offers.
  defp location_attributes(meeting_type_record, %BuildParams{} = params, fallback_video_id) do
    location =
      MeetingTypes.resolve_location(meeting_type_record, %{
        option_id: params.location_option_id,
        phone: params.location_phone,
        video_integration_id: params.location_video_integration_id,
        venue_id: params.location_venue_id
      })

    %{
      location: location.location,
      location_kind: location.location_kind,
      location_option_id: location.location_option_id,
      attendee_phone: location.attendee_phone || params.form_data["phone"],
      video_integration_id: video_integration_for(location, fallback_video_id),
      venue_id: location.venue_id,
      address_to_arrange: location.address_to_arrange
    }
  end

  # Where the booking came from: the UTM parameters and referrer captured on
  # the booking page, plus the cookieless key joining this meeting to that
  # page view in analytics. Grouped so the attributes map states the booking
  # itself rather than burying it under eight tracking keys.
  defp source_attribution(%BuildParams{} = params) do
    %{
      utm_source: params.utm_source,
      utm_medium: params.utm_medium,
      utm_campaign: params.utm_campaign,
      utm_content: params.utm_content,
      utm_term: params.utm_term,
      referrer_host: params.referrer_host,
      tracking_params: params.tracking_params,
      visitor_hash: params.visitor_hash
    }
  end

  # A booking on a meeting type requiring manual approval is held rather than
  # confirmed, and carries the clock the host is answering against. Everything
  # else confirms on submission exactly as before, with all three keys nil.
  defp approval_attributes(meeting_type_record, start_datetime) do
    if Approval.required?(meeting_type_record) and not is_nil(start_datetime) do
      requested_at = DateTime.truncate(Clock.utc_now(), :second)

      %{
        status: "awaiting_approval",
        approval_requested_at: requested_at,
        approval_deadline_at:
          Approval.deadline_for(meeting_type_record, requested_at, start_datetime)
      }
    else
      %{status: "confirmed", approval_requested_at: nil, approval_deadline_at: nil}
    end
  end

  # Snapshots host-uploaded meeting-type attachments as plain maps so the
  # calendar event and confirmation email reference a stable file set.
  defp attachments_snapshot(%{attachments: attachments}) do
    Enum.map(attachments, fn a ->
      %{
        "id" => a.id,
        "filename" => a.filename,
        "stored_path" => a.stored_path,
        "content_type" => a.content_type,
        "byte_size" => a.byte_size
      }
    end)
  end

  defp attachments_snapshot(_meeting_type), do: []

  # The booker's own files, kept only when the meeting type offers the field,
  # the same server-side gate guests get in `Tymeslot.Bookings.Create`.
  defp attendee_attachments(%{allow_attachments: true}, attachments), do: attachments
  defp attendee_attachments(_meeting_type, _attachments), do: []

  # Resolves the meeting type record if available and active
  defp resolve_meeting_type_record(meeting_type_id, organizer_user_id) do
    if meeting_type_id && organizer_user_id do
      case MeetingTypes.get_meeting_type(meeting_type_id, organizer_user_id) do
        %{is_active: true} = type -> type
        _other -> nil
      end
    else
      nil
    end
  end

  # Resolves meeting type name, ID, and video integration
  defp resolve_meeting_type_details(meeting_type_record, params, organizer_user_id) do
    case meeting_type_record do
      nil ->
        {"General Meeting", nil, resolve_video_integration_id(params, organizer_user_id)}

      type ->
        resolved_video_id =
          resolve_video_integration_id(params, organizer_user_id) || type.video_integration_id

        name = Resolve.text(type.translations, params.attendee_locale, :name, type.name)

        {name, type.id, resolved_video_id}
    end
  end

  # Gets reminder configuration from meeting type or returns defaults
  defp get_meeting_reminders(meeting_type_record) do
    case meeting_type_record do
      %{reminder_config: reminder_config} when is_list(reminder_config) ->
        ReminderUtils.normalize_reminders(reminder_config)

      _other ->
        [%{value: 30, unit: "minutes"}]
    end
  end

  # Builds URLs for meeting actions (view, reschedule, cancel)
  defp build_meeting_action_urls(meeting_uid, org_username) do
    %{
      view_url: build_meeting_url(meeting_uid, "", org_username),
      reschedule_url: build_meeting_url(meeting_uid, "/reschedule", org_username),
      cancel_url: build_meeting_url(meeting_uid, "/cancel", org_username),
      meeting_url: nil
    }
  end

  @doc """
  Gets the organizer name from configuration.
  """
  @spec organizer_name() :: String.t()
  def organizer_name do
    Application.get_env(:tymeslot, :email)[:from_name]
  end

  @doc """
  Gets the organizer email from configuration.
  """
  @spec organizer_email() :: String.t()
  def organizer_email do
    Application.get_env(:tymeslot, :email)[:from_email]
  end

  @doc """
  Determines if a meeting can be cancelled (status and time constraints).
  """
  @spec can_cancel_meeting?(meeting_record()) :: :ok | {:error, String.t()}
  defdelegate can_cancel_meeting?(meeting), to: MeetingPermissions

  @doc """
  Determines if a meeting can be rescheduled (status and time constraints).
  """
  @spec can_reschedule_meeting?(meeting_record()) :: :ok | {:error, String.t()}
  defdelegate can_reschedule_meeting?(meeting), to: MeetingPermissions

  @doc """
  Determines if the organiser may ask the attendee to pick a new time. See
  `Tymeslot.Bookings.MeetingPermissions.can_request_reschedule?/1`.
  """
  @spec can_request_reschedule?(meeting_record()) :: :ok | {:error, String.t()}
  defdelegate can_request_reschedule?(meeting), to: MeetingPermissions

  @doc """
  Determines if a meeting can be manually (hard) deleted: only cancelled ones.
  """
  @spec can_delete_meeting?(meeting_record()) :: :ok | {:error, String.t()}
  defdelegate can_delete_meeting?(meeting), to: MeetingPermissions

  @doc """
  Checks if a meeting is currently happening.
  """
  @spec meeting_is_current?(%{
          required(:start_time) => DateTime.t(),
          required(:end_time) => DateTime.t(),
          optional(atom()) => term()
        }) :: boolean()
  defdelegate meeting_is_current?(meeting), to: MeetingPermissions

  @doc """
  Checks if a meeting is in the past.
  """
  @spec meeting_is_past?(%{required(:end_time) => DateTime.t(), optional(atom()) => term()}) ::
          boolean()
  defdelegate meeting_is_past?(meeting), to: MeetingPermissions

  # Private functions

  defp build_meeting_url(meeting_uid, path, username) do
    if username do
      app_url() <> "/#{username}/meeting/#{meeting_uid}#{path}"
    else
      # Fallback to old URL structure if no username available
      app_url() <> "/meeting/#{meeting_uid}#{path}"
    end
  end

  # Private helper to get organizer details from profile or fallback to config
  defp get_organizer_details(nil), do: {organizer_name(), organizer_email(), nil, nil}

  defp get_organizer_details(user_id) do
    case ProfileQueries.get_by_user_id(user_id) do
      {:error, :not_found} ->
        {organizer_name(), organizer_email(), nil, nil}

      {:ok, profile} ->
        profile = ProfileQueries.preload_user(profile)
        name = profile.full_name || profile.user.name || organizer_name()
        email = profile.user.email || organizer_email()
        username = profile.username
        {name, email, username, profile.phone}
    end
  end

  # Private helper to get calendar integration info for tracking
  defp get_calendar_integration_info(nil), do: {nil, nil}

  defp get_calendar_integration_info(context) do
    case CalendarEvents.get_booking_integration_info(context) do
      {:ok, %{integration_id: integration_id, calendar_path: calendar_path}} ->
        {integration_id, calendar_path}

      _other ->
        {nil, nil}
    end
  end

  # Once a location has been chosen, it is the only thing that decides
  # whether a room is created and where: an in-person or phone location
  # resolves to no integration, and must *not* inherit the meeting type's,
  # which would open a video room for a meeting nobody is attending online.
  # The meeting-type-level id survives only for ad-hoc bookings, which have
  # no location list to choose from.
  defp video_integration_for(%{location_option_id: nil}, fallback_id), do: fallback_id
  defp video_integration_for(%{video_integration_id: id}, _fallback_id), do: id

  defp resolve_video_integration_id(params, organizer_user_id) do
    video_integration_id =
      case params.video_integration_id do
        id when is_integer(id) ->
          id

        id when is_binary(id) ->
          case Integer.parse(id) do
            {int, ""} -> int
            _other -> nil
          end

        _other ->
          nil
      end

    if is_nil(video_integration_id) or is_nil(organizer_user_id) do
      nil
    else
      case Video.fetch_integration_for_user(video_integration_id, organizer_user_id) do
        {:ok, %{is_active: true}} -> video_integration_id
        _other -> nil
      end
    end
  end

  @doc """
  Gets the application base URL based on configuration.
  """
  @spec app_url() :: String.t()
  defdelegate app_url, to: UrlBuilder, as: :base_url

  @doc """
  Builds the public accept/decline RSVP URLs for a guest's token.
  """
  @spec guest_rsvp_urls(String.t()) :: %{accept_url: String.t(), decline_url: String.t()}
  def guest_rsvp_urls(token) when is_binary(token) do
    %{
      accept_url: app_url() <> "/guest/#{token}/accept",
      decline_url: app_url() <> "/guest/#{token}/decline"
    }
  end

  @doc """
  Where a host answers a booking request from their email.

  Both actions point at the same review page. The `intent` parameter only
  preselects a choice for the host to confirm — it never acts on its own,
  because mail security scanners and link preview crawlers fetch every URL in
  an inbound message and would otherwise answer the request for them.
  """
  @spec approval_urls(String.t()) :: %{
          review_url: String.t(),
          approve_url: String.t(),
          decline_url: String.t()
        }
  def approval_urls(token) when is_binary(token) do
    review_url = app_url() <> "/meeting-request/#{token}"

    %{
      review_url: review_url,
      approve_url: review_url <> "?intent=approve",
      decline_url: review_url <> "?intent=decline"
    }
  end

  defp default_locale, do: Locales.booking_default_locale()
end
