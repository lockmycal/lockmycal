defmodule TymeslotWeb.Components.Dashboard.LocaleTabSwitcher do
  @moduledoc """
  Language tab-switcher for editing per-locale translations of
  organizer-authored text (meeting-type name/description, the profile's
  booking-page welcome text).

  A thin wrapper around `<.option_toggle>` with one pill per supported
  locale. The caller decides what "active" means: by convention, the pill
  whose code equals `Tymeslot.Locales.default_locale/0` shows/edits the
  owning record's base field(s) directly, and every other pill shows/edits
  that locale's row in the record's translations list.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Locales

  attr :active_value, :string, required: true
  attr :click_event, :string, required: true
  attr :target, :any, default: nil

  @spec locale_tab_switcher(map()) :: Phoenix.LiveView.Rendered.t()
  def locale_tab_switcher(assigns) do
    options = Enum.map(Locales.supported_codes(), &{&1, String.upcase(&1)})
    assigns = assign(assigns, :options, options)

    ~H"""
    <.option_toggle
      options={@options}
      active_value={@active_value}
      click_event={@click_event}
      target={@target}
      aria_label={dgettext("dashboard_common", "Language")}
    />
    """
  end
end
