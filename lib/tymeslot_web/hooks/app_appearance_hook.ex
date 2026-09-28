defmodule TymeslotWeb.Hooks.AppAppearanceHook do
  @moduledoc """
  LiveView hook that resolves the authenticated dashboard's light/dark class
  from the signed-in user's saved appearance preference, mirroring
  AppLocaleHook.

  Must run *after* the auth hook has assigned `:current_user` — it is placed
  in the dashboard hook chain right after `AppLocaleHook`.
  """

  import Phoenix.Component

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    preference = user_theme_preference(socket)

    # "light"/"dark" resolve to a concrete class up front — no flash, ever.
    # An unset preference ("system") can't be resolved server-side (the OS
    # setting isn't visible to the server), so it's left nil here and handled
    # by a small inline bootstrap script in root.html.heex instead.
    html_class =
      case preference do
        "dark" -> "dark"
        "light" -> ""
        _system -> nil
      end

    {:cont,
     assign(socket,
       appearance_preference: preference || "system",
       appearance_html_class: html_class
     )}
  end

  defp user_theme_preference(socket) do
    case socket.assigns[:current_user] do
      %{theme_preference: pref} when is_binary(pref) -> pref
      _other -> nil
    end
  end
end
