defmodule Tymeslot.Dashboard.OverviewWidget do
  @moduledoc """
  Behaviour for an extra widget in the dashboard Overview's side column
  (`TymeslotWeb.Dashboard.DashboardOverview.ComponentView`), after the
  built-in widgets.

  Same rationale as `Tymeslot.Dashboard.Admin.SettingsTab`: Core defines the
  contract, an external application (e.g. a paid overlay showing the user's
  subscription) implements it and registers itself — Core never names the
  external application, imports from it, or checks whether one is present.

  ## Usage

  Register one or more modules via `config/runtime.exs`:

      config :tymeslot, :dashboard_overview_extra_widgets, [
        MyApp.Dashboard.PlanWidget
      ]

  Each renders in list order. An empty or unset list (the default) leaves the
  Overview exactly as it is.

  `render/1` returns the widget's whole card (usually a `card-glass` block), or
  `nil` to show nothing for this user. It is called on every Overview render —
  including the 60-second agenda refresh — so it should read from a cache or
  assigns-cheap source rather than run slow queries. A widget that handles its
  own events should render a nested `Phoenix.LiveComponent`.

      defmodule MyApp.Dashboard.PlanWidget do
        @behaviour Tymeslot.Dashboard.OverviewWidget

        use Phoenix.Component

        @impl true
        def id, do: :plan

        @impl true
        def render(user) do
          assigns = %{plan: MyApp.plan_name(user)}

          ~H\"\"\"
          <div class="card-glass">{@plan}</div>
          \"\"\"
        end
      end
  """

  alias Tymeslot.Auth.UserSchema

  @doc "The widget's identifier; used as its DOM id suffix, so keep it unique."
  @callback id() :: atom()

  @doc "Renders the widget for the user viewing the Overview, or `nil` to skip it."
  @callback render(user :: UserSchema.t()) :: Phoenix.LiveView.Rendered.t() | nil

  @doc """
  Reads the registered widget modules from config. Not validated, for the same
  reason `Tymeslot.Dashboard.Admin.SettingsTab.registered/0` isn't: the list is
  short, developer-authored, and a misbehaving module surfaces immediately as a
  rendering crash.
  """
  @spec registered() :: [module()]
  def registered do
    Application.get_env(:tymeslot, :dashboard_overview_extra_widgets, [])
  end
end
