defmodule TymeslotWeb.Public.CalendarLive do
  @moduledoc """
  Public, read-only month view of an organiser's calendar at `/:username/calendar`.
  The organiser can switch it off on the Calendars settings page
  (`Profiles.public_calendar_enabled?/1`); the page then only says so.

  Unauthenticated — access is scoped to what `Tymeslot.FreeBusy` already
  treats as safe to publish: busy/free blocks derived from connected-calendar
  events, never event titles, descriptions, or attendees. Busy blocks render
  as a generic "Busy" chip rather than the real summary shown to the
  signed-in owner on `/dashboard/calendar` (`CalendarGridComponent`).

  A meeting awaiting the organiser's approval is shown as its own chip,
  sourced from the meetings table (`Tymeslot.Meetings.pending_approval_time_ranges/3`)
  rather than from `FreeBusy`: the tentative hold the booking writes to the
  host's calendar only shows up once sync brings it back, and would read as
  plain "Busy" when it does. `assign_month/1` merges the pending chips in and
  leaves that hold out of `FreeBusy`'s intervals, so the slot appears once,
  styled like the "awaiting approval" red treatment on the dashboard grid
  (`EventPositioning.pending_approval?/1`) — same privacy boundary as
  everything else here: only the time range, never a title or attendee.

  Visually mirrors the booking flow (`TymeslotWeb.Themes.Quill.Scheduling.*`)
  rather than the dashboard: rendered through the `:theme_browser`
  pipeline/`scheduling_root` layout, same as the scheduling routes. The
  template only uses the Quill theme's classes, so `mount/3` pins `theme_id` to
  Quill (overriding what `ThemeHook` resolved from `profile.booking_theme`): a
  Rhythm organiser gets Quill's look here until this page grows per-theme
  variants like the scheduling dispatcher has.

  Days are dimmed and unclickable outside the organiser's actual booking
  window (the profile's default schedule's `min_advance_hours` ..
  `advance_booking_days` policy, resolved via `Tymeslot.Availability.Schedules`,
  the same values the dashboard's Availability settings write to). Clicking a
  bookable day navigates to `/:username?date=...` — the meeting-type picker —
  so the visitor chooses a duration before landing on the real scheduling
  page; the date carries through automatically (`selected_date` stays
  assigned across the scheduling LiveView's internal state transitions, see
  `TymeslotWeb.Themes.Shared.LiveHelpers.maybe_assign_from_params/3`).
  """
  use TymeslotWeb, :live_view
  use Gettext, backend: TymeslotWeb.Gettext

  import TymeslotWeb.Components.PublicTopBar
  import TymeslotWeb.Components.PublicFooter

  alias Tymeslot.Availability.Calculate
  alias Tymeslot.Availability.Schedules
  alias Tymeslot.CalendarGrid
  alias Tymeslot.FreeBusy
  alias Tymeslot.Locales
  alias Tymeslot.Meetings
  alias Tymeslot.Profiles
  alias Tymeslot.Utils.DateTimeUtils.TimeFormat
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers.PreferenceHelpers
  alias TymeslotWeb.Helpers.LocaleFormat
  alias TymeslotWeb.Themes.Shared.Customization.Helpers, as: CustomizationHelpers

  @max_chips 4

  defp max_chips, do: @max_chips

  @impl Phoenix.LiveView
  def mount(%{"username" => username}, _session, socket) do
    # The template is Quill markup whatever the organiser's booking theme, so
    # the layout loads Quill's stylesheet: with Rhythm's (the one ThemeHook
    # resolves for a Rhythm organiser) none of its classes match and the page
    # falls apart.
    socket = assign(socket, :theme_id, "1")

    case Profiles.resolve_organizer_context(username) do
      {:ok, context} ->
        if Profiles.public_calendar_enabled?(context.profile) do
          mount_calendar(socket, context)
        else
          {:ok,
           socket
           |> assign(:not_found, true)
           |> assign(:not_found_message, dgettext("booking", "This calendar is not public."))}
        end

      {:error, :profile_not_found} ->
        {:ok,
         socket
         |> assign(:not_found, true)
         |> assign(:not_found_message, dgettext("booking", "No such organiser."))}
    end
  end

  defp mount_calendar(socket, context) do
    {:ok,
     socket
     |> assign(:username, context.username)
     |> assign(:profile, context.profile)
     |> assign(:page_title, "#{context.username} — Calendar")
     |> assign(:not_found, false)
     |> assign(:dropdown_open, false)
     |> assign(:locales, Locales.supported())
     |> CustomizationHelpers.assign_theme_customization(context.profile, "1")}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_language_dropdown", _params, socket) do
    {:noreply, assign(socket, :dropdown_open, !socket.assigns.dropdown_open)}
  end

  def handle_event("close_language_dropdown", _params, socket) do
    {:noreply, assign(socket, :dropdown_open, false)}
  end

  def handle_event("change_locale", %{"locale" => locale}, socket) do
    if Locales.acceptable?(locale) do
      # A plain assign update leaves `gettext(...)` calls stale: LiveView's
      # diff only re-evaluates a template expression when an @assign it
      # references changes, and gettext/1 takes no assigns — so it renders
      # once and never again. A full remount re-evaluates everything from
      # scratch against the new locale — but it must be a real HTTP redirect,
      # not `push_navigate`: that's a WebSocket-only client navigation that
      # never runs through `TymeslotWeb.Plugs.LocalePlug`, the only place
      # that persists the choice to `session["locale"]`. Without that, the
      # locale silently reverts to the old one on the next page load. Same
      # fix/reasoning as the real booking pages' `EventHandlers.handle_change_locale/3`.
      query = %{"locale" => locale, "month" => month_param(socket.assigns.month)}

      {:noreply, redirect(socket, external: ~p"/#{socket.assigns.username}/calendar?#{query}")}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    if socket.assigns.not_found do
      {:noreply, socket}
    else
      {:noreply, assign_month(socket, parse_month(params["month"]))}
    end
  end

  @impl Phoenix.LiveView
  def render(%{not_found: true} = assigns) do
    ~H"""
    <div class="quill-theme-wrapper theme-1">
      <div class="main-gradient theme-grid">
        <div class="content-area">
          <div class="public-calendar-container">
            <p class="text-glass-primary public-calendar-not-found">
              {@not_found_message}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="quill-theme-wrapper theme-1" data-locale={@locale}>
      <CustomizationHelpers.render_custom_theme_styles custom_css={@custom_css} />
      <div
        class="main-gradient theme-grid"
        style={CustomizationHelpers.get_background_style(@theme_customization)}
      >
        <div class="content-area">
          <.public_top_bar
            locale={@locale}
            locales={@locales}
            dropdown_open={@dropdown_open}
            theme="quill"
            current_user={@current_user}
            username={@username}
          />

          <div class="public-calendar-container">
            <.glass_morphism_card class="public-calendar-card">
              <div class="public-calendar-body">
                <div class="calendar-month-header public-calendar-month-header">
                  <div class="calendar-nav-cluster">
                    <%= if prev_month_allowed?(@month, @bookable_range) do %>
                      <.link
                        patch={~p"/#{@username}/calendar?month=#{prev_month_param(@month)}"}
                        class="calendar-nav-button rounded-lg"
                        aria-label={dgettext("booking", "Previous month")}
                      >
                        ←
                      </.link>
                    <% else %>
                      <span
                        class="calendar-nav-button rounded-lg public-calendar-nav-disabled"
                        aria-hidden="true"
                      >←</span>
                    <% end %>

                    <%= if next_month_allowed?(@month, @bookable_range) do %>
                      <.link
                        patch={~p"/#{@username}/calendar?month=#{next_month_param(@month)}"}
                        class="calendar-nav-button rounded-lg"
                        aria-label={dgettext("booking", "Next month")}
                      >
                        →
                      </.link>
                    <% else %>
                      <span
                        class="calendar-nav-button rounded-lg public-calendar-nav-disabled"
                        aria-hidden="true"
                      >→</span>
                    <% end %>

                    <.link
                      patch={~p"/#{@username}/calendar"}
                      class="action-button action-button--secondary public-calendar-today-button"
                    >
                      {dgettext("booking", "Today")}
                    </.link>

                    <details class="public-calendar-month-picker">
                      <summary class="public-calendar-month-picker-trigger">
                        <span class="public-calendar-month-picker-label">{month_label(@month, @locale)}</span>
                        <.icon name="hero-chevron-down" class="w-3.5 h-3.5 shrink-0" />
                      </summary>
                      <div class="public-calendar-month-picker-panel">
                        <.link
                          :for={month <- bookable_months(@bookable_range)}
                          patch={~p"/#{@username}/calendar?month=#{month_param(month)}"}
                          class={[
                            "public-calendar-month-picker-item",
                            Date.compare(month, @month) == :eq && "active"
                          ]}
                        >
                          {month_label(month, @locale)}
                        </.link>
                      </div>
                    </details>
                  </div>

                  <h1 class="calendar-month-title public-calendar-title">
                    {dgettext("booking", "%{username}'s calendar", username: @username)}
                  </h1>
                </div>

                <div class={[
                  "public-calendar-grid",
                  !@show_weekends && "public-calendar-grid--weekdays"
                ]}>
                  <div class="public-calendar-weekdays">
                    <div
                      :for={day_name <- @day_names}
                      class="calendar-weekday public-calendar-weekday"
                    >
                      {day_name}
                    </div>
                  </div>

                  <div class="public-calendar-days">
                    <div
                      :for={day <- @days}
                      class={[
                        "public-calendar-day",
                        public_calendar_day_class(day, @month, @today, @bookable_range)
                      ]}
                    >
                      <%= if bookable?(day, @bookable_range) do %>
                        <.link
                          navigate={day_url(@username, day)}
                          class="public-calendar-day-link"
                          aria-label={dgettext("booking", "Book %{date}", date: Date.to_iso8601(day))}
                        ></.link>
                      <% end %>

                      <div class="public-calendar-day-number">{day.day}</div>

                      <% chips = chips_for(@busy_intervals, day, @timezone) %>
                      <% visible_chips = Enum.take(chips, max_chips()) %>
                      <% hidden_chips = Enum.drop(chips, max_chips()) %>
                      <div class="public-calendar-day-chips">
                        <div
                          :for={interval <- visible_chips}
                          class={[
                            "public-calendar-chip",
                            chip_color_class(elem(interval, 2), @integration_colors)
                          ]}
                        >
                          <span class="public-calendar-chip-text">
                            {chip_label(interval, day, @timezone, @time_format)}
                          </span>
                        </div>
                        <div
                          :if={hidden_chips != []}
                          class="public-calendar-chip-more"
                          title={overflow_title(hidden_chips, day, @timezone, @time_format)}
                        >
                          {dgettext("booking", "+%{count} more", count: length(hidden_chips))}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <p class="public-calendar-legend">
                  <span class="public-calendar-legend-dots">
                    <span
                      class="public-calendar-legend-dot"
                      style="background-color: var(--color-calendar-1)"
                    ></span>
                    <span
                      class="public-calendar-legend-dot"
                      style="background-color: var(--color-calendar-2)"
                    ></span>
                    <span
                      class="public-calendar-legend-dot"
                      style="background-color: var(--color-calendar-5)"
                    ></span>
                    <span
                      class="public-calendar-legend-dot"
                      style="background-color: var(--color-calendar-6)"
                    ></span>
                    <span
                      class="public-calendar-legend-dot"
                      style="background-color: var(--color-calendar-8)"
                    ></span>
                  </span>
                  {dgettext("booking", "Busy")}
                  <span :if={@has_pending_approvals} class="public-calendar-legend-pending">
                    <span class="public-calendar-legend-dot public-calendar-legend-dot--pending"></span>
                    {dgettext("booking", "Pending approval")}
                  </span>
                  <span :if={@has_non_blocking} class="public-calendar-legend-non-blocking">
                    <span class="public-calendar-legend-dot public-calendar-legend-dot--non-blocking"></span>
                    {dgettext("booking", "Not blocking bookings")}
                  </span>
                  <span class="public-calendar-legend-hint">{dgettext(
                    "booking",
                    "Click a day to see available times and book."
                  )}</span>
                </p>
              </div>
            </.glass_morphism_card>
          </div>
        </div>

        <.public_footer />
      </div>
    </div>
    """
  end

  defp assign_month(socket, month) do
    profile = socket.assigns.profile
    tz = profile.timezone || "Etc/UTC"
    days = PreferenceHelpers.month_matrix(month, :monday)

    today = DateTime.utc_now() |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    schedule = Schedules.resolve_for(nil, profile)
    range = bookable_range(schedule, tz, today)
    show_weekends = show_weekends?(profile, days, range, schedule)

    busy_intervals =
      filter_historical(
        month_intervals(profile, days, tz),
        today,
        tz,
        profile.public_calendar_show_historical_events
      )

    socket
    |> assign(:month, month)
    |> assign(:show_weekends, show_weekends)
    |> assign(:days, if(show_weekends, do: days, else: Enum.reject(days, &weekend?/1)))
    |> assign(
      :day_names,
      socket.assigns.locale
      |> monday_first_weekday_names()
      |> Enum.take(if show_weekends, do: 7, else: 5)
    )
    |> assign(:timezone, tz)
    |> assign(:today, today)
    |> assign(:busy_intervals, busy_intervals)
    |> assign(:has_pending_approvals, Enum.any?(busy_intervals, &pending_approval_interval?/1))
    |> assign(:has_non_blocking, Enum.any?(busy_intervals, &non_blocking_interval?/1))
    |> assign(:bookable_range, range)
    |> assign(:show_colors, profile.public_calendar_colors)
    |> assign(:integration_colors, integration_colors(profile))
    |> assign(
      :time_format,
      CalendarGrid.get_user_time_format(profile.user_id, socket.assigns.locale)
    )
  end

  # Every chip interval of the month grid: FreeBusy's busy and non-blocking
  # blocks plus the pending-approval chips, which stand in for those bookings'
  # tentative holds — so FreeBusy leaves the holds out.
  defp month_intervals(profile, days, tz) do
    window_start = to_utc(List.first(days), ~T[00:00:00], tz)
    window_end = DateTime.add(to_utc(List.last(days), ~T[00:00:00], tz), 1, :day)

    pending_approvals = pending_approvals(profile, List.first(days), List.last(days))
    free_busy_opts = [exclude_linked_to: pending_approvals]

    pending_approval_intervals =
      pending_approvals
      |> Enum.map(&{&1.start_time, &1.end_time, :pending_approval})
      |> FreeBusy.clip_to_public_visibility(profile)

    FreeBusy.busy_intervals_with_source(profile, window_start, window_end, free_busy_opts) ++
      FreeBusy.non_blocking_intervals(profile, window_start, window_end, free_busy_opts) ++
      pending_approval_intervals
  end

  # Meetings awaiting the organiser's approval, from the meetings table: their
  # tentative calendar hold may not have synced yet, and once it has it would
  # only read as "Busy". Turned into intervals tagged `:pending_approval`
  # instead of a real `calendar_integration_id` so `chip_color_class/2` and
  # the template can style/label them distinctly — only the time range ever
  # leaves this module, same as every other chip.
  #
  # Bounds are whole UTC calendar days padding the requested range, rather
  # than exact instants, so a meeting is never missed at a timezone/DST edge.
  defp pending_approvals(profile, start_date, end_date) do
    range_start = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    range_end = DateTime.new!(Date.add(end_date, 1), ~T[00:00:00], "Etc/UTC")

    Meetings.pending_approval_time_ranges(profile.user_id, range_start, range_end)
  end

  defp pending_approval_interval?({_start_time, _end_time, :pending_approval}), do: true
  defp pending_approval_interval?(_interval), do: false

  defp non_blocking_interval?({_start_time, _end_time, :non_blocking}), do: true
  defp non_blocking_interval?(_interval), do: false

  # `ProfileSchema.public_calendar_show_historical_events` — off by default.
  # A visitor can still reach a past month (direct `?month=` link; the
  # prev-month nav button is usually already disabled by `bookable_range/3`,
  # but that's a separate, booking-window concern, not a guarantee about
  # what's rendered), so this drops anything that never reaches today rather
  # than relying on navigation alone to hide it.
  defp filter_historical(intervals, _today, _timezone, true), do: intervals

  defp filter_historical(intervals, today, timezone, _show_historical) do
    today_start = to_utc(today, ~T[00:00:00], timezone)

    Enum.filter(intervals, fn interval ->
      DateTime.compare(elem(interval, 1), today_start) == :gt
    end)
  end

  defp chip_label(interval, day, timezone, time_format) do
    time = format_interval(interval, day, timezone, time_format)

    cond do
      pending_approval_interval?(interval) ->
        dgettext("booking", "Pending approval (%{time})", time: time)

      non_blocking_interval?(interval) ->
        dgettext("booking", "Not blocking (%{time})", time: time)

      true ->
        dgettext("booking", "Busy (%{time})", time: time)
    end
  end

  # Text for the "+x more" chip's hover tooltip — same label as a visible
  # chip, one per hidden interval, so a visitor can see what's overflowing
  # without leaving the month view.
  defp overflow_title(hidden_chips, day, timezone, time_format) do
    Enum.map_join(hidden_chips, "\n", &chip_label(&1, day, timezone, time_format))
  end

  # Only computed when the organiser has opted in — cheap either way (a
  # handful of integrations), but no reason to query when it won't render.
  defp integration_colors(%{public_calendar_colors: true, user_id: user_id}) do
    user_id
    |> CalendarGrid.list_active_integrations()
    |> CalendarGrid.integration_colour_classes()
  end

  defp integration_colors(_profile), do: %{}

  defp parse_month(nil), do: beginning_of_month(Date.utc_today())

  defp parse_month(month_param) do
    case Date.from_iso8601("#{month_param}-01") do
      {:ok, date} -> beginning_of_month(date)
      {:error, _reason} -> beginning_of_month(Date.utc_today())
    end
  end

  defp beginning_of_month(date), do: Date.new!(date.year, date.month, 1)

  defp prev_month(month), do: month |> Date.add(-1) |> beginning_of_month()
  defp next_month(month), do: month |> Date.add(32) |> beginning_of_month()
  defp prev_month_param(month), do: month_param(prev_month(month))
  defp next_month_param(month), do: month_param(next_month(month))
  defp month_param(date), do: "#{date.year}-#{String.pad_leading("#{date.month}", 2, "0")}"

  defp prev_month_allowed?(month, {earliest, _latest}),
    do: Date.compare(prev_month(month), beginning_of_month(earliest)) != :lt

  defp next_month_allowed?(month, {_earliest, latest}),
    do: Date.compare(next_month(month), beginning_of_month(latest)) != :gt

  defp to_utc(date, time, timezone) do
    date
    |> DateTime.new!(time, timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp chips_for(busy_intervals, day, timezone) do
    day_start = to_utc(day, ~T[00:00:00], timezone)
    day_end = DateTime.add(day_start, 1, :day)

    busy_intervals
    |> Enum.filter(fn {busy_start, busy_end, _calendar_integration_id} ->
      DateTime.compare(day_start, busy_end) == :lt and
        DateTime.compare(day_end, busy_start) == :gt
    end)
    |> Enum.sort_by(&elem(&1, 0), DateTime)
  end

  defp chip_color_class(:pending_approval, _integration_colors),
    do: "public-calendar-chip--pending"

  defp chip_color_class(:non_blocking, _integration_colors),
    do: "public-calendar-chip--non-blocking"

  defp chip_color_class(_calendar_integration_id, integration_colors)
       when integration_colors == %{},
       do: "public-calendar-chip--default"

  defp chip_color_class(calendar_integration_id, integration_colors),
    do: Map.get(integration_colors, calendar_integration_id, "bg-calendar-fallback")

  # Clamps the interval to this day's boundaries (a busy block spanning
  # midnight shows only the portion that falls on the day it's rendered on)
  # and renders it in the organiser's local time, not UTC.
  defp format_interval(
         {busy_start, busy_end, _calendar_integration_id},
         day,
         timezone,
         time_format
       ) do
    day_start = to_utc(day, ~T[00:00:00], timezone)
    day_end = DateTime.add(day_start, 1, :day)

    clamped_start =
      if DateTime.compare(busy_start, day_start) == :lt, do: day_start, else: busy_start

    clamped_end = if DateTime.compare(busy_end, day_end) == :gt, do: day_end, else: busy_end

    if clamped_start == day_start and clamped_end == day_end do
      dgettext("booking", "All day")
    else
      local_start = DateTime.shift_zone!(clamped_start, timezone)
      local_end = DateTime.shift_zone!(clamped_end, timezone)

      "#{TimeFormat.format(local_start, time_format)}–#{TimeFormat.format(local_end, time_format)}"
    end
  end

  # With `public_calendar_show_weekends` off the grid is Monday to Friday,
  # unless a weekend day it shows can be booked: inside the booking window and
  # open in the organiser's schedule. Hiding that day would hide the way to
  # book it, so the weekend columns stay for that month.
  defp show_weekends?(%{public_calendar_show_weekends: true}, _days, _range, _schedule),
    do: true

  defp show_weekends?(_profile, days, range, schedule) do
    days
    |> Enum.filter(&(weekend?(&1) and bookable?(&1, range)))
    |> Calculate.any_business_day?(schedule && schedule.id)
  end

  defp weekend?(day), do: Date.day_of_week(day) in [6, 7]

  defp bookable_range(schedule, tz, today) do
    min_advance_hours = Schedules.policy(schedule, :min_advance_hours)
    advance_booking_days = Schedules.policy(schedule, :advance_booking_days)

    now = DateTime.shift_zone!(DateTime.utc_now(), tz)
    earliest = now |> DateTime.add(min_advance_hours * 3600, :second) |> DateTime.to_date()
    latest = Date.add(today, advance_booking_days)
    {earliest, latest}
  end

  defp bookable?(day, {earliest, latest}) do
    Date.compare(day, earliest) != :lt and Date.compare(day, latest) != :gt
  end

  # Every month-start from the earliest to the latest bookable date, inclusive —
  # the options offered by the month picker.
  defp bookable_months({earliest, latest}) do
    start_month = beginning_of_month(earliest)
    end_month = beginning_of_month(latest)

    start_month
    |> Stream.iterate(&(&1 |> Date.add(32) |> beginning_of_month()))
    |> Enum.take_while(&(Date.compare(&1, end_month) != :gt))
  end

  defp public_calendar_day_class(day, month, today, range) do
    [
      day.month != month.month && "public-calendar-day--other-month",
      Date.compare(day, today) == :eq && "public-calendar-day--today",
      if(bookable?(day, range),
        do: "public-calendar-day--bookable",
        else: "public-calendar-day--unavailable"
      )
    ]
  end

  defp day_url(username, day), do: "/#{username}?date=#{Date.to_iso8601(day)}"

  # LocaleFormat's weekday lists are Sunday-first; the grid starts on Monday
  # (see PreferenceHelpers.month_matrix(month, :monday) above).
  defp monday_first_weekday_names(locale) do
    [sunday | rest] = LocaleFormat.get_weekday_names(locale, :short)
    rest ++ [sunday]
  end

  defp month_label(date, locale),
    do: "#{LocaleFormat.format_month_name(date.month, locale)} #{date.year}"
end
