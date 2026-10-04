defmodule TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachments do
  @moduledoc """
  Dashboard widgets for the files a booker attached to their booking
  (`Tymeslot.Bookings.AttendeeAttachments`): the paperclip badge on a
  booking card, the smaller paperclip marker on a calendar event, and the
  list of download links.

  Shared by the bookings list, the calendar grid's booking detail and the
  approval request page, so a meeting with attachments reads the same
  everywhere. Download links point at `TymeslotWeb.MeetingAttachmentController`,
  which only serves the meeting's organiser; callers render `links/1` for the
  organiser only.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext
  use TymeslotWeb, :verified_routes

  alias TymeslotWeb.Components.CoreComponents

  @doc "Pill with a paperclip and the number of files, for a booking card's header."
  attr :attachments, :list, required: true

  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  def badge(assigns) do
    ~H"""
    <span
      :if={@attachments != []}
      class="inline-flex items-center gap-1.5 px-3 py-1 bg-neutral-50 dark:bg-twilight-indigo-900 text-neutral-700 dark:text-neutral-300 text-token-xs font-black uppercase tracking-wider rounded-full border border-neutral-200 dark:border-twilight-indigo-700 shadow-sm"
      title={dgettext("dashboard_bookings", "Has attachments")}
      data-testid="attachments-badge"
    >
      <CoreComponents.icon name="hero-paper-clip" class="w-3.5 h-3.5" />
      {dgettext("dashboard_bookings", "Attachments (%{count})", count: length(@attachments))}
    </span>
    """
  end

  @doc "Bare paperclip in front of a calendar event's title."
  attr :attachments, :list, default: []
  attr :class, :string, default: "inline-block w-3 h-3 opacity-70 mr-0.5 align-text-bottom"

  @spec marker(map()) :: Phoenix.LiveView.Rendered.t()
  def marker(assigns) do
    ~H"""
    <%!-- phx-no-format: whitespace around the icon would render as a gap
         before the event title it sits against. --%>
    <span
      :if={(@attachments || []) != []}
      role="img"
      title={dgettext("dashboard_bookings", "Has attachments")}
      aria-label={dgettext("dashboard_bookings", "Has attachments")}
      data-testid="attachments-marker"
      phx-no-format
    ><CoreComponents.icon name="hero-paper-clip-micro" class={@class} /></span>
    """
  end

  @doc "Download links for each attached file, with its size."
  attr :meeting_id, :string, required: true
  attr :attachments, :list, required: true
  attr :class, :string, default: nil

  @spec links(map()) :: Phoenix.LiveView.Rendered.t()
  def links(assigns) do
    ~H"""
    <ul :if={(@attachments || []) != []} class={["space-y-2", @class]}>
      <li :for={attachment <- @attachments} class="flex items-center justify-between gap-3">
        <a
          href={~p"/dashboard/meetings/#{@meeting_id}/attachments/#{attachment["id"]}"}
          class="flex items-center gap-2 min-w-0 text-token-sm font-bold text-primary-700 dark:text-primary-300 hover:underline"
          download
        >
          <CoreComponents.icon name="hero-arrow-down-tray" class="w-4 h-4 shrink-0" />
          <span class="truncate">{attachment["filename"]}</span>
        </a>
        <span class="shrink-0 text-token-xs font-medium text-neutral-500 dark:text-neutral-400">
          {format_size(attachment["byte_size"])}
        </span>
      </li>
    </ul>
    """
  end

  defp format_size(bytes) when is_integer(bytes) and bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp format_size(bytes) when is_integer(bytes), do: "#{max(1, div(bytes, 1000))} kB"
  defp format_size(_unknown), do: ""
end
