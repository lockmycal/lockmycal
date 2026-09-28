defmodule Tymeslot.Dashboard.Admin.SettingsTab do
  @moduledoc """
  Behaviour for an extra tab in the admin panel's settings tab bar
  (`TymeslotWeb.AdminLive.Tabs`), for settings Core itself has no
  `app_settings` column for.

  Same rationale as `Tymeslot.Dashboard.Admin.UserColumn`: Core defines the
  contract, an external application (e.g. a paid overlay wanting admins to
  configure per-plan limits) implements it and registers itself — Core never
  names the external application, imports from it, or checks whether one is
  present.

  ## Usage

  Register one or more modules via `config/runtime.exs`:

      config :tymeslot, :admin_settings_extra_tabs, [
        MyApp.Dashboard.Admin.PlansTab
      ]

  Each renders after the built-in tabs, in list order. An empty or unset list
  (the default) leaves the admin panel exactly as it is.

  The tab's content almost always handles its own events, typically as a
  nested `Phoenix.LiveComponent`. Those events skip `DashboardLive`'s admin
  gate, so the content must re-check that `viewer` is still an admin itself
  on every state-changing event, the same way
  `TymeslotWeb.Dashboard.Admin.HubComponent` does.

      defmodule MyApp.Dashboard.Admin.PlansTab do
        @behaviour Tymeslot.Dashboard.Admin.SettingsTab

        use Phoenix.Component

        @impl true
        def id, do: :plans

        @impl true
        def name, do: "Plans"

        @impl true
        def render(viewer) do
          assigns = %{viewer_id: viewer.id}

          ~H\"\"\"
          <.live_component module={MyApp.PlansForm} id="plans-form" viewer_id={@viewer_id} />
          \"\"\"
        end
      end
  """

  alias Tymeslot.Auth.UserSchema

  @doc "The tab's identifier; must not collide with a built-in tab."
  @callback id() :: atom()

  @doc "Tab label, already translated if applicable."
  @callback name() :: String.t()

  @doc "Renders the tab's content for the admin currently viewing it."
  @callback render(viewer :: UserSchema.t()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Reads the registered extra-tab modules from config. Not validated, for the
  same reason `Tymeslot.Dashboard.Admin.UserColumn.registered/0` isn't: the
  list is short, developer-authored, and a misbehaving module surfaces
  immediately as a rendering crash.
  """
  @spec registered() :: [module()]
  def registered do
    Application.get_env(:tymeslot, :admin_settings_extra_tabs, [])
  end

  @doc "The registered module whose `id/0` is `tab`, if any."
  @spec find(atom()) :: module() | nil
  def find(tab) when is_atom(tab), do: Enum.find(registered(), &(&1.id() == tab))
end
