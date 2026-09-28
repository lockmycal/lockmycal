defmodule TymeslotWeb.Components.Dashboard.ProBadge do
  @moduledoc """
  Small "Pro" pill marking a feature gated behind a paid plan. Used next to
  locked sidebar nav items (`DashboardSidebar`) and locked in-page actions
  (e.g. the meeting-type "Change link" button in
  `ServiceSettings.ComponentView`) — extracted here once it had a second
  caller, per the shared-widget convention.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :class, :string, default: nil
  attr :rest, :global

  @spec pro_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def pro_badge(assigns) do
    ~H"""
    <span
      class={[
        "ml-auto text-xs bg-tertiary-50 text-tertiary-800 px-2 py-0.5 rounded font-semibold",
        @class
      ]}
      {@rest}
    >
      {dgettext("dashboard_common", "Pro")}
    </span>
    """
  end
end
