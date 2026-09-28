defmodule TymeslotWeb.AdminLive.Components.LocaleSetting do
  @moduledoc """
  The per-surface fallback-language control on the admin settings page.

  A `select` input (via the shared `CoreComponents.input/1`), matching the
  same language picker on Profile Settings (`LanguageFormComponent`) rather
  than the row-of-flag-buttons this used to be — the flag row scaled poorly
  as more locales are added and didn't match the rest of the settings tab's
  form controls.

  Wrapped in its own form (`phx-change`), same shape as the `:text`/`:score`
  setting controls in `SettingsView` (a hidden `key` field alongside the
  actual control) — a standalone select with `phx-change` but no ancestor
  form element fails client-side (`pushInput` requires `inputEl.form`).

  The country each locale's endonym comes from is read from the `:locales`
  config entry, so adding a language to that list is the only change a new
  option needs.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Locales
  alias TymeslotWeb.Dashboard.Admin.Formatters

  attr :key, :atom, required: true
  attr :effective, :map, required: true
  attr :disabled, :boolean, default: false
  attr :target, :any, required: true

  @spec locale_control(map()) :: Phoenix.LiveView.Rendered.t()
  def locale_control(assigns) do
    assigns = assign(assigns, :locales, Locales.supported())

    ~H"""
    <form
      id={"admin-locale-form-#{@key}"}
      phx-change="set_locale"
      phx-target={@target}
      class="shrink-0 max-w-full"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
    >
      <input type="hidden" name="key" value={Atom.to_string(@key)} />
      <.input
        type="select"
        name="locale"
        value={@effective.value || ""}
        options={locale_options(@locales)}
        disabled={@disabled}
        class="w-56 max-w-full"
      />
    </form>
    """
  end

  defp locale_options(locales) do
    [{Formatters.unset_locale_label(), ""} | Enum.map(locales, &{&1.name, &1.code})]
  end
end
