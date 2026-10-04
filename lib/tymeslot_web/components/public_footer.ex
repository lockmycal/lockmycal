defmodule TymeslotWeb.Components.PublicFooter do
  @moduledoc """
  Shared footer for unauthenticated public-facing pages that use a scheduling
  theme's CSS (the booking flow, the public read-only calendar), the bottom
  counterpart of `TymeslotWeb.Components.PublicTopBar`. It fills the themes'
  `theme-grid` second row and is skinned by each theme's
  `modules/public-footer.css`.

  Shows "Powered by <app name> · v<version>" in the middle and, once
  `WEB_HOST` is set, the "Report a bug" link to the website's forum
  (`Config.bug_report_url/0`) on the right. Renders nothing on embedded pages.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config

  import TymeslotWeb.Components.CoreComponents, only: [icon: 1]

  attr :embedded, :boolean, default: false

  @spec public_footer(map()) :: Phoenix.LiveView.Rendered.t()
  def public_footer(assigns) do
    assigns = assign(assigns, :bug_report_url, Config.bug_report_url())

    ~H"""
    <footer :if={!@embedded} class="public-footer">
      <span class="public-footer-powered">
        {dgettext("common", "Powered by %{app_name}", app_name: Config.app_name())} · v{to_string(
          Application.spec(:tymeslot, :vsn)
        )}
      </span>
      <a
        :if={@bug_report_url}
        href={@bug_report_url}
        target="_blank"
        rel="noopener noreferrer"
        class="public-footer-link"
      >
        <.icon name="hero-bug-ant" class="w-4 h-4" />
        {dgettext("common", "Report a bug")}
      </a>
    </footer>
    """
  end
end
