defmodule TymeslotWeb.Components.Dashboard.Integrations.Calendar.ConnectionLimit do
  @moduledoc """
  The user-facing side of the per-user calendar connection limit
  (`Tymeslot.Integrations.Calendar.connection_limit/1`): the one refusal
  message every connect path shows, and the usage notice on the Calendars
  page. Renders nothing while the limit is `:unlimited`, so a deployment
  whose feature checker imposes no limit (Core's default) sees no change.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  @doc "Why a new calendar connection was refused."
  @spec limit_reached_message() :: String.t()
  def limit_reached_message do
    dgettext(
      "dashboard_calendar_settings",
      "You have reached the maximum number of connected calendars for your plan. Remove one to connect another."
    )
  end

  @doc "Why turning a paused calendar back on was refused."
  @spec activation_limit_message() :: String.t()
  def activation_limit_message do
    dgettext(
      "dashboard_calendar_settings",
      "Your plan allows only this many active calendars. Pause an active calendar before turning this one back on."
    )
  end

  @doc "Renders the user's calendar usage against their limit."
  attr :limit, :map,
    required: true,
    doc: "a `Tymeslot.Integrations.Calendar.connection_limit/1` result"

  @spec connection_limit_notice(map()) :: Phoenix.LiveView.Rendered.t()
  def connection_limit_notice(%{limit: %{limit: :unlimited}} = assigns), do: ~H""

  def connection_limit_notice(assigns) do
    assigns = assign(assigns, :paused_blocked?, paused_blocked?(assigns.limit))

    ~H"""
    <.info_box
      variant={if @limit.reached? or @paused_blocked?, do: :warning, else: :info}
      class="connection-limit-notice"
    >
      {dgettext(
        "dashboard_calendar_settings",
        "Active calendars: %{active} of %{limit}.",
        active: @limit.active,
        limit: @limit.limit
      )}
      <span :if={@limit.reached?}>{limit_reached_message()}</span>
      <span :if={@paused_blocked?}>
        {dgettext(
          "dashboard_calendar_settings",
          "To turn a paused calendar back on, pause an active one first."
        )}
      </span>
    </.info_box>
    """
  end

  defp paused_blocked?(limit), do: limit.activation_reached? and limit.count > limit.active
end
