defmodule TymeslotWeb.Dashboard.ProfileSettings.LanguageFormComponent do
  @moduledoc """
  Language form component for the Profile page.

  Lets the organiser choose the admin dashboard's display language. Backed
  by `user.locale` — the same field and resolution chain used everywhere
  else in the dashboard (`Tymeslot.Auth.update_user_locale/2`,
  `TymeslotWeb.Hooks.AppLocaleHook`: a URL-prefixed locale wins outright,
  then this saved preference, then the session locale, then the app
  default). Moved here from the old standalone `/dashboard/account` page's
  `language_card`, matching every other Profile Settings block.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Auth
  alias Tymeslot.Locales
  alias TymeslotWeb.Live.Shared.Flash

  @impl Phoenix.LiveComponent
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    locale = if locale in [nil, ""], do: nil, else: locale

    case Auth.update_user_locale(socket.assigns.current_user, locale) do
      {:ok, updated_user} ->
        # Full remount (not a plain assign update) so every `dgettext/2` call
        # re-evaluates in the new locale — LiveView only re-diffs a template
        # expression when an @assign it reads changes, and gettext calls read
        # none. `put_flash/3` (not `Flash.put_flash/3`) paired with
        # `push_navigate/2` in the same return is required here: forwarding
        # via `send/2` would race the process teardown a navigate triggers,
        # same as `PasswordSettingsFormComponent`'s post-change redirect.
        new_locale = Locales.acceptable(updated_user.locale) || Locales.default_locale()
        Gettext.put_locale(new_locale)

        # credo:disable-for-lines:4 CredoChecks.PutFlashInLiveComponent
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_profile", "Language preference saved."))
         |> push_navigate(to: ~p"/dashboard/settings")}

      {:error, _changeset} ->
        {:noreply,
         Flash.put_flash(
           socket,
           :error,
           dgettext("dashboard_profile", "Could not save language preference.")
         )}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="language-form-container">
      <.subsection_header
        icon="hero-language"
        title={dgettext("dashboard_profile", "Language")}
        class="mb-3"
      />
      <.form_wrapper for={%{}} phx-change="change_locale" phx-target={@myself} id="language-form">
        <.input
          type="select"
          name="locale"
          value={@current_user.locale || ""}
          options={locale_options()}
        />
      </.form_wrapper>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext(
          "dashboard_profile",
          "Changes the language of this admin dashboard. Does not affect the language visitors see on your booking page."
        )}
      </p>
    </div>
    """
  end

  defp locale_options do
    [
      {dgettext("dashboard_profile", "Automatic"), ""}
      | Enum.map(Locales.supported(), &{&1.name, &1.code})
    ]
  end
end
