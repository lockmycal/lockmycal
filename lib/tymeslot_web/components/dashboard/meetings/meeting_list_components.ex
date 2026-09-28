defmodule TymeslotWeb.Components.Dashboard.Meetings.MeetingListComponents do
  @moduledoc """
  UI components for displaying and filtering meetings in the dashboard.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Components.Dashboard.Meetings.MeetingCardComponents

  # Filter Tabs
  attr :active, :string, required: true
  attr :upcoming_count, :integer, default: 0
  attr :past_count, :integer, default: 0
  attr :cancelled_count, :integer, default: 0
  attr :target, :any, required: true
  attr :awaiting_approval_count, :integer, default: 0

  @spec filter_tabs(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_tabs(assigns) do
    ~H"""
    <div class="flex bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-800 rounded-[1.25rem] p-1.5 shadow-sm max-w-fit">
      <.filter_tab_button
        active={@active == "upcoming"}
        filter="upcoming"
        label={dgettext("dashboard_bookings", "Upcoming (%{count})", count: @upcoming_count)}
        icon="hero-clock"
        target={@target}
      />
      <.filter_tab_button
        active={@active == "past"}
        filter="past"
        label={dgettext("dashboard_bookings", "Past (%{count})", count: @past_count)}
        icon="hero-calendar-days"
        target={@target}
      />
      <.filter_tab_button
        active={@active == "cancelled"}
        filter="cancelled"
        label={dgettext("dashboard_bookings", "Cancelled (%{count})", count: @cancelled_count)}
        icon="hero-x-mark"
        target={@target}
      />
      <%!-- Only shown once there is something to answer: a host who requires no
            approvals should never see a tab that is permanently empty. --%>
      <.filter_tab_button
        :if={@awaiting_approval_count > 0 or @active == "awaiting_approval"}
        active={@active == "awaiting_approval"}
        filter="awaiting_approval"
        label={dgettext("dashboard_bookings", "Requests")}
        icon="hero-inbox-arrow-down"
        count={@awaiting_approval_count}
        target={@target}
      />
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :filter, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :target, :any, required: true
  attr :count, :integer, default: 0

  defp filter_tab_button(assigns) do
    ~H"""
    <button
      phx-click="filter_meetings"
      phx-value-filter={@filter}
      phx-target={@target}
      class={[
        "flex items-center space-x-2 px-6 py-2.5 rounded-token-xl text-token-sm font-black transition-all duration-300 cursor-pointer",
        if(@active,
          do: "bg-linear-to-br from-primary-600 to-secondary-600 text-white",
          else:
            "text-neutral-500 dark:text-neutral-400 hover:text-primary-600 hover:bg-primary-50 dark:hover:bg-twilight-indigo-900"
        )
      ]}
    >
      <CoreComponents.icon name={@icon} class={if @active, do: "text-white/90", else: ""} />
      <span>{@label}</span>
      <span
        :if={@count > 0}
        class={[
          "ml-1 inline-flex items-center justify-center min-w-[1.375rem] h-5.5 px-1.5 rounded-full text-token-xs font-black tabular-nums",
          if(@active, do: "bg-white/25 text-white", else: "bg-amber-100 text-amber-700")
        ]}
      >
        {@count}
      </span>
    </button>
    """
  end

  # Meetings List
  attr :loading, :boolean, required: true
  attr :is_empty, :boolean, required: true
  attr :filter, :string, required: true
  attr :profile, :any, required: false
  attr :time_format, :string, required: true
  attr :cancelling_meeting, :any, required: false
  attr :sending_reschedule, :any, required: false
  attr :answering_request, :any, default: nil
  attr :deleting_meeting, :any, required: false
  attr :target, :any, required: true
  attr :meetings_stream, :any, required: true

  @spec meetings_list(map()) :: Phoenix.LiveView.Rendered.t()
  def meetings_list(assigns) do
    ~H"""
    <div>
      <.loading_spinner :if={@loading} />
      <.empty_state :if={!@loading and @is_empty} filter={@filter} />
      <div :if={!@loading and !@is_empty} class="space-y-4" id="meetings" phx-update="stream">
        <div :for={{dom_id, meeting} <- @meetings_stream} id={dom_id}>
          <MeetingCardComponents.meeting_card
            meeting={meeting}
            profile={@profile}
            time_format={@time_format}
            cancelling_meeting={@cancelling_meeting}
            sending_reschedule={@sending_reschedule}
            answering_request={@answering_request}
            deleting_meeting={@deleting_meeting}
            target={@target}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :filter, :string, required: true

  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_state(assigns) do
    ~H"""
    <div class="card-glass py-20">
      <div class="text-center max-w-sm mx-auto">
        <div class="w-24 h-24 mx-auto mb-8 rounded-token-3xl bg-neutral-50 flex items-center justify-center border-2 border-neutral-300 shadow-sm transition-transform hover:scale-110 hover:rotate-3 duration-500">
          <CoreComponents.icon name="hero-calendar-days" class="w-12 h-12 text-neutral-300" />
        </div>
        <h3 class="text-token-2xl font-black text-neutral-900 dark:text-neutral-50 tracking-tight mb-3">
          <%= case @filter do %>
            <% "upcoming" -> %>
              {dgettext("dashboard_bookings", "No upcoming meetings")}
            <% "past" -> %>
              {dgettext("dashboard_bookings", "No past meetings")}
            <% "cancelled" -> %>
              {dgettext("dashboard_bookings", "No cancelled meetings")}
            <% "awaiting_approval" -> %>
              {dgettext("dashboard_bookings", "Nothing waiting on you")}
          <% end %>
        </h3>
        <p class="text-neutral-500 font-medium text-lg leading-relaxed">
          <%= case @filter do %>
            <% "upcoming" -> %>
              {dgettext(
                "dashboard_bookings",
                "Your upcoming appointments will appear here automatically."
              )}
            <% "past" -> %>
              {dgettext("dashboard_bookings", "You haven't had any meetings in this period yet.")}
            <% "cancelled" -> %>
              {dgettext(
                "dashboard_bookings",
                "You don't have any cancelled appointments to show."
              )}
            <% "awaiting_approval" -> %>
              {dgettext(
                "dashboard_bookings",
                "Booking requests you haven't answered yet will appear here."
              )}
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  @doc "Displays a loading spinner inside a card."
  @spec loading_spinner(map()) :: Phoenix.LiveView.Rendered.t()
  def loading_spinner(assigns) do
    ~H"""
    <div class="card-glass">
      <div class="flex items-center justify-center py-12">
        <CoreComponents.spinner class="h-8 w-8 text-primary-600" />
      </div>
    </div>
    """
  end

  @doc "Displays an informational panel about meeting management features."
  @spec info_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def info_panel(assigns) do
    ~H"""
    <div class="card-glass p-8 lg:p-12 relative overflow-hidden group/info">
      <div class="absolute top-0 right-0 -mr-16 -mt-16 w-64 h-64 bg-primary-500/5 rounded-full blur-3xl transition-colors group-hover/info:bg-primary-500/10">
      </div>

      <div class="flex flex-col lg:flex-row gap-12 relative z-10">
        <div class="flex-1">
          <p class="text-neutral-500 font-bold text-lg leading-relaxed max-w-2xl mb-8">
            {dgettext(
              "dashboard_bookings",
              "Manage all your scheduled meetings in one place. Filter by status and take quick actions on your appointments."
            )}
          </p>

          <div class="flex flex-wrap gap-4">
            <span class="inline-flex items-center gap-2 px-4 py-2 bg-neutral-50 dark:bg-twilight-indigo-900/60 text-neutral-600 dark:text-neutral-300 rounded-token-xl text-token-sm font-black border border-neutral-300 shadow-sm">
              <div class="w-2 h-2 rounded-full bg-primary-500"></div>
              {dgettext("dashboard_bookings", "Real-time updates")}
            </span>
            <span class="inline-flex items-center gap-2 px-4 py-2 bg-neutral-50 dark:bg-twilight-indigo-900/60 text-neutral-600 dark:text-neutral-300 rounded-token-xl text-token-sm font-black border border-neutral-300 shadow-sm">
              <div class="w-2 h-2 rounded-full bg-secondary-500"></div>
              {dgettext("dashboard_bookings", "Auto-notifications")}
            </span>
          </div>
        </div>

        <div class="lg:w-80 space-y-4">
          <.info_card
            icon="hero-arrows-right-left"
            title={dgettext("dashboard_bookings", "Reschedule")}
            description={dgettext("dashboard_bookings", "Change meeting times")}
            color="turquoise"
          />
          <.info_card
            icon="hero-x-mark"
            title={dgettext("dashboard_bookings", "Cancel")}
            description={dgettext("dashboard_bookings", "With auto notifications")}
            color="red"
          />
          <.info_card
            icon="hero-video-camera"
            title={dgettext("dashboard_bookings", "Join Video")}
            description={dgettext("dashboard_bookings", "Quick meeting access")}
            color="blue"
          />
        </div>
      </div>
    </div>
    """
  end

  defp info_card(assigns) do
    ~H"""
    <div class="p-5 rounded-token-2xl bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 shadow-sm hover:border-primary-100 dark:hover:border-primary-700 transition-all hover:shadow-md group/item">
      <div class="flex items-center gap-4">
        <div class={[
          "w-10 h-10 rounded-token-xl flex items-center justify-center transition-colors",
          case @color do
            "turquoise" ->
              "bg-primary-50 dark:bg-primary-950/40 group-hover/item:bg-primary-100 dark:group-hover/item:bg-primary-900 text-primary-600 dark:text-primary-400"

            "red" ->
              "bg-red-50 dark:bg-red-950/40 group-hover/item:bg-red-100 dark:group-hover/item:bg-red-900 text-red-500 dark:text-red-400"

            "blue" ->
              "bg-blue-50 dark:bg-blue-950/40 group-hover/item:bg-blue-100 dark:group-hover/item:bg-blue-900 text-blue-600 dark:text-blue-400"

            _other ->
              "bg-neutral-50 dark:bg-twilight-indigo-900/60 group-hover/item:bg-neutral-100 dark:group-hover/item:bg-twilight-indigo-800 text-neutral-600 dark:text-neutral-300"
          end
        ]}>
          <CoreComponents.icon name={@icon} class="w-5 h-5" />
        </div>
        <div>
          <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-0.5">
            {@title}
          </p>
          <p class="text-neutral-700 dark:text-neutral-200 font-bold">{@description}</p>
        </div>
      </div>
    </div>
    """
  end
end
