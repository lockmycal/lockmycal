defmodule TymeslotWeb.Live.Dashboard.EmbedSettings.AliasSection do
  @moduledoc """
  The "Hidden widget address" card of the embed settings: the booking
  widget's alias (`Tymeslot.Profiles.EmbedAlias`), which replaces the username
  in the widget's URLs so the snippet does not reveal the public booking page.

  Locked with the Pro notice when `embed_alias_allowed` is false. Replacing or
  removing an alias breaks the snippets already in use, so both go through a
  confirmation; the events are handled by `EmbedSettingsComponent` (`@myself`).
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Dashboard.ProBadge
  alias TymeslotWeb.Components.Dashboard.ProNotice

  attr :embed_alias, :string, default: nil
  attr :embed_alias_allowed, :boolean, required: true
  attr :alias_change, :atom, default: nil, values: [nil, :regenerate, :remove]
  attr :myself, :any, required: true

  @spec alias_section(map()) :: Phoenix.LiveView.Rendered.t()
  def alias_section(assigns) do
    ~H"""
    <div
      id="embed-alias-section"
      class="mt-6 bg-white rounded-token-2xl border-2 border-neutral-200 p-8 dark:bg-twilight-indigo-950 dark:border-twilight-indigo-800"
    >
      <div class="flex items-center gap-3 mb-2">
        <.icon name="hero-eye-slash" class="w-6 h-6 text-amber-600" />
        <h2 class="text-token-lg font-semibold text-neutral-900 dark:text-neutral-50">
          {dgettext("dashboard_embed", "Hidden widget address")}
        </h2>
        <ProBadge.pro_badge :if={!@embed_alias_allowed} />
      </div>
      <p class="text-neutral-600 dark:text-neutral-300">
        {dgettext(
          "dashboard_embed",
          "Use a random address in the widget instead of your username, so the code on your website does not reveal your public booking page. Through it, visitors see only the meeting types shown in the widget and the ones hidden from your public page."
        )}
      </p>

      <div class="mt-6 space-y-4">
        <%= if @embed_alias do %>
          <div class="flex flex-wrap items-center gap-3">
            <code
              id="embed-alias-value"
              class="px-3 py-2 rounded-token-lg bg-neutral-100 text-neutral-800 border border-neutral-300 text-token-sm dark:bg-twilight-indigo-900 dark:text-neutral-100 dark:border-twilight-indigo-800"
            >
              {@embed_alias}
            </code>
            <.action_button
              :if={@embed_alias_allowed}
              variant={:secondary}
              phx-click="ask_embed_alias_change"
              phx-value-change="regenerate"
              phx-target={@myself}
            >
              {dgettext("dashboard_embed", "Generate a new address")}
            </.action_button>
            <.action_button
              :if={@embed_alias_allowed}
              variant={:danger_soft}
              phx-click="ask_embed_alias_change"
              phx-value-change="remove"
              phx-target={@myself}
            >
              {dgettext("dashboard_embed", "Remove")}
            </.action_button>
          </div>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_embed",
              "The embed code on the Embed Options tab already uses this address."
            )}
          </p>
        <% else %>
          <.action_button
            :if={@embed_alias_allowed}
            variant={:primary}
            phx-click="generate_embed_alias"
            phx-target={@myself}
          >
            {dgettext("dashboard_embed", "Create a hidden address")}
          </.action_button>
        <% end %>

        <ProNotice.pro_notice :if={!@embed_alias_allowed} data-testid="embed-alias-pro-note">
          {dgettext(
            "dashboard_embed",
            "The hidden widget address is only available on the Pro plan and above."
          )}
        </ProNotice.pro_notice>
      </div>

      <.confirm_modal
        id="embed-alias-change-modal"
        show={@alias_change != nil}
        size={:small}
        title={change_title(@alias_change)}
        confirm_label={change_label(@alias_change)}
        on_cancel={JS.push("cancel_embed_alias_change", target: @myself)}
        on_confirm={JS.push("confirm_embed_alias_change", target: @myself)}
      >
        <p>
          {dgettext(
            "dashboard_embed",
            "The current address stops working at once. Every website that embeds the widget with it must get the new embed code."
          )}
        </p>
      </.confirm_modal>
    </div>
    """
  end

  defp change_title(:remove), do: dgettext("dashboard_embed", "Remove the hidden address?")
  defp change_title(_regenerate), do: dgettext("dashboard_embed", "Generate a new address?")

  defp change_label(:remove), do: dgettext("dashboard_embed", "Remove")
  defp change_label(_regenerate), do: dgettext("dashboard_embed", "Generate a new address")
end
