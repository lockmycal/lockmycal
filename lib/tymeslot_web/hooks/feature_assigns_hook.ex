defmodule TymeslotWeb.Hooks.FeatureAssignsHook do
  @moduledoc """
  Sets default feature assigns from config.

  This hook reads feature flags from application config and sets them as assigns.
  All features default to `true` (allowed) in core.

  SaaS can register additional hooks via config to override these defaults
  based on subscription status or other business logic.
  """

  import Phoenix.Component

  @spec on_mount(:set_feature_assigns, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:set_feature_assigns, _params, _session, socket) do
    feature_assigns = Application.get_env(:tymeslot, :feature_assigns, [])

    socket =
      Enum.reduce(feature_assigns, socket, fn {key, default_value}, acc ->
        assign(acc, key, default_value)
      end)

    {:cont, socket}
  end
end
