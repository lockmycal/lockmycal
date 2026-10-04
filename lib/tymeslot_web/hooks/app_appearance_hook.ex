defmodule TymeslotWeb.Hooks.AppAppearanceHook do
  @moduledoc """
  LiveView hook that resolves the authenticated dashboard's light/dark class
  from the signed-in user's saved appearance preference, mirroring
  AppLocaleHook.

  Must run *after* the auth hook has assigned `:current_user` — it is placed
  in the dashboard hook chain right after `AppLocaleHook`.

  It also saves the choice made in the top bar's appearance switch
  (`DashboardLayout`), whose `change_appearance` event reaches whichever
  dashboard LiveView renders the layout. Handled here, every one of them
  takes it, rather than each needing its own clause.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Tymeslot.Auth

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
     socket
     |> assign(
       appearance_preference: preference || "system",
       appearance_html_class: html_class
     )
     |> attach_hook(:appearance_switch, :handle_event, &save_appearance/3)}
  end

  # "system" is stored as no preference. The hook on the switch has already
  # applied the choice on the page; this only saves it.
  defp save_appearance("change_appearance", %{"option" => option}, socket) do
    preference = if option == "system", do: nil, else: option

    case Auth.update_user_theme_preference(socket.assigns.current_user, preference) do
      {:ok, user} ->
        {:halt,
         assign(socket,
           current_user: user,
           appearance_preference: user.theme_preference || "system"
         )}

      {:error, _changeset} ->
        {:halt, socket}
    end
  end

  defp save_appearance(_event, _params, socket), do: {:cont, socket}

  defp user_theme_preference(socket) do
    case socket.assigns[:current_user] do
      %{theme_preference: pref} when is_binary(pref) -> pref
      _other -> nil
    end
  end
end
